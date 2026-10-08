# Copyright 2026 davenonymous
use v5.36;
use Object::Pad;

class BindGen::Mapping::Bool : isa(BindGen::Mapping) {
	method kind()    { return 'bool' }
	method perlDoc() { return 'boolean' }

	method inputCode($sv, $ctx) { return '(' . $self->cType . ")SvTRUE($sv)" }
	method outputCode($expr)    { return "newSVsv(boolSV($expr))" }
}

1;
