# Copyright 2026 davenonymous
use v5.36;
use Object::Pad;

# Writes the XS distribution described by a plan. Static scaffolding comes
# from Template Toolkit templates, the per-declaration C and POD text is
# assembled here from the mappings.
class BindGen::Emitter {
	use Carp       qw(croak);
	use Path::Tiny qw(path);
	use Template;

	field $plan          : param;
	field $naming        : param;
	field $outputDir     : param;
	field $templateDir   : param;
	field $distVersion   : param;
	field $pkgConfigName : param;
	field $entryHeader   : param;    # e.g. SDL3/SDL.h, what the generated code includes
	field $template;
	field $out;
	field @written;

	ADJUST {
		$template = Template->new(INCLUDE_PATH => $templateDir, STRICT => 1, TRIM => 0) or croak Template->error;
		$out      = path($outputDir);
	}

	method root()     { return $naming->rootModule }
	method distFile() { return (split /::/, $naming->rootModule)[-1] }

	method emit() {
		my @headerPlans = grep { $_->hasContent } $plan->headers->@*;
		my @records     = $plan->allRecords;
		my %common      = (
			root         => $self->root,
			distFile     => $self->distFile,
			version      => $distVersion,
			entryHeader  => $entryHeader,
			pointerClass => $naming->pointerClass,
			structBase   => $naming->structBaseClass,
		);

		$self->_writeTemplate('Makefile.PL',       'Makefile.PL.tt', {%common, pkgConfig => $pkgConfigName, xsFiles => [ map { 'xs/' . $_->fileStem . '.xsh' } @headerPlans ]});
		$self->_writeTemplate('bindgen_runtime.h', 'runtime.h.tt',   \%common);
		$self->_write('bindgen_callbacks.h', join("\n", map { $self->_trampoline($_) } $plan->callbacks->@*) . "\n");
		$self->_writeTemplate($self->distFile . '.xs',                          'main.xs.tt',        {%common, includes => [ map { 'xs/' . $_->fileStem . '.xsh' } @headerPlans ]});
		$self->_writeTemplate($naming->fileForModule($naming->structBaseClass), 'struct_base.pm.tt', \%common);
		$self->_writeTemplate($naming->fileForModule($naming->pointerClass),    'pointer.pm.tt',     \%common);

		foreach my $headerPlan (@headerPlans) {
			$self->_write('xs/' . $headerPlan->fileStem . '.xsh', $self->_headerXs($headerPlan));
			$self->_writeApiModule($headerPlan, \%common);
		}
		foreach my $bound (@records) {
			$self->_writeTemplate($naming->fileForModule($bound->class), 'record.pm.tt', {%common, %{$self->_recordVars($bound)}});
		}
		$self->_writeTemplate(
			$naming->fileForModule($self->root),
			'root.pm.tt',
			{
				%common,
				apiModules   => [ map { $_->module } @headerPlans ],
				tags         => [ map { {name => $_->tag, module => $_->module} } @headerPlans ],
				classModules => [ sort map { $_->class } @records ],
			}
		);
		$self->_writeTemplate('t/00-load.t',   'load.t.tt',   \%common);
		$self->_writeTemplate('t/01-struct.t', 'struct.t.tt', {%common, sample => $self->_sampleRecord(@records)});
		$self->_writeTemplate(
			'README.md',
			'README.md.tt',
			{
				%common,
				pkgConfig => $pkgConfigName,
				headers   => [ map { {module => $_->module, header => $_->header->name, functions => scalar $_->functions->@*, constants => scalar $_->constants->@*} } @headerPlans ]
			}
		);
		$self->_write('bindgen-report.txt', $plan->report->asText);
		return [@written];
	}

	method _write($relative, $content) {
		my $file = $out->child($relative);
		$file->parent->mkdir;
		$file->spew_utf8($content);
		push @written, $relative;
		return;
	}

	method _writeTemplate($relative, $templateName, $vars) {
		my $content = '';
		$template->process($templateName, $vars, \$content) or croak "template $templateName: " . $template->error;
		return $self->_write($relative, $content);
	}

