# Copyright 2026 davenonymous
use v5.36;
use Object::Pad;

# Maps C names to Perl package names. The only knowledge about the library
# is the common symbol prefix handed in as an option.
class BindGen::Naming {
	field $namespace    : param : reader;    # e.g. SDL3
	field $apiNamespace : param : reader;    # e.g. API => header modules live in SDL3::API::*
	field $stripPrefix  : param : reader;    # e.g. SDL_

	method withoutPrefix($name) {
		return $name =~ s/^\Q$stripPrefix\E//ir;
	}

	method camel($text) {
		return join('', map { ucfirst $_ } grep { $_ ne '' } split /_+/, $text);
	}

	method moduleForHeader($header) {
		my $base = $header->name =~ s/\.h$//r;
		return join('::', $namespace, $apiNamespace, $self->camel($self->withoutPrefix($base)));
	}

	method classForRecord($record) {
		return $self->classForRecord($record->parent) . '::' . $self->camel($record->parentField) if $record->isNested;
		die 'cannot name an anonymous top-level record ' . $record->key                           if $record->isAnonymous;
		return join('::', $namespace, $self->camel($self->withoutPrefix($record->name)));
	}

	use Readonly;
	Readonly my %RESERVED_METHOD => map { $_ => 1 } qw(new address bytes isa can DOES VERSION DESTROY import AUTOLOAD _alloc _sizeof _bytes);

	# field accessors live next to the struct base class methods, so a clashing field name gets a suffix
	method methodNameForField($fieldName) {
		return $RESERVED_METHOD{$fieldName} ? "${fieldName}_" : $fieldName;
	}

	method pointerClass()    { return "${namespace}::Pointer" }
	method structBaseClass() { return "${namespace}::Struct" }
	method rootModule()      { return $namespace }

	method exportTagForHeader($header) {
		return lc($self->withoutPrefix($header->name =~ s/\.h$//r));
	}

	method fileForModule($module) {
		return join('/', 'lib', split(/::/, $module)) . '.pm';
	}
}

1;
