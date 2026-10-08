# Copyright 2026 davenonymous
use v5.36;
use Object::Pad;

# A trampoline: C calls it with the callback's signature, it calls the Perl code ref.
class BindGen::Plan::Callback {
	field $id        : param : reader;
	field $signature : param : reader;    # BindGen::CType of kind function
	field $slot      : param : reader;    # index of the void * parameter carrying the holder
	field $params    : param : reader;    # [ mapping ] for every parameter, undef at the slot
	field $returns   : param : reader;    # mapping

	method trampoline() { return "bg_tramp_$id" }
}

1;