	# ---- XS -----------------------------------------------------------------

	method _headerXs($headerPlan) {
		my @parts = ("MODULE = " . $self->root . "  PACKAGE = " . $headerPlan->module, '');
		push @parts, map { $self->_functionXs($_) } $headerPlan->functions->@*;
		push @parts, $self->_constantsBoot($headerPlan) if $headerPlan->constants->@*;
		push @parts, map { $self->_recordXs($_) } map { $_->withNested } $headerPlan->records->@*;
		return join("\n", @parts);
	}

	method _functionXs($bound) {
		my $function = $bound->function;
		my $name     = $function->name;
		my @svNames  = map { "sv_$_" } $bound->perlParamNames;
		my (@declare, @prepare, @args, @writeback);

		foreach my $param ($bound->params->@*) {
			if ($bound->isPrintfLike && $param->{index} == $bound->formatIndex) {
				push @args, '"%s"';
				next;
			}
			my ($var, $mapping) = ($param->{name}, $param->{mapping});
			my $ctx = "\"$name($var)\"";
			push @declare, $mapping->declareCode($var);
			push @prepare, $mapping->prepareCode($var, "sv_$var", $ctx);
			push @args,    $mapping->argumentExpr($var);
			my $writeback = $mapping->writebackCode($var);
			push @writeback, $writeback if $writeback ne '';
		}
		if ($bound->isPrintfLike) {
			my $message = $bound->messageName;
			push @declare, "const char *c_$message;";
			push @prepare, "c_$message = bg_in_string(aTHX_ sv_$message, \"$name($message)\");";
			push @args,    "(c_$message ? c_$message : \"\")";
		}

		my $returns = $bound->returns;
		my $isVoid  = $returns->kind eq 'void';
		push @declare, $returns->declareCode('bg_ret') if !$isVoid;
		my $call = "$name(" . join(', ', @args) . ');';
		$call = "c_bg_ret = $call" if !$isVoid;
		my @result = $isVoid ? ('XSRETURN(0);') : ('ST(0) = sv_2mortal(' . $returns->outputCode('c_bg_ret') . ');', 'XSRETURN(1);');

		return join("\n",
			'void',
			"$name(" . join(', ', @svNames) . ')',
			(map { "\tSV *$_" } @svNames),
			(@declare ? ('    PREINIT:', map { "\t$_" } @declare) : ()),
			'    PPCODE:', (map { "\t$_" } @prepare, $call, @writeback, @result), '',);
	}

	method _constantsBoot($headerPlan) {
		return join("\n",
			'BOOT:', "\t{",
			"\tHV *stash = gv_stashpv(\"" . $headerPlan->module . "\", GV_ADD);",
			(map { "\tbg_export_constant(aTHX_ stash, \"$_\", BG_CONST_SV($_));" } $headerPlan->constants->@*),
			"\t}", '',);
	}

	method _recordXs($bound) {
		return '' if $bound->isOpaque;
		my $class = $bound->class;
		my $ctype = $bound->cTypeExpr;
		my @parts = ("MODULE = " . $self->root . "  PACKAGE = $class", '');
		push @parts, join("\n", 'void', '_alloc(sv_class)',  "\tSV *sv_class", '    PPCODE:', "\tST(0) = sv_2mortal(bg_new_record(aTHX_ sizeof($ctype), SvPV_nolen(sv_class)));", "\tXSRETURN(1);", '');
		push @parts, join("\n", 'void', '_sizeof(sv_class)', "\tSV *sv_class", '    PPCODE:', "\tPERL_UNUSED_VAR(sv_class);", "\tST(0) = sv_2mortal(newSVuv(sizeof($ctype)));", "\tXSRETURN(1);", '');
		push @parts, map { $self->_accessorXs($bound, $_) } $bound->accessors->@*;
		return join("\n", @parts);
	}

