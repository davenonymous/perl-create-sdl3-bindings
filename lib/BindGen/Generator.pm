# Copyright 2026 davenonymous
use v5.36;
use Object::Pad;

# Runs the pipeline: clang -> model -> macro probe -> plan.
class BindGen::Generator {
	use Path::Tiny qw(path);
	use BindGen::Clang;
	use BindGen::Model;
	use BindGen::Model::Macro;
	use BindGen::HeaderLocator;
	use BindGen::Parser;
	use BindGen::MacroProbe;
	use BindGen::Planner;
	use BindGen::Report;

	field $clangBinary  : param;
	field $clangArgs    : param = [];
	field $includeRoot  : param;
	field $entryHeader  : param;    # relative to the include root
	field $naming       : param;
	field $filter       : param;
	field $freeFunction : param = undef;
	field $logger       : param = sub { };

	method buildPlan() {
		my $clang     = BindGen::Clang->new(binary => $clangBinary, includeDirs => [$includeRoot], extraArgs => $clangArgs);
		my $entryFile = path($includeRoot)->child($entryHeader)->stringify;
		die "entry header $entryFile does not exist\n" if !-f $entryFile;

		$logger->('using ' . $clang->version);
		$logger->("parsing $entryFile");
		my $ast     = $clang->dumpAst($entryFile);
		my $formats = $clang->dumpFormatAttributes($entryFile);

		my $model   = BindGen::Model->new;
		my $locator = BindGen::HeaderLocator->new(model => $model, includeRoot => $includeRoot);
		BindGen::Parser->new(model => $model, locator => $locator, formats => $formats)->parse($ast);
		$logger->(sprintf('found %d headers, %d functions, %d records, %d enums', scalar $model->headers->@*, scalar $model->functions->@*, scalar $model->records->@*, scalar $model->enums->@*));

		$self->_collectMacros($model, $locator, $clang->dumpDefines($entryFile));
		my $scratch = Path::Tiny->tempdir;
		BindGen::MacroProbe->new(clang => $clang, entryInclude => "#include <$entryHeader>", scratchDir => "$scratch")->probe($model->macros);
		$logger->(sprintf('found %d macros', scalar $model->macros->@*));

		return BindGen::Planner->new(model => $model, naming => $naming, filter => $filter, freeFunction => $freeFunction, report => BindGen::Report->new)->plan;
	}

	method _collectMacros($model, $locator, $defines) {
		my %latest;    # the last definition of a name wins and an #undef removes it, as for the compiler
		foreach my $define (@$defines) {
			if ($define->{undefined}) {
				delete $latest{$define->{name}};
				next;
			}
			my $header = $locator->headerFor($define->{file}) // next;
			$latest{$define->{name}} = BindGen::Model::Macro->new(name => $define->{name}, body => $define->{body}, functionLike => (defined $define->{args} ? 1 : 0), header => $header);
		}
		foreach my $name (sort keys %latest) {
			my $macro = $latest{$name};
			$model->addMacro($macro);
			$macro->header->addMacro($macro);
		}
		return;
	}
}

1;
