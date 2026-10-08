# Copyright 2026 davenonymous
use v5.36;
use Object::Pad;

# The "void *userdata" that travels with a callback: carries the holder that
# keeps the Perl code ref and the caller's data alive.
class BindGen::Mapping::CallbackData : isa(BindGen::Mapping) {
	field $callbackParam : param : reader;    # name of the parameter holding the code ref

	method kind()    { return 'callback-data' }
	method perlDoc() { return 'any scalar, handed to the callback' }

	method prepareCode($var, $sv, $ctx) {
		return "c_$var = SvOK($callbackParam) ? (" . $self->cType . ")bg_make_holder(aTHX_ $callbackParam, $sv, $ctx) : NULL;";
	}
}

1;
