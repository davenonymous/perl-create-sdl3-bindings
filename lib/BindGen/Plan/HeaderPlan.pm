# Copyright 2026 davenonymous
use v5.36;
use Object::Pad;

# Everything generated for one header: an API module plus the classes of its records.
class BindGen::Plan::HeaderPlan {
	field $header    : param : reader;
	field $module    : param : reader;
	field $tag       : param : reader;         # export tag name
	field $functions : param : reader = [];    # BindGen::Plan::BoundFunction
	field $records   : param : reader = [];    # BindGen::Plan::BoundRecord
	field $constants : param : reader = [];    # names exported as constant subs
	field $enums     : param : reader = [];    # BindGen::Model::Enum for documentation

	method fileStem()   { return $module =~ s/::/_/gr }
	method hasContent() { return @$functions || @$records || @$constants }
}

1;
