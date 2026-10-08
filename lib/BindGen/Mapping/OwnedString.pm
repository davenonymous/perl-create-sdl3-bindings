# Copyright 2026 davenonymous
use v5.36;
use Object::Pad;

# "char *" result the caller owns: copied into a Perl string, then handed to the library's free function.
class BindGen::Mapping::OwnedString : isa(BindGen::Mapping) {
	field $freeFunction : param : reader;

	method kind()    { return 'owned-string' }
	method perlDoc() { return 'string' }

	method outputCode($expr) { return "bg_out_owned_string(aTHX_ (char *)($expr), (void (*)(void *))$freeFunction)" }
}

1;
