# Copyright 2026 davenonymous
use v5.36;
use Object::Pad;

class BindGen::Model::EnumValue {
	field $name    : param : reader;
	field $value   : param : reader = undef;    # undef when clang did not report an evaluated value
	field $comment : param : reader = undef;
}

1;
