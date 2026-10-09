# Copyright 2026 davenonymous
use v5.36;
use Object::Pad;

# Everything the parser learned about the library: headers, declarations
# and the typedef table needed to resolve spelled types to their structure.
class BindGen::Model {
	use Carp qw(croak);

	field %headers;      # relative path => BindGen::Model::Header
	field %records;      # record key => BindGen::Model::Record
	field %enums;        # enum key => BindGen::Model::Enum
	field %typedefs;     # typedef name => BindGen::CType (the aliased type)
	field %callbacks;    # typedef name => BindGen::CType (pointer to function)
	field @functions;    # BindGen::Model::Function, in declaration order
	field %macros;       # macro name => BindGen::Model::Macro

	method headers() {
		return [ sort { $a->path cmp $b->path } values %headers ];
	}
	method functions() { return [@functions] }
	method records()   { return [ values %records ] }
	method enums()     { return [ values %enums ] }
	method macros()    { return [ sort { $a->name cmp $b->name } values %macros ] }
	method callbacks() { return {%callbacks} }

	method header($path)   { return $headers{$path} }
	method record($key)    { return $records{$key} }
	method enum($key)      { return $enums{$key} }
	method typedef($name)  { return $typedefs{$name} }
	method callback($name) { return $callbacks{$name} }
	method macro($name)    { return $macros{$name} }

	method addHeader($header)     { $headers{$header->path} = $header; return $header }
	method addRecord($record)     { $records{$record->key}  = $record; return $record }
	method addEnum($enum)         { $enums{$enum->key}      = $enum;   return $enum }
	method addFunction($function) { push @functions, $function;     return $function }
	method addMacro($macro)       { $macros{$macro->name} = $macro; return $macro }

	# Gives a record declared without a tag the name of its typedef and re-keys it.
	method renameRecord($record, $newName) {
		delete $records{$record->key};
		$record->adoptTypedefName($newName);
		$records{$newName} = $record;
		return $record;
	}

	method addTypedef($name, $type) {
		$typedefs{$name}  = $type;
		$callbacks{$name} = $type if $type->isPointer && $type->pointee->isFunction;
		return $self;
	}

	# Follows typedef chains until a structural type remains.
	method resolve($type) {
		my %seen;
		while ($type->isTypedef) {
			croak 'typedef cycle at ' . $type->name if $seen{$type->name}++;
			$type = $typedefs{$type->name} // croak 'unknown typedef ' . $type->name;
		}
		return $type;
	}

	# The record a (resolved) record type refers to, registering foreign opaque records on first sight.
	method recordFor($type) {
		croak 'recordFor needs a record type, got ' . $type->kind if !$type->isRecord;
		my $key = $type->recordKey;
		return $records{$key} //= BindGen::Model::Record->new(key => $key, name => $type->name, tag => $type->tag);
	}

	# The typedef name a type was spelled with, if it directly names a callback typedef.
	method callbackNameOf($type) {
		return $type->isTypedef && $callbacks{$type->name} ? $type->name : undef;
	}
}

1;
