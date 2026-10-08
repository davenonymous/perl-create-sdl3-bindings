# Copyright 2026 davenonymous
use v5.36;
use Object::Pad;

class BindGen::Model::Field {
	field $name     : param : reader = undef;    # undef for an anonymous member (C11 unnamed struct/union member)
	field $type     : param : reader;            # BindGen::CType
	field $comment  : param : reader = undef;
	field $bitfield : param : reader = 0;
	field $nested   : param : reader = undef;    # BindGen::Model::Record when the field's type is an unnamed record declared inline

	method isAnonymousMember() { return !defined $name }
}

1;
