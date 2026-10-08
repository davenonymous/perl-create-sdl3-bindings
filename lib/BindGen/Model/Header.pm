# Copyright 2026 davenonymous
use v5.36;
use Object::Pad;

# One public header of the library: the unit a generated module corresponds to.
class BindGen::Model::Header {
	field $name : param : reader;    # basename, e.g. SDL_video.h
	field $path : param : reader;    # path relative to the include root, e.g. SDL3/SDL_video.h
	field @functions;
	field @records;
	field @enums;
	field @macros;

	method functions() { return [@functions] }
	method records()   { return [@records] }
	method enums()     { return [@enums] }
	method macros()    { return [@macros] }

	method addFunction($function) { push @functions, $function; return $self }
	method addRecord($record)     { push @records,   $record;   return $self }
	method addEnum($enum)         { push @enums,     $enum;     return $self }
	method addMacro($macro)       { push @macros,    $macro;    return $self }
}

1;
