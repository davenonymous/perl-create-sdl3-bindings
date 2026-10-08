# Copyright 2026 davenonymous
use v5.36;
use Object::Pad;

# One generated field accessor of a struct class.
class BindGen::Plan::Accessor {
	field $name    : param : reader;            # Perl method name
	field $cPath   : param : reader;            # C member access path relative to the record pointer, e.g. "x" or "axis_min"
	field $mapping : param : reader = undef;    # BindGen::Mapping for scalar-like fields
	field $element : param : reader = undef;    # element mapping for fixed-size array fields
	field $length  : param : reader = undef;    # array length
	field $comment : param : reader = undef;

	method isArray() { return defined $element }
	method perlDoc() { return $self->isArray ? 'list of ' . $length . ' x ' . $element->perlDoc : $mapping->perlDoc }
}

1;
