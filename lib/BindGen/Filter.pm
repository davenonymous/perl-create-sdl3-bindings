# Copyright 2026 davenonymous
use v5.36;
use Object::Pad;

# Which headers and functions the user wants bound. Patterns are regular expressions.
class BindGen::Filter {
	field $includeHeaders   : param = [];
	field $excludeHeaders   : param = [];
	field $excludeFunctions : param = [];
	field $includeVariadic  : param = 0;
	field $includeInline    : param = 1;

	method headerIncluded($header) {
		my $name = $header->name;
		return 0 if @$includeHeaders && !grep { $name =~ /$_/ } @$includeHeaders;
		return 0 if grep                      { $name =~ /$_/ } @$excludeHeaders;
		return 1;
	}

	# Returns undef when the function is wanted, otherwise the reason it is not.
	method functionExclusion($function) {
		my $name = $function->name;
		return 'excluded by --exclude-function'                             if grep { $name =~ /$_/ } @$excludeFunctions;
		return 'variadic functions are left out without --include-variadic' if $function->variadic && !$includeVariadic;
		return 'inline functions are left out with --no-include-inline'     if $function->inline   && !$includeInline;
		return undef;
	}
}

1;
