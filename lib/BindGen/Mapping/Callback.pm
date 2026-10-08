# Copyright 2026 davenonymous
use v5.36;
use Object::Pad;

# Function pointer parameter: a Perl code ref is wrapped by a generated trampoline.
class BindGen::Mapping::Callback : isa(BindGen::Mapping) {
	field $id : param : reader;    # trampoline identity, shared by every use of the same callback type

	method kind()       { return 'callback' }
	method perlDoc()    { return 'code reference or undef' }
	method trampoline() { return "bg_tramp_$id" }

	method prepareCode($var, $sv, $ctx) {
		return "c_$var = SvOK($sv) ? (" . $self->cType . ')' . $self->trampoline . ' : NULL;';
	}
}

1;
