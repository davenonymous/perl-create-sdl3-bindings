# Copyright 2026 davenonymous
use v5.36;
use Object::Pad;

# Decides how a C type crosses into Perl, depending on where it appears.
# Positions: param, return, field, callbackParam, callbackReturn, outref.
class BindGen::Mapper {
	use BindGen::Mapping::Void;
	use BindGen::Mapping::Integer;
	use BindGen::Mapping::Number;
	use BindGen::Mapping::Bool;
	use BindGen::Mapping::String;
	use BindGen::Mapping::WritableString;
	use BindGen::Mapping::OwnedString;
	use BindGen::Mapping::RecordPtr;
	use BindGen::Mapping::RecordValue;
	use BindGen::Mapping::RawPtr;
	use BindGen::Mapping::OutRef;
	use BindGen::Mapping::Callback;
	use BindGen::Mapping::Unsupported;

	field $model  : param;
	field $naming : param;
	field $freeFunction : param = undef;    # the library's deallocator, enables owned string results

	# Options: fallbackCallbackId names the trampoline of a function pointer parameter without a typedef name;
	# ownedResult marks a return value the caller must free.
	method map($type, $position, %options) {
		return BindGen::Mapping::Unsupported->new(type => $type, reason => 'va_list cannot be built from Perl') if $self->_isVaList($type);
		my $resolved = $model->resolve($type);

		if ($resolved->isVoid) {
			return BindGen::Mapping::Void->new(type => $type) if $position eq 'return' || $position eq 'callbackReturn';
			return BindGen::Mapping::Unsupported->new(type => $type, reason => 'void is not a value');
		}
		return $self->_mapBuiltin($type, $resolved)                                                                      if $resolved->isBuiltin;
		return BindGen::Mapping::Integer->new(type => $type, unsigned => 0)                                              if $resolved->isEnum;
		return $self->_mapRecordValue($type, $resolved)                                                                  if $resolved->isRecord;
		return $self->_mapPointer($type, $resolved, $position, \%options)                                                if $resolved->isPointer;
		return BindGen::Mapping::Unsupported->new(type => $type, reason => 'arrays are only supported as struct fields') if $resolved->isArray;
		return BindGen::Mapping::Unsupported->new(type => $type, reason => 'bare function types are not values');
	}

	# The C standard's variable argument list has no Perl representation.
	method _isVaList($type) {
		my %seen;
		while ($type->isTypedef && !$seen{$type->name}++) {
			return 1 if $type->name =~ /^(?:va_list|__builtin_va_list|__gnuc_va_list)$/;
			$type = $model->typedef($type->name) // return 0;
		}
		return 0;
	}

	method _mapBuiltin($type, $resolved) {
		return BindGen::Mapping::Bool->new(type => $type)   if $resolved->isBool;
		return BindGen::Mapping::Number->new(type => $type) if $resolved->isFloating;
		return BindGen::Mapping::Integer->new(type => $type, unsigned => ($resolved->isUnsigned ? 1 : 0));
	}

	method _mapRecordValue($type, $resolved) {
		return BindGen::Mapping::Unsupported->new(type => $type, reason => 'unnamed record type')                                if $resolved->isAnonymous;
		return BindGen::Mapping::Unsupported->new(type => $type, reason => $resolved->name . ' belongs to the C implementation') if _isReservedIdentifier($resolved->name);
		my $record = $model->recordFor($resolved);
		return BindGen::Mapping::Unsupported->new(type => $type, reason => $record->name . ' is opaque and cannot be passed by value') if $record->isOpaque;
		return BindGen::Mapping::RecordValue->new(type => $type, record => $record, class => $naming->classForRecord($record), cTypeExpr => $record->cTypeExpr);
	}

	method _mapPointer($type, $resolved, $position, $options) {
		my $pointee = $model->resolve($resolved->pointee);
		my $isParam = $position eq 'param';

		return $self->_rawPointer($type) if $pointee->isVoid;
		if ($pointee->isChar) {
			return BindGen::Mapping::String->new(type => $type)         if $pointee->const;
			return BindGen::Mapping::WritableString->new(type => $type) if $isParam;
			return $self->_mapStringResult($type, $options)             if $position eq 'return';
			return $self->_rawPointer($type);
		}
		if ($pointee->isFunction) {
			return $self->_rawPointer($type) if !$isParam;
			my $id = $model->callbackNameOf($type) // $options->{fallbackCallbackId} // return BindGen::Mapping::Unsupported->new(type => $type, reason => 'function pointer without a name');
			return BindGen::Mapping::Callback->new(type => $type, id => $id);
		}
		if ($pointee->isRecord) {
			return BindGen::Mapping::Unsupported->new(type => $type, reason => 'pointer to an unnamed record')                      if $pointee->isAnonymous;
			return BindGen::Mapping::Unsupported->new(type => $type, reason => $pointee->name . ' belongs to the C implementation') if _isReservedIdentifier($pointee->name);
			my $record = $model->recordFor($pointee);
			return BindGen::Mapping::RecordPtr->new(type => $type, record => $record, class => $naming->classForRecord($record));
		}
		return $self->_rawPointer($type) if !$isParam;
		return $self->_rawPointer($type) if $pointee->const && !$pointee->isPointer;
		return $self->_outRef($type, $resolved);
	}

	# A non-const char * result is a string either way; freeing it needs the deallocator and the knowledge that the caller owns it.
	method _mapStringResult($type, $options) {
		return BindGen::Mapping::OwnedString->new(type => $type, freeFunction => $freeFunction) if $options->{ownedResult} && defined $freeFunction;
		return BindGen::Mapping::String->new(type => $type);
	}

	method _outRef($type, $resolved) {
		my $inner = $self->map($resolved->pointee, 'outref');
		return $inner if $inner->isUnsupported;
		return BindGen::Mapping::OutRef->new(type => $type, inner => $inner);
	}

	# C reserves identifiers starting with two underscores or an underscore and a capital for the implementation (compiler builtins such as __va_list_tag).
	sub _isReservedIdentifier($name) { return $name =~ /^_(?:_|[A-Z])/ }

	method _rawPointer($type) {
		return BindGen::Mapping::RawPtr->new(type => $type, pointerClass => $naming->pointerClass);
	}
}

1;
