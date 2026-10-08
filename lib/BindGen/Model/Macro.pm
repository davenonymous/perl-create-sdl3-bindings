# Copyright 2026 davenonymous
use v5.36;
use Object::Pad;

# An object-like or function-like preprocessor macro defined in a library header.
class BindGen::Model::Macro {
	field $name         : param : reader;
	field $body         : param : reader = '';
	field $functionLike : param : reader = 0;
	field $header       : param : reader;
	field $problem      : reader = undef;    # why the macro cannot be exported as a constant, once known

	method markProblem($reason)  { $problem = $reason; return $self }
	method isConstantCandidate() { return !$functionLike && !defined $problem }
}

1;
