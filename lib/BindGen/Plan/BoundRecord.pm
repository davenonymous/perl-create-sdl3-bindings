# Copyright 2026 davenonymous
use v5.36;
use Object::Pad;

# A struct or union that becomes a Perl class.
class BindGen::Plan::BoundRecord {
	field $record    : param : reader;
	field $class     : param : reader;
	field $accessors : param : reader = [];    # BindGen::Plan::Accessor
	field $nested    : param : reader = [];    # BindGen::Plan::BoundRecord for unnamed records used as field types

	method cTypeExpr() { return $record->cTypeExpr }
	method isOpaque()  { return $record->isOpaque }

	# this record and every nested one, depth first
	method withNested() {
		return ($self, map { $_->withNested } @$nested);
	}
}

1;
