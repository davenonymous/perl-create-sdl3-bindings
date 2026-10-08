# Copyright 2026 davenonymous
use v5.36;
use Object::Pad;

class BindGen::Mapping::Void : isa(BindGen::Mapping) {
	method kind()    { return 'void' }
	method perlDoc() { return 'nothing' }
}

1;
