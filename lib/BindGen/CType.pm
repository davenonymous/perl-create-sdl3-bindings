# Copyright 2026 davenonymous
use v5.36;
use Object::Pad;

class BindGen::CType {
	use Carp qw(croak);
	use Readonly;

	Readonly my %BUILTIN_CANONICAL => (
		'void'                   => 'void',
		'_Bool'                  => '_Bool',
		'bool'                   => '_Bool',
		'char'                   => 'char',
		'signed char'            => 'signed char',
		'unsigned char'          => 'unsigned char',
		'short'                  => 'short',
		'short int'              => 'short',
		'signed short'           => 'short',
		'signed short int'       => 'short',
		'unsigned short'         => 'unsigned short',
		'unsigned short int'     => 'unsigned short',
		'int'                    => 'int',
		'signed'                 => 'int',
		'signed int'             => 'int',
		'unsigned'               => 'unsigned int',
		'unsigned int'           => 'unsigned int',
		'long'                   => 'long',
		'long int'               => 'long',
		'signed long'            => 'long',
		'signed long int'        => 'long',
		'unsigned long'          => 'unsigned long',
		'unsigned long int'      => 'unsigned long',
		'long long'              => 'long long',
		'long long int'          => 'long long',
		'signed long long'       => 'long long',
		'signed long long int'   => 'long long',
		'unsigned long long'     => 'unsigned long long',
		'unsigned long long int' => 'unsigned long long',
		'__int128'               => '__int128',
		'unsigned __int128'      => 'unsigned __int128',
		'float'                  => 'float',
		'double'                 => 'double',
		'long double'            => 'long double',
		'_Float16'               => '_Float16',
		'__fp16'                 => '__fp16',
		'__float128'             => '__float128',
	);
	Readonly my %UNSIGNED  => map { $_ => 1 } ('_Bool', 'unsigned char', 'unsigned short', 'unsigned int', 'unsigned long', 'unsigned long long', 'unsigned __int128');
	Readonly my %FLOATING  => map { $_ => 1 } ('float', 'double', 'long double', '_Float16', '__fp16', '__float128');
	Readonly my %QUALIFIER => map { $_ => 1 } qw(const volatile restrict __restrict __restrict__ _Nonnull _Nullable _Null_unspecified);
	Readonly my %TAGGED    => map { $_ => 1 } qw(struct union enum);

	# kind is one of: void builtin record enum typedef pointer array function
	field $kind          : param : reader;
	field $name          : param : reader = undef;
	field $tag           : param : reader = undef;
	field $anonymousAt   : param : reader = undef;
	field $nameIsTypedef : param : reader = 0;       # record named through "typedef struct { } Name": render as "Name", not "struct Name"
	field $const         : param : reader = 0;
	field $pointee       : param : reader = undef;
	field $element       : param : reader = undef;
	field $length        : param : reader = undef;
	field $returns       : param : reader = undef;
	field $params        : param : reader = [];
	field $variadic      : param : reader = 0;
	field $spelled       : param : reader;

	method isVoid()     { return $kind eq 'void' }
	method isBuiltin()  { return $kind eq 'builtin' }
	method isRecord()   { return $kind eq 'record' }
	method isEnum()     { return $kind eq 'enum' }
	method isTypedef()  { return $kind eq 'typedef' }
	method isPointer()  { return $kind eq 'pointer' }
	method isArray()    { return $kind eq 'array' }
	method isFunction() { return $kind eq 'function' }

	method isBool()      { return $kind eq 'builtin' && $name eq '_Bool' }
	method isChar()      { return $kind eq 'builtin' && $name eq 'char' }
	method isFloating()  { return $kind eq 'builtin' && $FLOATING{$name} }
	method isInteger()   { return $kind eq 'builtin' && !$FLOATING{$name} && $name ne '_Bool' }
	method isUnsigned()  { return $kind eq 'builtin' && $UNSIGNED{$name} }
	method isAnonymous() { return defined $anonymousAt }

