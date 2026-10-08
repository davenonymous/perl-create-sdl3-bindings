# Copyright 2026 davenonymous
use v5.36;
use Object::Pad;

# Pointer to a struct or union: a blessed, non-owning pointer object on the Perl side.
class BindGen::Mapping::RecordPtr : isa(BindGen::Mapping) {
	field $record : param : reader;    # BindGen::Model::Record
	field $class  : param : reader;    # Perl package the pointer is blessed into

	method kind()    { return 'record-pointer' }
	method perlDoc() { return "$class object or undef" }

	method inputCode($sv, $ctx) { return '(' . $self->cType . ")bg_in_record_ptr(aTHX_ $sv, \"$class\", $ctx)" }
	method outputCode($expr)    { return "bg_out_record_ptr(aTHX_ (void *)($expr), \"$class\")" }
}

1;
