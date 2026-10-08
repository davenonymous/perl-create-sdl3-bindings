# Copyright 2026 davenonymous
use v5.36;
use Object::Pad;

# Collects every declaration the generator left out and why, so nothing is skipped silently.
class BindGen::Report {
	field @entries;    # { kind, name, header, reason }
	field @notes;      # { kind, name, header, text } about declarations that were bound but deserve attention
	field %counts;     # kind => { bound => n, skipped => n }

	method skip($kind, $name, $header, $reason) {
		push @entries, {kind => $kind, name => $name, header => $header, reason => $reason};
		$counts{$kind}{skipped}++;
		return $self;
	}

	method note($kind, $name, $header, $text) {
		push @notes, {kind => $kind, name => $name, header => $header, text => $text};
		return $self;
	}

	method bound($kind) { $counts{$kind}{bound}++; return $self }

	method entries() { return [@entries] }
	method counts()  { return {%counts} }

	method summaryLines() {
		my @lines;
		foreach my $kind (sort keys %counts) {
			my $bound   = $counts{$kind}{bound}   // 0;
			my $skipped = $counts{$kind}{skipped} // 0;
			push @lines, sprintf('%-10s %5d bound, %5d skipped', $kind, $bound, $skipped);
		}
		return @lines;
	}

	method detailLines() {
		my @lines;
		foreach my $entry (sort { $a->{header} cmp $b->{header} || $a->{kind} cmp $b->{kind} || $a->{name} cmp $b->{name} } @entries) {
			push @lines, sprintf('%-20s %-10s %-45s %s', $entry->{header}, $entry->{kind}, $entry->{name}, $entry->{reason});
		}
		return @lines;
	}

	method noteLines() {
		return map { sprintf('%-20s %-10s %-45s %s', $_->{header}, $_->{kind}, $_->{name}, $_->{text}) } sort { $a->{header} cmp $b->{header} || $a->{name} cmp $b->{name} } @notes;
	}

	method asText() {
		return join("\n", 'Summary', '=======', $self->summaryLines, '', 'Skipped declarations', '====================', $self->detailLines, '', 'Notes', '=====', $self->noteLines) . "\n";
	}
}

1;