	method _accessorXs($bound, $accessor) {
		my $class = $bound->class;
		my $ctype = $bound->cTypeExpr;
		my $name  = $accessor->name;
		my $path  = $accessor->cPath;
		my $ctx   = "\"${class}::$name\"";
		my @head  = ('void', "$name(sv_self, ...)", "\tSV *sv_self", '    PREINIT:', "\t$ctype *self;");
		my @fetch = ("self = ($ctype *)bg_in_record_value_ptr(aTHX_ sv_self, \"$class\", $ctx);");

		if (!$accessor->isArray) {
			my $mapping = $accessor->mapping;
			return join(
				"\n", @head,
				'    PPCODE:',
				map({ "\t$_" } @fetch,
					'if (items > 1) {',
					"\tself->$path = " . $mapping->inputCode('ST(1)', $ctx) . ';',
					"\tXSRETURN(1);", '}', 'ST(0) = sv_2mortal(' . $mapping->fieldOutputCode("self->$path") . ');',
					'XSRETURN(1);',),
				''
			);
		}

		my $element = $accessor->element;
		my $length  = $accessor->length;
		return join(
			"\n", @head,
			"\tSize_t bg_i;",
			'    PPCODE:',
			map({ "\t$_" } @fetch,
				'if (items > 1) {',
				"\tif (items - 1 != $length) croak(\"%s expects $length values, got %d\", $ctx, (int)(items - 1));",
				"\tfor (bg_i = 0; bg_i < $length; bg_i++) self->${path}[bg_i] = " . $element->inputCode('ST(1 + bg_i)', $ctx) . ';',
				"\tXSRETURN(1);",
				'}',
				"EXTEND(SP, $length);",
				"for (bg_i = 0; bg_i < $length; bg_i++) mPUSHs(" . $element->outputCode("self->${path}[bg_i]") . ');',
				"XSRETURN($length);",
			),
			''
		);
	}

