# Copyright 2026 davenonymous
use v5.36;
use Object::Pad;

# Any integral C type including enums; unsigned ones travel as UV, the rest as IV.
class BindGen::Mapping::Integer : isa(BindGen::Mapping) {
	field $unsigned : param : reader = 0;

	method kind()    { return 'integer' }
	method perlDoc() { return $unsigned ? 'unsigned integer' : 'integer' }

	method inputCode($sv, $ctx) {
		my $reader = $unsigned ? 'bg_in_uv' : 'bg_in_iv';
		return '(' . $self->cType . ")$reader(aTHX_ $sv, $ctx)";
	}

	method outputCode($expr) {
		return $unsigned ? "newSVuv((UV)($expr))" : "newSViv((IV)($expr))";
	}
}

1;
