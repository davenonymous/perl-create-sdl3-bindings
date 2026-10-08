# Copyright 2026 davenonymous
use v5.36;
use Object::Pad;

# Finds out which object-like macros can be exported as constants by letting
# the compiler judge each of them: it must be an expression, a compile-time
# constant, and of a type the generated BOOT code knows how to turn into an SV.
class BindGen::MacroProbe {
	use Readonly;

	Readonly my @REPRESENTABLE => (
		'char *', 'const char *', 'float', 'double', 'long double', '_Bool', 'char', 'signed char', 'short', 'int', 'long', 'long long',
		'unsigned char',
		'unsigned short',
		'unsigned int',
		'unsigned long',
		'unsigned long long'
	);
	Readonly my $LINES_PER_MACRO => 3;

	field $clang        : param;
	field $entryInclude : param;    # text of the #include line pulling in the library
	field $scratchDir   : param;

	method probe($macros) {
		my @candidates = grep { !$_->functionLike } @$macros;
		return if !@candidates;

		my $typeList = join(', ', map { "$_: 1" } @REPRESENTABLE);
		my @lines    = ($entryInclude);
		foreach my $index (0 .. $#candidates) {
			my $name = $candidates[$index]->name;
			push @lines,
			  "__typeof__(($name)) bg_probe_$index;",
			  "_Static_assert(__builtin_constant_p(($name)), \"not a compile-time constant\");",
			  "_Static_assert(_Generic(($name), $typeList, default: 0), \"value type not representable\");";
		}
		my $errors = $clang->syntaxErrors(join("\n", @lines) . "\n", $scratchDir);
		foreach my $line (sort { $a <=> $b } keys %$errors) {
			my $macro = $candidates[ int(($line - 2) / $LINES_PER_MACRO) ] // next;
			next if defined $macro->problem;    # the first complaint about a macro is the telling one
			$macro->markProblem($self->_describe($errors->{$line}));
		}
		return;
	}

	method _describe($message) {
		return 'not a compile-time constant'  if $message =~ /not a compile-time constant/;
		return 'value type not representable' if $message =~ /value type not representable/;
		return "not a constant expression: $message";
	}
}

1;
