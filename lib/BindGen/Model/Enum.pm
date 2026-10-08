# Copyright 2026 davenonymous
use v5.36;
use Object::Pad;

class BindGen::Model::Enum {
	field $key     : param : reader;
	field $name    : param : reader = undef;
	field $header  : param : reader = undef;
	field $comment : param : reader = undef;
	field $values  : param : reader = [];      # BindGen::Model::EnumValue

	method setName($newName) { $name = $newName; return $self }
}

1;
