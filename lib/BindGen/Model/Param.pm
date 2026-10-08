# Copyright 2026 davenonymous
use v5.36;
use Object::Pad;

class BindGen::Model::Param {
	field $name : param : reader;
	field $type : param : reader;    # BindGen::CType
}

1;
