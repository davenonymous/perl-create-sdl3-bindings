# Copyright 2026 davenonymous
use v5.36;
use Object::Pad;

# Drives the clang binary: AST dumps, preprocessor output and syntax checks.
class BindGen::Clang {
	use Carp             qw(croak);
	use Cpanel::JSON::XS ();
	use Path::Tiny       qw(path);
	use Capture::Tiny    qw(capture);

	field $binary      : param;
	field $includeDirs : param = [];
	field $extraArgs   : param = [];
	field $verbose     : param = 0;

	method _baseArgs() {
		return ('-x', 'c', (map { ('-I', $_) } @$includeDirs), @$extraArgs);
	}

	# Runs clang with captured output: { exit => code, stdout => text, stderr => text }.
	# A child killed by signal N reports exit 128 + N, as the shell does.
	# $! is lost once capture restores the handles, so a failed exec is recorded inside the block.
	method _run(@args) {
		my $execError;
		my ($stdout, $stderr, $status) = capture {
			my $systemStatus = system($binary, @args);
			$execError = "$!" if $systemStatus == -1;
			$systemStatus;
		};
		croak "cannot run $binary: $execError" if defined $execError;
		my $signal = $status & 127;
		return {exit => $signal ? 128 + $signal : $status >> 8, stdout => $stdout, stderr => $stderr};
	}

	method _runOrDie($what, @args) {
		my $result = $self->_run(@args);
		croak "clang failed while $what (exit $result->{exit}):\n$result->{stderr}" if $result->{exit} != 0;
		return $result->{stdout};
	}

	# The translation unit's JSON AST as a hashref.
	method dumpAst($entryFile) {
		my $json = $self->_runOrDie("dumping the AST of $entryFile", '-fsyntax-only', '-Xclang', '-ast-dump=json', $self->_baseArgs, $entryFile);
		return Cpanel::JSON::XS->new->decode($json);
	}

	# printf/scanf format attributes per function name: { name => { style => 'printf', index => 0-based param index } }.
	# The JSON dump leaves the attribute's arguments out, the text dump has them.
	method dumpFormatAttributes($entryFile) {
		my $text = $self->_runOrDie("dumping attributes of $entryFile", '-fsyntax-only', '-Xclang', '-ast-dump', $self->_baseArgs, $entryFile);
		my %formats;
		my $currentFunction;
		foreach my $line (split /\n/, $text) {
			if ($line =~ /FunctionDecl 0x[0-9a-f]+ <[^>]*> \S+ (?:(?:used|implicit|referenced) )*(\w+) '/) {
				$currentFunction = $1;
				next;
			}
			next if $line !~ /FormatAttr 0x[0-9a-f]+ <[^>]*>(?: Inherited| Implicit)* (\w+) (\d+) (\d+)/;
			next if !defined $currentFunction;
			$formats{$currentFunction} = {style => $1, index => $2 - 1};
		}
		return \%formats;
	}

	# Macro definitions and removals in source order: [ { name, args (undef for object-like), body, file } | { name, undefined => 1, file } ].
	method dumpDefines($entryFile) {
		my $text = $self->_runOrDie("preprocessing $entryFile", '-E', '-dD', $self->_baseArgs, $entryFile);
		my @defines;
		my $currentFile = $entryFile;
		foreach my $line (split /\n/, $text) {
			if ($line =~ /^#\s*\d+\s+"([^"]*)"/) {
				$currentFile = $1;
				next;
			}
			if ($line =~ /^#\s*undef\s+(\w+)/) {
				push @defines, {name => $1, undefined => 1, file => $currentFile};
				next;
			}
			next if $line !~ /^#\s*define\s+(\w+)(\([^)]*\))?\s*(.*)$/;
			push @defines, {name => $1, args => $2, body => $3, file => $currentFile};
		}
		return \@defines;
	}

	# Syntax-checks C source text; returns { line number => first error message on that line }.
	method syntaxErrors($source, $scratchDir) {
		my $file = path($scratchDir)->child('bindgen-probe.c');
		$file->spew_utf8($source);
		my $result = $self->_run('-fsyntax-only', '-ferror-limit=0', '-w', $self->_baseArgs, "$file");
		my %errors;
		foreach my $line (split /\n/, $result->{stderr}) {
			next if $line !~ /^\Q$file\E:(\d+):\d+: error: (.*)$/;
			$errors{$1} //= $2;
		}
		return \%errors;
	}

	method version() {
		my $text = $self->_runOrDie('asking for its version', '--version');
		return (split /\n/, $text)[0];
	}
}

1;
