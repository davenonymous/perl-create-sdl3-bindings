# Copyright 2026 davenonymous
use v5.36;
use Object::Pad;

# How one C type crosses the XS boundary. Subclasses provide the C
# expressions that convert an SV to a C value and back; the generic
# declare/prepare/argument/writeback steps cover plain by-value cases.
class BindGen::Mapping : abstract {
	field $type : param : reader;    # BindGen::CType as spelled in the declaration

	method kind;
	method perlDoc;

	method cType()         { return $type->render(0) }
	method isUnsupported() { return 0 }

	method inputCode($sv, $ctx) { die $self->kind . ' cannot be converted from Perl' }
	method outputCode($expr)    { die $self->kind . ' cannot be converted to Perl' }

	method declareCode($var)            { return $type->declare("c_$var") . ';' }
	method fieldOutputCode($expr)       { return $self->outputCode($expr) }                          # getters of struct fields; by-value records return a view instead of a copy
	method prepareCode($var, $sv, $ctx) { return "c_$var = " . $self->inputCode($sv, $ctx) . ';' }
	method argumentExpr($var)           { return "c_$var" }
	method writebackCode($var)          { return '' }
}

1;
