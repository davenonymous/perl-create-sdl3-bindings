# Copyright 2026 davenonymous
use v5.36;
use Object::Pad;

# Turns clang's JSON AST into a BindGen::Model. Only declarations located
# below the include root become part of the model; typedefs from foreign
# headers are recorded as well because they are needed to resolve types.
class BindGen::Parser {
	use Carp qw(croak);
	use BindGen::CType;
	use BindGen::Model;
	use BindGen::Model::Function;
	use BindGen::Model::Param;
	use BindGen::Model::Record;
	use BindGen::Model::Field;
	use BindGen::Model::Enum;
	use BindGen::Model::EnumValue;
	use BindGen::Model::Comment;

	field $model   : param;
	field $locator : param;         # BindGen::HeaderLocator
	field $formats : param = {};    # function name => { style, index }, see BindGen::Clang::dumpFormatAttributes
	field $currentFile;             # clang omits the file of a location when it did not change
	field %seenFunctions;

	method parse($ast) {
		foreach my $node (($ast->{inner} // [])->@*) {
			$self->_trackFile($node->{loc});
			next if $node->{isImplicit};
			my $header = $self->_currentHeader;
			my $kind   = $node->{kind};
			if    ($kind eq 'TypedefDecl')  { $self->_typedef($node) }
			elsif ($kind eq 'RecordDecl')   { $self->_record($node, $header, undef, undef) }
			elsif ($kind eq 'EnumDecl')     { $self->_enum($node, $header) }
			elsif ($kind eq 'FunctionDecl') { $self->_function($node, $header) if $header }
		}
		return $model;
	}

	method _trackFile($loc) {
		return if !$loc;
		my $file = $loc->{expansionLoc}{file} // $loc->{spellingLoc}{file} // $loc->{file};
		$currentFile = $file if defined $file;
		return;
	}

	method _currentHeader() { return $locator->headerFor($currentFile) }

	method _comment($node) {
		my ($commentNode) = grep { $_->{kind} eq 'FullComment' } ($node->{inner} // [])->@*;
		return BindGen::Model::Comment->new if !$commentNode;
		return BindGen::Model::Comment->fromAst($commentNode);
	}

	method _typedef($node) {
		my $name  = $node->{name};
		my $type  = BindGen::CType->parse($node->{type}{qualType});
		my $owned = $self->_ownedTagDecl($node);

		# "typedef struct { ... } Name;" gives the unnamed record the typedef's name
		if ($owned && $type->isRecord && $type->isAnonymous) {
			my $record = $model->record('anon:' . $owned->{id}) // croak "typedef $name refers to an unknown unnamed record";
			$model->renameRecord($record, $name);
			$type = BindGen::CType->new(kind => 'record', tag => $type->tag, name => $name, nameIsTypedef => 1, const => $type->const, spelled => $name);
		}
		if ($owned && $type->isEnum && $type->isAnonymous) {
			my $enum = $model->enum('anon:' . $owned->{id});
			$enum->setName($name) if $enum;
		}
		$model->addTypedef($name, $type);
		return;
	}

	method _ownedTagDecl($node) {
		foreach my $child (($node->{inner} // [])->@*) {
			return $child->{ownedTagDecl} if $child->{ownedTagDecl};
			my $deeper = $self->_ownedTagDecl($child);
			return $deeper if $deeper;
		}
		return undef;
	}

	method _record($node, $header, $parent, $parentField) {
		my $key    = $node->{name}        // ('anon:' . $node->{id});
		my $record = $model->record($key) // $self->_newRecord($key, $node, $header, $parent, $parentField);
		return $record if !$node->{completeDefinition};

		$record->setComplete(1);
		$record->setComment($self->_comment($node));

		my @fields;
		my $pendingUnnamed;
		foreach my $child (($node->{inner} // [])->@*) {
			my $kind = $child->{kind};
			if ($kind eq 'RecordDecl') {
				if (defined $child->{name}) { $self->_record($child, $header, undef, undef) }
				else                        { $pendingUnnamed = $child }
				next;
			}
			next if $kind ne 'FieldDecl';
			my $type   = BindGen::CType->parse($child->{type}{qualType});
			my $nested = undef;
			if (_innermostType($type)->isRecord && _innermostType($type)->isAnonymous) {
				croak 'field ' . ($child->{name} // '(anonymous)') . " of $key has an unnamed type without a preceding declaration" if !$pendingUnnamed;
				$nested         = $self->_record($pendingUnnamed, $header, $record, $child->{name});
				$pendingUnnamed = undef;
			}
			push @fields,
			  BindGen::Model::Field->new(
				name     => $child->{name},
				type     => $type,
				comment  => $self->_comment($child),
				bitfield => ($child->{isBitfield} ? 1 : 0),
				nested   => $nested,
			  );
		}
		$record->setFields(@fields);
		return $record;
	}

	method _newRecord($key, $node, $header, $parent, $parentField) {
		my $record = $model->addRecord(
			BindGen::Model::Record->new(
				key         => $key,
				name        => $node->{name},
				tag         => $node->{tagUsed},
				header      => $header,
				parent      => $parent,
				parentField => $parentField,
			)
		);
		$header->addRecord($record) if $header;
		return $record;
	}

	sub _innermostType($type) {
		$type = $type->isPointer ? $type->pointee : $type->element while $type->isPointer || $type->isArray;
		return $type;
	}

	method _enum($node, $header) {
		my $key = $node->{name} // ('anon:' . $node->{id});
		my @values;
		my $next = 0;
		foreach my $child (($node->{inner} // [])->@*) {
			next if $child->{kind} ne 'EnumConstantDecl';
			my $value = _evaluatedValue($child) // $next;
			push @values, BindGen::Model::EnumValue->new(name => $child->{name}, value => $value, comment => $self->_comment($child));
			$next = $value + 1;
		}
		my $enum = BindGen::Model::Enum->new(key => $key, name => $node->{name}, header => $header || undef, comment => $self->_comment($node), values => \@values);
		$model->addEnum($enum);
		$header->addEnum($enum) if $header;
		return;
	}

	sub _evaluatedValue($node) {
		foreach my $child (($node->{inner} // [])->@*) {
			next                   if $child->{kind} eq 'FullComment';
			return $child->{value} if defined $child->{value};
			my $deeper = _evaluatedValue($child);
			return $deeper if defined $deeper;
		}
		return undef;
	}

	method _function($node, $header) {
		my $name = $node->{name};
		return if $seenFunctions{$name}++;
		my $signature = BindGen::CType->parse($node->{type}{qualType});
		croak "function $name has a non-function type " . $node->{type}{qualType} if !$signature->isFunction;

		my @params;
		my $index = 0;
		foreach my $child (($node->{inner} // [])->@*) {
			next if $child->{kind} ne 'ParmVarDecl';
			push @params, BindGen::Model::Param->new(name => $child->{name} // "arg$index", type => BindGen::CType->parse($child->{type}{qualType}));
			$index++;
		}

		my $function = BindGen::Model::Function->new(
			name     => $name,
			returns  => $signature->returns,
			params   => \@params,
			variadic => ($node->{variadic} ? 1 : 0),
			format   => $formats->{$name},
			inline   => ($node->{inline} ? 1 : 0),
			header   => $header,
			comment  => $self->_comment($node),
		);
		$model->addFunction($function);
		$header->addFunction($function);
		return;
	}
}

1;
