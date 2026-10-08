# Copyright 2026 davenonymous
use v5.36;
use Object::Pad;

# Decides for every declaration whether and how it is bound, recording
# every omission in the report.
class BindGen::Planner {
	use List::Util qw(uniq);
	use BindGen::Mapper;
	use BindGen::Mapping::CallbackData;
	use BindGen::Mapping::RecordValue;
	use BindGen::Plan;
	use BindGen::Plan::HeaderPlan;
	use BindGen::Plan::BoundFunction;
	use BindGen::Plan::BoundRecord;
	use BindGen::Plan::Accessor;
	use BindGen::Plan::Callback;

	field $model  : param;
	field $naming : param;
	field $filter : param;
	field $report : param;
	field $freeFunction : param = undef;
	field $mapper;
	field %callbacks;            # trampoline id => BindGen::Plan::Callback
	field %boundRecords;         # record key => BindGen::Plan::BoundRecord
	field @referencedRecords;    # records bound functions point at

	ADJUST { $mapper = BindGen::Mapper->new(model => $model, naming => $naming, freeFunction => $freeFunction) }

	method plan() {
		my @headerPlans;
		foreach my $header ($model->headers->@*) {
			if (!$filter->headerIncluded($header)) {
				$report->skip('header', $header->name, $header->name, 'excluded by header filter');
				next;
			}
			$report->bound('header');
			my @functions = grep { defined } map                 { $self->_planFunction($_) } $header->functions->@*;
			my @records   = map  { $self->_planRecord($_) } grep { !$_->isNested } $header->records->@*;
			push @headerPlans,
			  BindGen::Plan::HeaderPlan->new(
				header    => $header,
				module    => $naming->moduleForHeader($header),
				tag       => $naming->exportTagForHeader($header),
				functions => \@functions,
				records   => \@records,
				constants => [ $self->_planConstants($header) ],
				enums     => $header->enums,
			  );
		}

		my @foreign = map { $self->_planRecord($_) } sort { $a->key cmp $b->key } grep { !$boundRecords{$_->key} } uniq @referencedRecords;

		return BindGen::Plan->new(
			headers        => \@headerPlans,
			callbacks      => [ map { $callbacks{$_} } sort keys %callbacks ],
			foreignRecords => \@foreign,
			report         => $report,
		);
	}

	method _skipFunction($function, $reason) {
		$report->skip('function', $function->name, $function->header->name, $reason);
		return undef;
	}

	method _planFunction($function) {
		my $exclusion = $filter->functionExclusion($function);
		return $self->_skipFunction($function, $exclusion)                                   if defined $exclusion;
		return $self->_skipFunction($function, 'variadic without a printf format attribute') if $function->variadic && !$function->isPrintfLike;

		my @params;
		foreach my $index (0 .. $function->params->$#*) {
			my $param   = $function->params->[$index];
			my $mapping = $mapper->map($param->type, 'param', fallbackCallbackId => $function->name . '__' . $param->name);
			return $self->_skipFunction($function, 'parameter ' . $param->name . ': ' . $mapping->reason) if $mapping->isUnsupported;
			push @params, {index => $index, name => $param->name, type => $param->type, mapping => $mapping};
		}

		my $callbackProblem = $self->_wireCallback($function, \@params);
		return $self->_skipFunction($function, $callbackProblem) if defined $callbackProblem;

		my $returns = $self->_mapResult($function);
		return $self->_skipFunction($function, 'return value: ' . $returns->reason) if $returns->isUnsupported;

		my $formatIndex = $function->isPrintfLike ? $function->format->{index} : undef;
		if (defined $formatIndex) {
			my $format = $params[$formatIndex] // return $self->_skipFunction($function, 'format attribute points past the parameters');
			return $self->_skipFunction($function, 'format parameter is not a string') if $format->{mapping}->kind ne 'string';
		}

		$self->_noteReferences($returns, map { $_->{mapping} } @params);
		$report->bound('function');
		return BindGen::Plan::BoundFunction->new(
			function    => $function,
			params      => \@params,
			returns     => $returns,
			formatIndex => $formatIndex,
			messageName => (defined $formatIndex ? _freeName('message', map { $_->{name} } @params) : undef),
		);
	}