	method recordKey() {
		croak "recordKey called on a $kind type" if $kind ne 'record' && $kind ne 'enum';
		return $name // $anonymousAt;
	}

	# C source text for this type, usable in declarations and casts.
	# Top-level const is dropped when $withConst is false so the text
	# can declare an assignable local variable.
	method render($withConst = 1) {
		croak "an unnamed $tag has no C spelling" if ($kind eq 'record' || $kind eq 'enum') && !defined $name;
		my $prefix = ($withConst && $const) ? 'const ' : '';
		return $prefix . $name                                if $kind eq 'builtin' || $kind eq 'typedef' || $kind eq 'void';
		return $prefix . $name                                if ($kind eq 'record' || $kind eq 'enum') && $nameIsTypedef;
		return $prefix . "$tag $name"                         if $kind eq 'record' || $kind eq 'enum';
		return $self->_renderPointer($withConst)              if $kind eq 'pointer';
		return $element->render . '[' . ($length // '') . ']' if $kind eq 'array';
		return $self->_renderFunction                         if $kind eq 'function';
		croak "cannot render C type of kind '$kind'";
	}

	method _renderPointer($withConst) {
		my $constText = ($withConst && $const) ? ' const' : '';
		return $pointee->returns->render . ' (*' . ($constText ne '' ? 'const' : '') . ')(' . $pointee->_renderParams . ')' if $pointee->isFunction;
		my $base = $pointee->render;
		$base .= ' ' if $base !~ /\*$/;
		return $base . '*' . $constText;
	}

	# C declaration of a variable of this type: function pointers and arrays wrap the name.
	method declare($varName) {
		return $pointee->returns->render . " (*$varName)(" . $pointee->_renderParams . ')' if $kind eq 'pointer' && $pointee->isFunction;
		return $element->render . " " . $varName . "[" . ($length // '') . ']'             if $kind eq 'array';
		return $self->render(0) . " $varName";
	}

	method _renderParams() {
		my $paramText = join(', ', map { $_->render } $params->@*);
		$paramText .= ', ...' if $variadic && @$params;
		$paramText = '...'    if $variadic && !@$params;
		return $paramText eq '' ? 'void' : $paramText;
	}

	method _renderFunction() { return $returns->render . ' (' . $self->_renderParams . ')' }

	method parse : common ($text) {
		my $trimmed = $text =~ s/^\s+|\s+$//gr =~ s/\s+/ /gr;
		croak 'cannot parse an empty C type' if $trimmed eq '';

		return $class->_parseBase($trimmed)          if $trimmed =~ /\((?:unnamed|anonymous)\b[^)]*\)$/;
		return $class->_parseParenthesized($trimmed) if $trimmed =~ /\)$/;
		return $class->_parseArray($trimmed)         if $trimmed =~ /\]$/;
		return $class->_parsePointer($trimmed)       if $trimmed =~ /\*\s*(?:(?:const|volatile|restrict|__restrict|__restrict__)\s*)*$/;
		return $class->_parseBase($trimmed);
	}

	# "R (*)(A, B)" or "R (*const)(A, B)" or a plain function type "R (A, B)"
	method _parseParenthesized : common ($text) {
		my $open      = _matchingOpenParen($text);
		my $paramText = substr($text, $open + 1, length($text) - $open - 2);
		my $prefix    = substr($text, 0,         $open) =~ s/\s+$//r;

		my $params   = [];
		my $variadic = 0;
		foreach my $piece (_splitTopLevel($paramText)) {
			next if $piece eq 'void' || $piece eq '';
			if ($piece eq '...') { $variadic = 1; next }
			push @$params, $class->parse($piece);
		}

		if ($prefix =~ /^(.*?)\s*\(\s*\*\s*((?:const\s*)?)\)$/) {
			my $function = $class->new(kind => 'function', returns => $class->parse($1), params => $params, variadic => $variadic, spelled => $text);
			return $class->new(kind => 'pointer', pointee => $function, const => ($2 ne '' ? 1 : 0), spelled => $text);
		}
		croak "unsupported parenthesized C type '$text'" if $prefix =~ /\(/;
		return $class->new(kind => 'function', returns => $class->parse($prefix), params => $params, variadic => $variadic, spelled => $text);
	}

	method _parseArray : common ($text) {
		croak "unsupported pointer-to-array C type '$text'" if $text =~ /\(\s*\*\s*\)\s*\[/;
		my ($prefix, $length) = $text =~ /^(.*)\[\s*(\d*)\s*\]$/ or croak "cannot parse array C type '$text'";
		return $class->new(kind => 'array', element => $class->parse($prefix), length => ($length eq '' ? undef : $length + 0), spelled => $text);
	}

	method _parsePointer : common ($text) {
		my ($prefix, $qualifiers) = $text =~ /^(.*?)\s*\*\s*((?:(?:const|volatile|restrict|__restrict|__restrict__)\s*)*)$/ or croak "cannot parse pointer C type '$text'";
		return $class->new(kind => 'pointer', pointee => $class->parse($prefix), const => ($qualifiers =~ /\bconst\b/ ? 1 : 0), spelled => $text);
	}

	method _parseBase : common ($text) {
		my @words = split ' ', $text;
		my $const = grep { $_ eq 'const' } @words;
		@words = grep { !$QUALIFIER{$_} } @words;
		croak "cannot parse C type '$text'" if !@words;

		if ($TAGGED{$words[0]}) {
			my $tag  = shift @words;
			my $rest = join(' ', @words);
			my $kind = $tag eq 'enum' ? 'enum' : 'record';
			if ($rest =~ /\((?:unnamed|anonymous)\b[^)]*?\bat\s+(\S+?):(\d+):(\d+)\)/) {
				return $class->new(kind => $kind, tag => $tag, anonymousAt => "$1:$2:$3", const => $const, spelled => $text);
			}
			croak "cannot parse tagged C type '$text'" if $rest !~ /^\w+$/;
			return $class->new(kind => $kind, tag => $tag, name => $rest, const => $const, spelled => $text);
		}

		my $joined = join(' ', @words);
		if (my $canonical = $BUILTIN_CANONICAL{$joined}) {
			return $class->new(kind => 'void',    name => 'void',     const => $const, spelled => $text) if $canonical eq 'void';
			return $class->new(kind => 'builtin', name => $canonical, const => $const, spelled => $text);
		}
		croak "cannot parse C type '$text'" if @words != 1 || $words[0] !~ /^\w+$/;
		return $class->new(kind => 'typedef', name => $words[0], const => $const, spelled => $text);
	}

	sub _matchingOpenParen($text) {
		my $depth = 0;
		foreach my $index (reverse 0 .. length($text) - 1) {
			my $char = substr($text, $index, 1);
			$depth++      if $char eq ')';
			$depth--      if $char eq '(';
			return $index if $depth == 0;
		}
		croak "unbalanced parentheses in C type '$text'";
	}

	sub _splitTopLevel($text) {
		my @pieces;
		my $depth   = 0;
		my $current = '';
		foreach my $char (split //, $text) {
			if ($char eq ',' && $depth == 0) {
				push @pieces, $current =~ s/^\s+|\s+$//gr;
				$current = '';
				next;
			}
			$depth++ if $char eq '(' || $char eq '[';
			$depth-- if $char eq ')' || $char eq ']';
			$current .= $char;
		}
		push @pieces, $current =~ s/^\s+|\s+$//gr;
		return @pieces;
	}
}

1;

__END__

=head1 NAME

BindGen::CType - structured representation of a C type parsed from clang's type spelling

=head1 DESCRIPTION

Parses the C type strings found in clang's JSON AST (for example
C<const char *>, C<SDL_Window **>, C<void (*)(void *, int)> or
C<Uint8[16]>) into a tree of kinds: void, builtin, record, enum, typedef,
pointer, array and function. Typedef names are kept as-is; resolving them
is the model's job.

=cut
