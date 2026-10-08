# Copyright 2026 davenonymous
use v5.36;
use Object::Pad;

# The complete decision of what gets generated.
class BindGen::Plan {
	field $headers        : param : reader = [];    # BindGen::Plan::HeaderPlan
	field $callbacks      : param : reader = [];    # BindGen::Plan::Callback
	field $foreignRecords : param : reader = [];    # BindGen::Plan::BoundRecord for records without an API module (opaque classes)
	field $report         : param : reader;

	method allRecords() {
		return map { $_->withNested } ((map { $_->records->@* } @$headers), @$foreignRecords);
	}

	method allFunctions() {
		return map { $_->functions->@* } @$headers;
	}
}

1;