	# The documentation decides whether a char * result is the caller's to free: borrowed pointers are copied only.
	method _mapResult($function) {
		my $owned   = defined $freeFunction && $function->comment->mentions($freeFunction);
		my $returns = $mapper->map($function->returns, 'return', ownedResult => $owned);
		$report->note('function', $function->name, $function->header->name, "char * result is copied but not freed: documentation does not mention " . ($freeFunction // 'a free function'))
		  if $returns->kind eq 'string' && !$model->resolve($model->resolve($function->returns)->pointee)->const;
		return $returns;
	}

	# Pairs a callback parameter with the function's single void * parameter. Returns a problem text or undef.
	method _wireCallback($function, $params) {
		my @callbacks = grep { $_->{mapping}->kind eq 'callback' } @$params;
		return undef                              if !@callbacks;
		return 'more than one callback parameter' if @callbacks > 1;

		my @slots = grep { $self->_isPlainVoidPointer($_->{type}) } @$params;
		return 'callback without exactly one void * userdata parameter' if @slots != 1;

		my $callback = $callbacks[0];
		my $problem  = $self->_planCallback($callback->{mapping}->id, $callback->{type});
		return $problem if defined $problem;

		$slots[0]{mapping} = BindGen::Mapping::CallbackData->new(type => $slots[0]{type}, callbackParam => 'sv_' . $callback->{name});
		return undef;
	}

	method _isPlainVoidPointer($type) {
		my $resolved = $model->resolve($type);
		return 0 if !$resolved->isPointer;
		my $pointee = $model->resolve($resolved->pointee);
		return $pointee->isVoid && !$pointee->const;
	}

	# Builds the trampoline plan for a callback type. Returns a problem text or undef.
	method _planCallback($id, $type) {
		return undef if $callbacks{$id};
		my $signature = $model->resolve($model->resolve($type)->pointee);
		my @slots     = grep { $self->_isPlainVoidPointer($signature->params->[$_]) } 0 .. $signature->params->$#*;
		return "callback type $id has no single void * parameter to carry the Perl code" if @slots != 1;

		my @params;
		foreach my $index (0 .. $signature->params->$#*) {
			if ($index == $slots[0]) { push @params, undef; next }
			my $mapping = $mapper->map($signature->params->[$index], 'callbackParam');
			return "callback type $id, parameter $index: " . $mapping->reason if $mapping->isUnsupported;
			push @params, $mapping;
		}
		my $returns = $mapper->map($signature->returns, 'callbackReturn');
		return "callback type $id, return value: " . $returns->reason if $returns->isUnsupported;

		$self->_noteReferences($returns, grep { defined } @params);
		$report->bound('callback');
		$callbacks{$id} = BindGen::Plan::Callback->new(id => $id, signature => $signature, slot => $slots[0], params => \@params, returns => $returns);
		return undef;
	}

	method _noteReferences(@mappings) {
		foreach my $mapping (@mappings) {
			$mapping = $mapping->inner if $mapping->kind eq 'out-reference';
			push @referencedRecords, $mapping->record if $mapping->kind eq 'record-pointer' || $mapping->kind eq 'record-value';
		}
		return;
	}

	method _planRecord($record) {
		return $boundRecords{$record->key} if $boundRecords{$record->key};
		my $class = $naming->classForRecord($record);
		my (@accessors, @nested);
		$self->_planFields($record, $class, \@accessors, \@nested) if !$record->isOpaque;
		$report->bound('record');
		return $boundRecords{$record->key} = BindGen::Plan::BoundRecord->new(record => $record, class => $class, accessors => \@accessors, nested => \@nested);
	}

	method _planFields($record, $class, $accessors, $nested) {
		my @taken = map { $_->name } @$accessors;
		foreach my $field ($record->fields->@*) {
			my $label = $class . '.' . ($field->name // '(anonymous)');
			if ($field->bitfield) {
				$report->skip('field', $label, $record->header ? $record->header->name : '-', 'bitfields are not supported');
				next;
			}
			if ($field->isAnonymousMember) {
				$self->_planFields($field->nested, $class, $accessors, $nested);
				next;
			}
			my $accessor = $self->_planAccessor($field, $label, $record, $nested);
			next if !$accessor;
			push @$accessors, $accessor;
		}
		return;
	}

	method _planAccessor($field, $label, $record, $nested) {
		my $headerName = $record->header ? $record->header->name : '-';
		my $name       = $naming->methodNameForField($field->name);
		my %common     = (name => $name, cPath => $field->name, comment => $field->comment);

		if ($field->nested) {
			if (!$field->type->isRecord) {
				$report->skip('field', $label, $headerName, 'arrays or pointers of unnamed records are not supported');
				return undef;
			}
			my $bound = $self->_planRecord($field->nested);
			push @$nested, $bound;
			return BindGen::Plan::Accessor->new(%common,
				mapping => BindGen::Mapping::RecordValue->new(type => $field->type, record => $field->nested, class => $bound->class, cTypeExpr => $field->nested->cTypeExpr));
		}
		if ($field->type->isArray) {
			if (!defined $field->type->length) {
				$report->skip('field', $label, $headerName, 'flexible array members are not supported');
				return undef;
			}
			my $element = $mapper->map($field->type->element, 'field');
			if ($element->isUnsupported) {
				$report->skip('field', $label, $headerName, 'array element: ' . $element->reason);
				return undef;
			}
			return BindGen::Plan::Accessor->new(%common, element => $element, length => $field->type->length);
		}
		my $mapping = $mapper->map($field->type, 'field');
		if ($mapping->isUnsupported) {
			$report->skip('field', $label, $headerName, $mapping->reason);
			return undef;
		}
		return BindGen::Plan::Accessor->new(%common, mapping => $mapping);
	}

	method _planConstants($header) {
		my @names;
		foreach my $macro ($header->macros->@*) {
			if ($macro->functionLike) {
				$report->skip('constant', $macro->name, $header->name, 'function-like macro');
				next;
			}
			if (defined $macro->problem) {
				$report->skip('constant', $macro->name, $header->name, $macro->problem);
				next;
			}
			push @names, $macro->name;
		}
		push @names, map { $_->name } map { $_->values->@* } $header->enums->@*;
		my @unique = uniq @names;
		$report->bound('constant') for @unique;
		return @unique;
	}

	sub _freeName($wanted, @taken) {
		my %taken = map { $_ => 1 } @taken;
		my $name  = $wanted;
		$name .= '_' while $taken{$name};
		return $name;
	}
}

1;
