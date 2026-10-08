# Copyright 2026 davenonymous
use v5.36;
use Object::Pad;

# Struct or union by value: copied out of or into an object's memory.
class BindGen::Mapping::RecordValue : isa(BindGen::Mapping) {
	field $record    : param : reader;
	field $class     : param : reader;
	field $cTypeExpr : param;    # C type expression of the record, valid after including the headers

	method kind()    { return 'record-value' }
	method perlDoc() { return "$class object" }
	method cType()   { return $cTypeExpr }

	method declareCode($var)      { return "$cTypeExpr c_$var;" }
	method fieldOutputCode($expr) { return "bg_out_record_ptr(aTHX_ (void *)&($expr), \"$class\")" }

	method inputCode($sv, $ctx) { return "*($cTypeExpr *)bg_in_record_value_ptr(aTHX_ $sv, \"$class\", $ctx)" }
	method outputCode($expr)    { return "bg_out_record_copy(aTHX_ (const void *)&($expr), sizeof($cTypeExpr), \"$class\")" }
}

1;
