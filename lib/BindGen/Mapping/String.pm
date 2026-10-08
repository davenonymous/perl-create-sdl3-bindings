# Copyright 2026 davenonymous
use v5.36;
use Object::Pad;

# "const char *": a NUL-terminated UTF-8 string, undef on both sides for NULL.
class BindGen::Mapping::String : isa(BindGen::Mapping) {
	method kind()    { return 'string' }
	method perlDoc() { return 'string' }

	method inputCode($sv, $ctx) { return '(' . $self->cType . ")bg_in_string(aTHX_ $sv, $ctx)" }
	method outputCode($expr)    { return "bg_out_string(aTHX_ (const char *)($expr))" }
}

1;
