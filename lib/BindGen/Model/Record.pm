# Copyright 2026 davenonymous
use v5.36;
use Object::Pad;

# A struct or union. Nested unnamed records declared inside another record
# carry their parent and the name of the field they are the type of.
class BindGen::Model::Record {
	field $key           : param : reader;            # tag name, or "file:line:col" for unnamed records
	field $name          : param : reader = undef;    # tag name or the typedef name that gave an unnamed record its name
	field $tag           : param : reader;            # struct | union
	field $complete      : param : reader = 0;
	field $header        : param : reader = undef;    # BindGen::Model::Header, undef for records from foreign headers
	field $comment       : param : reader = undef;
	field $parent        : param : reader = undef;    # enclosing BindGen::Model::Record for nested unnamed records
	field $parentField   : param : reader = undef;    # name of the field in the parent that has this record as type
	field $nameIsTypedef : reader = 0;                # named through "typedef struct { } Name"
	field @fields;

	method fields() { return [@fields] }

	method isOpaque()    { return !$complete }
	method isNested()    { return defined $parent }
	method isExternal()  { return !defined $header }
	method isAnonymous() { return !defined $name }

	method addField($field) { push @fields, $field; return $self }

	method setName($newName)              { $name     = $newName;            return $self }
	method adoptTypedefName($typedefName) { $name     = $key = $typedefName; $nameIsTypedef = 1; return $self }
	method setComplete($state)            { $complete = $state;              return $self }
	method setComment($newComment)        { $comment  = $newComment;         return $self }
	method setFields(@newFields)          { @fields   = @newFields;          return $self }

	# C expression naming this record's type, valid wherever the library headers are included.
	method cTypeExpr() {
		return $name                                                                 if $self->nameIsTypedef;
		return "$tag $name"                                                          if defined $name   && !$self->isNested;
		return '__typeof__(((' . $parent->cTypeExpr . ' *)0)->' . $parentField . ')' if $self->isNested && defined $parentField;
		die 'record ' . $key . ' has no C type expression';
	}
}

1;
