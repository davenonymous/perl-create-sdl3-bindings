# Copyright 2026 davenonymous
use v5.36;
use Object::Pad;

# A C function with a mapping for every parameter and the return value.
class BindGen::Plan::BoundFunction {
	field $function    : param : reader;
	field $params      : param : reader;            # [ { name, mapping } ] in C order
	field $returns     : param : reader;            # mapping
	field $formatIndex : param : reader = undef;    # index of the format string parameter of a printf-like function
	field $messageName : param : reader = undef;    # Perl name of the trailing preformatted message

	method name()         { return $function->name }
	method isPrintfLike() { return defined $formatIndex }

	# parameter names as seen from Perl: the format parameter is replaced by a trailing message
	method perlParamNames() {
		my @names = map { $_->{name} } grep { !defined $formatIndex || $_->{index} != $formatIndex } @$params;
		push @names, $messageName if defined $formatIndex;
		return @names;
	}
}

1;
