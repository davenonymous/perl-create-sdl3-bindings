# Copyright 2026 davenonymous
use v5.36;
use Object::Pad;

class BindGen::Mapping::Unsupported : isa(BindGen::Mapping) {
	field $reason : param : reader;

	method kind()          { return 'unsupported' }
	method perlDoc()       { return 'unsupported' }
	method isUnsupported() { return 1 }
}

1;
