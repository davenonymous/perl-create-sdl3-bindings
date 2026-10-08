# Copyright 2026 davenonymous
use v5.36;
use Object::Pad;

# Untyped or otherwise unboxed memory: void *, buffers, pointers to scalars
# returned from C, function pointers. Represented by the generic pointer class.
class BindGen::Mapping::RawPtr : isa(BindGen::Mapping) {
	field $pointerClass : param;

	method kind()    { return 'raw-pointer' }
	method perlDoc() { return "$pointerClass, object, string buffer or undef" }

	method inputCode($sv, $ctx) { return '(' . $self->cType . ")bg_in_raw_ptr(aTHX_ $sv, $ctx)" }
	method outputCode($expr)    { return "bg_out_raw_ptr(aTHX_ (void *)($expr), \"$pointerClass\")" }
}

1;
