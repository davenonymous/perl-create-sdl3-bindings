# Copyright 2026 davenonymous
use v5.36;
use Object::Pad;

# Documentation attached to a declaration, extracted from clang's FullComment nodes.
class BindGen::Model::Comment {
	field $paragraphs : param : reader = [];    # plain text paragraphs in order
	field $params     : param : reader = {};    # param name => description
	field $blocks     : param : reader = [];    # [ { command => 'returns', text => ... }, ... ]

	method brief()   { return $paragraphs->[0] // '' }
	method isEmpty() { return !@$paragraphs && !%$params && !@$blocks }

	method mentions($word) {
		my @texts = (@$paragraphs, values %$params, map { $_->{text} } @$blocks);
		return scalar grep { /\b\Q$word\E\b/ } @texts;
	}

	method blockText($command) {
		my @matching = grep { $_->{command} eq $command } @$blocks;
		return join("\n", map { $_->{text} } @matching);
	}

	method fromAst : common ($node) {
		my (@paragraphs, %params, @blocks);
		foreach my $child (($node->{inner} // [])->@*) {
			my $kind = $child->{kind};
			if ($kind eq 'ParagraphComment') {
				my $text = _textOf($child);
				push @paragraphs, $text if $text ne '';
			}
			elsif ($kind eq 'ParamCommandComment') {
				$params{$child->{param} // ''} = _textOf($child);
			}
			elsif ($kind eq 'BlockCommandComment') {
				push @blocks, {command => $child->{name}, text => _textOf($child)};
			}
			elsif ($kind eq 'VerbatimBlockComment') {
				push @paragraphs, _verbatimOf($child);
			}
		}
		return $class->new(paragraphs => \@paragraphs, params => \%params, blocks => \@blocks);
	}

	sub _textOf($node) {
		my @lines;
		foreach my $child (($node->{inner} // [])->@*) {
			my $kind = $child->{kind};
			if    ($kind eq 'TextComment')          { push @lines, $child->{text} }
			elsif ($kind eq 'InlineCommandComment') { push @lines, join(' ', ($child->{args} // [])->@*) }
			elsif ($kind eq 'ParagraphComment')     { push @lines, _textOf($child) }
			elsif ($kind eq 'VerbatimBlockComment') { push @lines, _verbatimOf($child) }
		}
		return join(' ', grep { $_ ne '' } map { s/^\s+|\s+$//gr } @lines) =~ s/\s+/ /gr;
	}

	sub _verbatimOf($node) {
		my @lines = map { $_->{text} // '' } grep { $_->{kind} eq 'VerbatimBlockLineComment' } ($node->{inner} // [])->@*;
		return join("\n", map { "    $_" } @lines);
	}
}

1;
