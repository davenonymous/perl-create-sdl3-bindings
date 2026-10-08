# Copyright 2026 davenonymous
use v5.36;
use Object::Pad;

# "char *" parameter: C writes into the buffer of the scalar handed in, which the
# caller sizes beforehand. A pointer object or undef is passed through as-is.
class BindGen::Mapping::WritableString : isa(BindGen::Mapping) {
	method kind()    { return 'writable-string' }
	method perlDoc() { return 'writable string buffer' }

	method inputCode($sv, $ctx) { return '(' . $self->cType . ")bg_in_writable_string(aTHX_ $sv, $ctx)" }
}

1;
