# Copyright 2026 davenonymous
use v5.36;
use Object::Pad;

# Tells which of the library's public headers a file name from clang refers to, if any.
class BindGen::HeaderLocator {
	use Path::Tiny qw(path);
	use BindGen::Model::Header;

	field $model       : param;
	field $includeRoot : param;
	field %cache;    # file name as clang prints it => header object, or '' for foreign files

	ADJUST { $includeRoot = path($includeRoot)->realpath }

	# the header object for a file below the include root, undef for anything else
	method headerFor($file) {
		return undef if !defined $file;
		my $header = $cache{$file} //= $self->_locate($file);
		return $header || undef;
	}

	method _locate($file) {
		return '' if !path($file)->exists;
		my $real = path($file)->realpath;
		return '' if !$includeRoot->subsumes($real);
		my $relative = $real->relative($includeRoot)->stringify;
		return $model->header($relative) // $model->addHeader(BindGen::Model::Header->new(name => $real->basename, path => $relative));
	}
}

1;
