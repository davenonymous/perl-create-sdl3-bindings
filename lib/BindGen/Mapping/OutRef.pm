# Copyright 2026 davenonymous
use v5.36;
use Object::Pad;

# Pointer parameter used to hand a value back: the caller passes a scalar
# reference (read before the call, written after), a pointer object, or undef for NULL.
class BindGen::Mapping::OutRef : isa(BindGen::Mapping) {
	field $inner : param : reader;    # mapping of the pointed-to value

	method kind()    { return 'out-reference' }
	method perlDoc() { return 'reference to a scalar holding ' . $inner->perlDoc . ', pointer object or undef' }

	method declareCode($var) {
		return join(' ', $inner->cType . " c_$var;", $self->type->declare("p_$var") . ';', "SV *t_$var;");
	}

	method prepareCode($var, $sv, $ctx) {
		my $innerType = $inner->cType;
		return join("\n\t",
			"t_$var = bg_outref_target(aTHX_ $sv);",
			"c_$var = (t_$var && SvOK(t_$var)) ? " . $inner->inputCode("t_$var", $ctx) . " : ($innerType)0;",
			"p_$var = t_$var ? &c_$var : (" . $self->cType . ")bg_outref_raw(aTHX_ $sv, $ctx);",
		);
	}

	method argumentExpr($var) { return "p_$var" }

	method writebackCode($var) {
		return "if (t_$var) sv_setsv(t_$var, sv_2mortal(" . $inner->outputCode("c_$var") . '));';
	}
}

1;
