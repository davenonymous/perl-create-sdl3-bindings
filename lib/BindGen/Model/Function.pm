# Copyright 2026 davenonymous
use v5.36;
use Object::Pad;

class BindGen::Model::Function {
	field $name     : param : reader;
	field $returns  : param : reader;            # BindGen::CType
	field $params   : param : reader = [];       # BindGen::Model::Param
	field $variadic : param : reader = 0;
	field $format   : param : reader = undef;    # { style => 'printf', index => 0-based fixed param index } for printf-like variadics
	field $inline   : param : reader = 0;
	field $header   : param : reader;            # BindGen::Model::Header
	field $comment  : param : reader;            # BindGen::Model::Comment

	method isPrintfLike() { return $variadic && $format && $format->{style} eq 'printf' }
}

1;