	method _trampoline($callback) {
		my $signature = $callback->signature;
		my @types     = $signature->params->@*;
		my $isVoid    = $callback->returns->kind eq 'void';
		my $cParams   = @types ? join(', ', map { $types[$_]->declare("a$_") } 0 .. $#types) : 'void';
		my @body      = (
			"bg_callback_holder *holder = (bg_callback_holder *)a" . $callback->slot . ';',
			'dTHXa(holder->perl);', 'dSP;', 'int count;', ($isVoid ? () : $callback->returns->declareCode('bg_ret')),
			'ENTER;', 'SAVETMPS;', 'PUSHMARK(SP);', 'EXTEND(SP, ' . scalar(@types) . ');',
		);
		foreach my $index (0 .. $#types) {
			my $mapping = $callback->params->[$index];
			push @body, defined $mapping ? 'mPUSHs(' . $mapping->outputCode("a$index") . ');' : 'PUSHs(holder->data);';
		}
		push @body,
		  'PUTBACK;',
		  'count = call_sv(holder->code, G_EVAL | ' . ($isVoid ? 'G_DISCARD' : 'G_SCALAR') . ');',
		  'SPAGAIN;',
		  ($isVoid ? () : 'memset(&c_bg_ret, 0, sizeof(c_bg_ret));'),
		  'if (SvTRUE(ERRSV)) {',
		  "\twarn(\"callback " . $callback->id . ' died: %" SVf, SVfARG(ERRSV));',
		  '}',
		  ($isVoid ? () : ('else if (count > 0) {', "\tc_bg_ret = " . $callback->returns->inputCode('POPs', "\"callback " . $callback->id . " return value\"") . ';', '}')),
		  'PUTBACK;',
		  'FREETMPS;',
		  'LEAVE;',
		  ($isVoid ? () : 'return c_bg_ret;');
		return join("\n", 'static ' . $callback->returns->cType . ' ' . $callback->trampoline . "($cParams) {", (map { "\t$_" } @body), '}', '');
	}

	# ---- Perl modules and POD ---------------------------------------------------

	method _writeApiModule($headerPlan, $common) {
		my @functions = $headerPlan->functions->@*;
		$self->_writeTemplate(
			$naming->fileForModule($headerPlan->module),
			'api.pm.tt',
			{
				%$common,
				module      => $headerPlan->module,
				header      => $headerPlan->header->name,
				functions   => [ map { $_->name } @functions ],
				constants   => $headerPlan->constants,
				functionPod => join("\n", map { $self->_functionPod($_) } @functions),
				enumPod     => join("\n", map { $self->_enumPod($_) } $headerPlan->enums->@*),
			}
		);
		return;
	}

	method _functionPod($bound) {
		my $function = $bound->function;
		my $comment  = $function->comment;
		my @names    = $bound->perlParamNames;
		my $call     = $function->name . '(' . join(', ', map { "\$$_" } @names) . ')';
		my $isVoid   = $bound->returns->kind eq 'void';
		my @pod      = ('=head2 ' . $function->name, '', ($isVoid ? "  $call;" : "  my \$result = $call;"), '', 'C: C<< ' . _cSignature($function) . ' >>', '');
		push @pod, map { (_podEscape($_), '') } $comment->paragraphs->@*;

		if (@names) {
			push @pod, '=over', '';
			foreach my $param ($bound->params->@*) {
				next if $bound->isPrintfLike && $param->{index} == $bound->formatIndex;
				my $description = $comment->params->{$param->{name}} // '';
				push @pod, '=item ' . $param->{name} . ' - ' . $param->{mapping}->perlDoc . ($description ne '' ? '. ' . _podEscape($description) : ''), '';
			}
			push @pod, '=item ' . $bound->messageName . ' - string, substituted for the format string and its arguments', '' if $bound->isPrintfLike;
			push @pod, '=back',                                                                                           '';
		}
		if (!$isVoid) {
			my $returnsText = $comment->blockText('returns');
			push @pod, 'Returns ' . $bound->returns->perlDoc . ($returnsText ne '' ? ': ' . _podEscape($returnsText) : '.'), '';
		}
		foreach my $block ([ 'since', 'Since' ], [ 'threadsafety', 'Thread safety' ]) {
			my $text = $comment->blockText($block->[0]);
			push @pod, "$block->[1]: " . _podEscape($text), '' if $text ne '';
		}
		return join("\n", @pod);
	}

	method _enumPod($enum) {
		my @pod = ('=head2 ' . ($enum->name // 'anonymous enum'), '');
		push @pod, _podEscape($enum->comment->brief), '' if $enum->comment && $enum->comment->brief ne '';
		push @pod, '=over', '',
		  (map { ('=item ' . $_->name . ' = ' . ($_->value // '?') . ($_->comment && $_->comment->brief ne '' ? ' - ' . _podEscape($_->comment->brief) : ''), '') } $enum->values->@*), '=back', '';
		return join("\n", @pod);
	}

	method _recordVars($bound) {
		my $record = $bound->record;
		my @fields = map { {name => $_->name, doc => $_->perlDoc, text => _podEscape($_->comment ? $_->comment->brief : '')} } $bound->accessors->@*;
		return {
			class => $bound->class,
			cName => (
				$record->isNested
				? "unnamed " . $record->tag . " stored in field '" . $record->parentField . "' of " . $naming->classForRecord($record->parent)
				: $record->tag . ' ' . ($record->name // '')
			),
			tag         => $record->tag,
			opaque      => $bound->isOpaque,
			fields      => \@fields,
			description => ($record->comment ? _podEscape($record->comment->brief) : ''),
		};
	}

	method _sampleRecord(@records) {
		foreach my $bound (@records) {
			next if $bound->isOpaque || $bound->record->isNested;
			my ($accessor) = grep { !$_->isArray && $_->mapping->kind eq 'integer' } $bound->accessors->@*;
			next if !$accessor;
			return {class => $bound->class, field => $accessor->name};
		}
		return undef;
	}

	sub _cSignature($function) {
		my $params = join(', ', map { $_->type->render . ' ' . $_->name } $function->params->@*);
		$params .= ', ...' if $function->variadic;
		return $function->returns->render . ' ' . $function->name . '(' . ($params eq '' ? 'void' : $params) . ')';
	}

	sub _podEscape($text) {
		return $text =~ s/^=/ =/mgr =~ s/([A-Z])</$1E<lt>/gr;
	}
}

1;
