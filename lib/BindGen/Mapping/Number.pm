# Copyright 2026 davenonymous
use v5.36;
use Object::Pad;

class BindGen::Mapping::Number : isa(BindGen::Mapping) {
	method kind()    { return 'number' }
	method perlDoc() { return 'number' }

	method inputCode($sv, $ctx) { return '(' . $self->cType . ")bg_in_nv(aTHX_ $sv, $ctx)" }
	method outputCode($expr)    { return "newSVnv((NV)($expr))" }
}

1;
