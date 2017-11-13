package SitemasonPl::Normalize 8.0;

=head1 NAME

SitemasonPl::Normalize

=head1 DESCRIPTION


=head1 METHODS

=cut

use v5.012;
use strict;
use utf8;
use constant TRUE => 1;
use constant FALSE => 0;

use DateTime;
use DateTime::TimeZone;
use Text::DoubleMetaphone qw( double_metaphone );
use Text::Levenshtein::Damerau;
use Text::Unidecode;

use SitemasonPl::Common;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(
	compareTitles compareVenueTitles compareAddresses doubleMetaphone normalizeTitle phoneticizeTitle
	unplural translate getAddressScore convertNumbers normalizeFull normalizeAddress stripBoxFromAddress cleanAddress normalizeCity areSimilar getTimeZone
);

#=====================================================

=head2 B<notes>

Things to investigate:
 Stemmers: http://tartarus.org/~martin/PorterStemmer/perl.txt

=cut
#=====================================================



#=====================================================

=head2 B<compareTitles>

 my ($wordRatio, $editRatio, $wordCount) = compareTitles($titleA, $titleB);
 my ($wordRatio, $editRatio, $wordCount) = compareTitles( {
 	normalizedA	=> 'first-word',	# output from normalizeTitle 
 	normalizedB	=> 'second-word',
 	phoneticA	=> 'FST-WRD',		# output from phoneticizeTitle
 	phoneticB	=> 'SCND-WRD'
 } );

All comparisons are made with normalized double metaphone versions of the titles.

wordRatio returns a ratio of the number of matched words divided by the total number of words.
 1 - all words match
 0 - no words match

editRatio returns the Damerau–Levenshtein distance divided by the number of characters in the title. http://en.wikipedia.org/wiki/Damerau–Levenshtein_distance
 0 - no difference in characters
 1 - completely different

=cut
#=====================================================
sub compareTitles {
	my $args = shift || return;
	my $titleB = shift;
	my $results = [];
	
	# Convert two strings into args hash
	if (isText($args)) {
		my $titleA = $args;
		$args = {};
		$args->{normalizedA} = normalizeFull($titleA);
		$args->{normalizedB} = normalizeFull($titleB);
		$args->{phoneticA} = phoneticizeTitle($args->{normalizedA});
		$args->{phoneticB} = phoneticizeTitle($args->{normalizedB});
	}
	isHash($args) || return;
	
	# Quick answer on exact match
	if ($args->{normalizedA} eq $args->{normalizedB}) {
		my @words = split('-', $args->{normalizedA});
		my $wordCount = @words;
		push(@{$results}, "Full match: $args->{normalizedA} eq $args->{normalizedB}");
		return (1, $wordCount, $results);
	}
	
	# Separate words
	my $a = {};
	my $b = {};
	$a->{norm} = $args->{normalizedA};
	$b->{norm} = $args->{normalizedB};
	$a->{phon} = $args->{phoneticA};
	$b->{phon} = $args->{phoneticB};
	if ($args->{checkSynonyms}) {
		my ($synA, $synB) = _checkSynonyms($a->{norm}, $b->{norm});
		if ($synA) {
			push(@{$results}, "Synonyms: $a->{norm} -> $synA | $b->{norm} -> $synB");
			$a->{norm} = $synA;
			$b->{norm} = $synB;
			$a->{phon} = phoneticizeTitle($a->{norm});
			$b->{phon} = phoneticizeTitle($b->{norm});
		}
	}
	$a->{words} = [split('-', $a->{norm})];
	$b->{words} = [split('-', $b->{norm})];
	$a->{meta} = [split('-', $a->{phon})];
	$b->{meta} = [split('-', $b->{phon})];
	if (scalar @{$b->{words}} > scalar @{$a->{words}}) { my $tmp = $a; $a = $b; $b = $tmp; }
	
	if ($args->{address}) { push(@{$results}, "Compare addresses: $a->{norm} to $b->{norm}"); }
	else { push(@{$results}, "Compare titles: $a->{norm} to $b->{norm}"); }
	
	# Match words
	my $wordCount = 0;
	my $wordMatch = 0;
	my @leftoverA;
	my @leftoverB;
	my @leftoverWordsA;
	if ($args->{address}) { loadCommonAddressWords(); }
	else { loadCommonWords(); }
	for (my $i = 0; $i < @{$a->{meta}}; $i++) {
		my $meta1 = $a->{meta}->[$i];
		my $word1 = $a->{words}->[$i];
		
		# If no more b, then collect leftovers
		if ($i >= @{$b->{meta}}) {
			push(@leftoverA, $meta1);
			push(@leftoverWordsA, $word1);
			$wordCount += .5;
			push(@{$results}, "  leftover: $word1 ($meta1) | 0 / .5 | $wordMatch / $wordCount");
			next;
		}
		
		my $meta2 = $b->{meta}->[$i];
		my $word2 = $b->{words}->[$i];
		
		my $counter;
		my $multiplier = 1;
		if ($args->{address} && $SitemasonPl::Normalize::commonAddressWords->{$word1}) { $counter = .5; $multiplier = .5; }
		elsif (!$args->{address} && $SitemasonPl::Normalize::commonWords->{$word1}) { $counter = .5; $multiplier = .5; }
		else { $counter = 1; }
		$wordCount += $counter;
		
		my $score = 0;
		my $reason;
		# Normalized match
		if ($word1 eq $word2) { $score = 1; $reason = 'exact'; }
		# Address phonetic match
		elsif ($args->{address}) { $score = _compareMetaphones($meta1, $meta2) * .8; $reason = 'address'; }
		# Phonetic match
		elsif ($meta1 eq $meta2) { $score = .8; $reason = 'phonetic'; }
		
		if ($score) {
			$score *= $multiplier;
			$wordMatch += $score;
		}
		# Non-matching leftovers
		else {
			$score = '0';
			$reason = 'no match';
			push(@leftoverA, $meta1);
			push(@leftoverWordsA, $word1);
			push(@leftoverB, $meta2);
		}
		push(@{$results}, "  $reason: $word1 ($meta1) <> $word2 ($meta2) | $score / $counter | $wordMatch / $wordCount");
	}
	
	# Check for out-of-order words 
	if (@leftoverA && @leftoverB) {
		for (my $i = 0; $i < @leftoverA; $i++) {
			my $meta1 = $leftoverA[$i];
			my $word1 = $leftoverWordsA[$i];
			
			my $multiplier = 1;
			if ($args->{address} && $SitemasonPl::Normalize::commonAddressWords->{$word1}) { $multiplier = .5; }
			elsif (!$args->{address} && $SitemasonPl::Normalize::commonWords->{$word1}) { $multiplier = .5; }
			
			# Match anywhere
			my @leftoverBTemp;
			my $score = 0;
			my $meta2;
			foreach $meta2 (@leftoverB) {
				# Phonetic match
				if ($args->{address}) { $score = _compareMetaphones($meta1, $meta2) * .7; }
				elsif ($meta1 eq $meta2) { $score = .7; }
				
				if ($score) { last; }
				else { push(@leftoverBTemp, $meta2); }
			}
			if ($score) {
				$score *= $multiplier;
				$wordMatch += $score;
				push(@{$results}, "  extra: $word1 ($meta1) <> ($meta2) | $score | $wordMatch");
			} else {
				push(@{$results}, "  extra: $word1 ($meta1) | 0 | $wordMatch");
			}
			@leftoverB = @leftoverBTemp;
		}
	}
	
	# Calculate ratios
	my $wordRatio = 0;
	if ($wordCount) { $wordRatio = $wordMatch / $wordCount; }
	push(@{$results}, "final: $wordMatch / $wordCount = $wordRatio");
	return ($wordRatio, $wordCount, $results);
}


sub compareAddresses {
	my $args = shift || return;
	
	my $a = {};
	my $b = {};
	my (@wordsA, @wordsB, @metaA, @metaB);
	
	if (isHash($args)) {
		$a->{norm} = $args->{normalizedA};
		$b->{norm} = $args->{normalizedB};
		@wordsA = split('-', $a->{norm});
		@wordsB = split('-', $b->{norm});
		@metaA = split('-', $args->{phoneticA});
		@metaB = split('-', $args->{phoneticB});
	} else { return; }
	
	# Match words
	my $wordMatch = 0;
	my @leftoverA;
	my @leftoverB;
	for (my $i = 0; $i < @metaA; $i++) {
		my $meta1 = $metaA[$i];
		my $meta2 = $metaB[$i];
		
		my $score = 0;
		# Normalized match
		if ($wordsA[$i] eq $wordsB[$i]) { $score = 1; }
		# Phonetic match
		else { $score = _compareMetaphones($meta1, $meta2) * .8; }
		
		if ($score) { $wordMatch += $score; }
		# Non-matching leftovers
		else {
			push(@leftoverA, $meta1);
			push(@leftoverB, $meta2);
		}
	}
	# If @metaB is bigger, catch the rest of the words
	my $sizeDiff = scalar @metaB - scalar @metaA;
	if ($sizeDiff > 0) {
		for (my $i = @metaA; $i < @metaB; $i++) {
			push(@leftoverB, $metaB[$i]);
		}
	}
	
	# Check for out-of-order words 
	if (@leftoverA && @leftoverB) {
		foreach my $meta1 (@leftoverA) {
			# Match anywhere
			my @leftoverBTemp;
			my $score = 0;
			foreach my $meta2 (@leftoverB) {
				$score = _compareMetaphones($meta1, $meta2);
				
				if ($score) { last; }
				else { push(@leftoverBTemp, $meta2); }
			}
			$wordMatch += ($score / 2);
			@leftoverB = @leftoverBTemp;
		}
	}
	
	my $wordCount = @wordsA;
	if (@wordsB > $wordCount) { $wordCount = @wordsB; }
	
	# Calculate ratios
	my $wordRatio = 0;
	if ($wordCount) { $wordRatio = $wordMatch/$wordCount; }
	return ($wordRatio, $wordCount);
}

sub _checkSynonyms {
	my $normA = shift;
	my $normB = shift;
	loadSynonyms();
	foreach my $values (@{$SitemasonPl::Normalize::synonyms}) {
		my ($matchA, $matchB);
		my $isA;
		foreach my $value (@{$values}) {
			if ($normA =~ /\b$value\b/) { $matchA = $value; $isA = TRUE; last; }
		}
		$isA || next;
		
		my $isB;
		foreach my $value (@{$values}) {
			if ($normB =~ /\b$value\b/) { $matchB = $value; $isB = TRUE; last; }
		}
		$isB || next;
		
		$normA =~ s/\b$matchA\b/$values->[0]/g;
		$normB =~ s/\b$matchB\b/$values->[0]/g;
		return ($normA, $normB);
	}
}

sub _compareMetaphones {
	my $metaA = shift;
	my $metaB = shift;
	
	# Compare ordinals
	if (isOrdinal($metaA) && isOrdinal($metaB)) {
		if ($metaA eq $metaB) { return 1; }
		$metaA =~ s/(?:st|nt|rt|th)$//;
		$metaB =~ s/(?:st|nt|rt|th)$//;
		if ($metaA == $metaB) { return 1; }
		if (isClose($metaA, $metaB, 1)) { return .25; }
		return 0;
	}
	
	# Compare text
	if (!isPosInt($metaA) || !isPosInt($metaB)) {
		if ($metaA eq $metaB) { return 1; }
		return 0;
	}
	
	# Compare numbers
	# If match, perfect score
	if ($metaA == $metaB) { return 1; }
	
	# If numerically close, give a higher score
	if (isClose($metaA, $metaB, 2)) { return .85; }
	elsif (isClose($metaA, $metaB, 4)) { return .7; }
	
	# Find Damerau-Levenshtein edit distance
	my $tld = Text::Levenshtein::Damerau->new($metaA);
	my $metaEdit = $tld->dld($metaB);
	if ($metaEdit == 1) { return .4; }
	return 0;
}

sub doubleMetaphone {
	my $word = shift;
	defined($word) || return;
	my @parts = $word =~ /(\d+(?=\D)|\D+(?=\d)|\d+$|\D+)/g;
	my $code;
	foreach my $part (@parts) {
		if ($part =~ /^\d+$/) { $code .= $part; }
		else {
			my ($code1, $code2) = double_metaphone($part);
			if ($code1) { $code .= $code1; }
			else { $code .= uc($part); }
		}
	}
	return $code;
}

sub normalizeTitle {
	my $input = lc(shift);
	defined($input) || return;
	
	# Translate foreign characters
	$input = unidecode($input);
	
	# Translate symbols to text
	$input =~ s/&amp;/ and /g;
	$input =~ s/&/ and /g;
	$input =~ s/-n-/ and /g;
	$input =~ s/\+/ plus /g;
	
	# Convert numbers and symbols used as text
	$input =~ s/([a-z])\$(?=[a-z])/${1}s/g;
	$input =~ s/([a-z])0(?=[a-z])/${1}o/g;
	$input =~ s/([a-z])00(?=[a-z])/${1}oo/g;
	$input =~ s/([a-z])3(?=[a-z])/${1}e/g;
	$input =~ s/([a-z])33(?=[a-z])/${1}ee/g;
	$input =~ s/([a-z])5(?=[a-z])/${1}s/g;
	
	# Combine w-w+ words
	# Test against bar-bq, barb-bq, barb-q, bar-b-q, bar-b-que, barb-b-q, barb-be-que, barb-e-cue
	$input =~ s/\b([a-z])-(?=[a-z])/$1/g;
	$input =~ s/([a-z])-(?=[a-z]\b)/$1/g;
	
	# Combine contractions and possessives
	$input =~ s/(\w)['`](?=\w)/$1/g;
	
	# Strip number commas
	$input =~ s/(\d),(?=\d{3}(?:\D|$))/$1/g;
	
	$input =~ s/[\p{P}\p{S}\p{Z}]+/-/g;
	$input =~ s/[^a-z0-9-]//g;
	$input =~ s/(-(the|a|an)\b|\b(the|a|an)-)//g;
	$input =~ s/--+/-/g;
	$input =~ s/(^-+|-+$)//g;
	$input =~ s/-(un)?inc(orporated)?$//;
	
	# Separate numbers and text
	$input =~ s/([a-z])(?=\d)/$1-/g;
	$input =~ s/(\d)s\b/$1/g;
	my @words = split('-', $input);
	my @newWords;
	foreach my $word (@words) {
		if ($word !~ /\d(?:st|nd|rd|th|ers?)\b/) { 
			$word =~ s/(\d)(?=[a-z])/$1-/g;
		}
		push(@newWords, $word);
	}
	$input = join('-', @newWords);
	
	# Multi-word replacements
	$input =~ s/\b(?:barb?\-b?(?:q|que|cue)|barb?\-be?\-(?:q|que|cue)|barb\-e(?:q|que|cue)|barbq)\b/bbq/g;
	
	return $input;
}

sub phoneticizeTitle {
	my $normalized = shift;
	defined($normalized) || return;
	if ($normalized =~ /[^a-z0-9-]/) { $normalized = normalizeTitle($normalized); }
	my @words = split('-', $normalized);
	my @meta;
	foreach my $word (@words) {
		my $code = doubleMetaphone($word);
		if (defined($code)) { push(@meta, $code); }
	}
	return join('-', @meta);
}

sub unplural {
	my $word = shift;
	my $singular = $word;
	my $map = {
		'dallas' => 1,
		'angeles' => 1,
		'christmas' => 1
	};
	if (length($singular) >= 4) {
		if ($singular =~ s/(s|x|ch|sh)es$/$1/) { }
		elsif ($singular =~ /(?:[isux]|ch|sh|[aeiou]o)s$/) { }
		else { $singular =~ s/s$//; }
	}
	return $singular;
}

# $word = translate($normalized_word);
sub translate {
	my $word = shift;
	loadTranslations();
	my $translation = $SitemasonPl::Normalize::translations->{$word};
	$translation && return $translation;
	return $word;
}

# $phrase = hyphenate($normalized_word);
sub hyphenate {
	my $word = shift;
	loadHyphenated();
	my $hyphenated = $SitemasonPl::Normalize::hyphenated->{$word};
	$hyphenated && return $hyphenated;
	return $word;
}

# $word = compound($phrase);
sub compound {
	my $word1 = shift || return;
	my $word2 = shift || return;
	loadCompounds();
	my $compound = $SitemasonPl::Normalize::compounds->{"$word1-$word2"};
	$compound && return $compound;
	return;
}

# $word = unabbreviateAddress($word);
sub unabbreviateAddress {
	my $word = shift;
	loadAddressAbbreviations();
	my $translation = $SitemasonPl::Normalize::addressAbbreviations->{$word};
	$translation && return $translation;
	return $word;
}

sub getAddressScore {
	my $venue = shift || return;
	if (isText($venue)) { $venue = { address => $venue }; }
	isHash($venue) || return;
	$venue->{address} || return 0;
	
	my $addressOnly = TRUE;
	my $score = 0;
	if (($venue->{city} && $venue->{state}) || $venue->{postal_code}) {
		undef $addressOnly;
		$venue->{city_normalized} ||= normalizeFull($venue->{city});
		$venue->{state_code} ||= getStateCode($venue->{state});
		if (!$venue->{postal_clean}) {
			my ($code, $cc) = getPostalCode($venue->{postal_code});
			if ($code) { $venue->{postal_clean} = $code; }
		}
		if ($venue->{city_normalized}) { $score += .07; }
		if ($venue->{state_code}) { $score += .03; }
		if ($venue->{postal_clean}) { $score += .1; }
	}
	
	loadCommonAddressWords();
	$venue->{address_normalized} ||= normalizeAddress($venue->{address});
	my @words = split('-', $venue->{address_normalized});
	my $hasCommonWord;
	foreach my $word (@words) {
		if ($SitemasonPl::Normalize::commonAddressWords->{$word}) { $hasCommonWord = TRUE; }
	}
	
	if ($addressOnly) {
		if ($hasCommonWord) { return 1; }
	} else {
		if ($hasCommonWord) { $score += .8 }
		return $score;
	}
	
}

# $phrase = convertNumbers($normalized_phrase);
sub convertNumbers {
	my $phrase = shift || return '';
	loadNumbers();
	my @words = split('-', $phrase);
	
	my @newWords;
	my $total;
	my $subtotal;
	my $haveMil;
	my $haveThou;
	my $haveHund;
	my $haveTen;
	my $haveOne;
 	for (my $i = 0; $i < @words; $i++) {
		my $word = $words[$i];
		my $new = $SitemasonPl::Normalize::numbers->{$word};
 		
 		my $reset;
		if ($word =~ /^millions?/) {
			if ($haveThou || $haveMil) {
				# end && reset with million
				$reset = 1000000;
			} else {
				$subtotal ||= 1;
				$total += $subtotal * 1000000;
				$subtotal = 0;
			}
			$haveMil = TRUE;
			undef $haveThou; undef $haveHund; undef $haveTen; undef $haveOne;
		} elsif ($word =~ /^thousands?/) {
			if ($haveThou) {
				# end && reset with thousand
				$reset = 1000;
				undef $haveMil;
			} else {
				$subtotal ||= 1;
				$total += $subtotal * 1000;
				$subtotal = 0;
			}
			$haveThou = TRUE;
			undef $haveHund; undef $haveTen; undef $haveOne;
		} elsif ($word =~ /^hundreds?/) {
			if ($haveHund) {
				# end && reset with hundred
				$reset = 100;
				undef $haveMil; undef $haveThou;
			} else {
				$subtotal ||= 1;
				$subtotal = $subtotal * 100;
			}
			$haveHund = TRUE;
			undef $haveTen; undef $haveOne;
		} elsif ($new) {
			if (length($new->{n}) == 2) {
				if ($haveOne || $haveTen) {
					# end && reset with ten
					$reset = $new->{n};
					undef $haveMil; undef $haveThou; undef $haveHund;
				} else {
					$subtotal += $new->{n};
				}
				$haveTen = TRUE;
				undef $haveOne;
			} else {
				if ($haveOne) {
					# end && reset with one
					$reset = $new->{n};
					undef $haveMil; undef $haveThou; undef $haveHund; undef $haveTen;
				} else {
					$subtotal += $new->{n};
				}
				$haveOne = TRUE;
			}
 		}
 		
 		if (!$new || $reset || $new->{o}) {
 			if ($total + $subtotal) {
	 			push(@newWords, ($total + $subtotal) . $new->{o});
	 		}
 		}
 		if ($reset || $new->{o}) {
# 			print "  reset\n";
 			if (length($reset) >= 4) { $total = $reset; $subtotal = 0; }
 			else { $subtotal = $reset; $total = 0; }
 			undef $reset;
 		} elsif (isHashWithContent($new)) {
# 			print "  new ($total + $subtotal)\n";
 			
 		} else {
# 			print "  reset\n";
 			undef $haveMil; undef $haveThou; undef $haveHund; undef $haveTen; undef $haveOne;
 			$total = $subtotal = 0;
 			if ($word eq 'zero') { $word = '0'; }
 			push(@newWords, $word);
 		}
# 		print '= ' . join(' ', @newWords) . NL;
 	}
	if ($total + $subtotal) { push(@newWords, $total + $subtotal); }
#	print "$phrase\n   " . join(' ', @newWords) . "\n\n";
	return join('-', @newWords);
}

sub normalizeFull {
	my $input = shift || return;
	my $output;
	
	if (!ref($input)) { $output = _normalizeFull($input); }
	elsif (ref($input) eq 'SCALAR') { $output = _normalizeFull(${$input}); }
	elsif (ref($input) eq 'ARRAY') {
		$output = [];
		foreach my $value (@{$input}) {
			push(@{$output}, _normalizeFull($value));
		}
	} elsif (ref($input) eq 'HASH') {
		while (my($name, $value) = each(%{$input})) {
			$output->{$name} = _normalizeFull($value);
		}
	}
	
	return $output;
}

sub _normalizeFull {
	my $phrase = shift;
	$phrase = normalizeTitle($phrase);
	$phrase = convertNumbers($phrase);
	
	my @words = split('-', $phrase);
	
	my @newWords;
	for (my $i = 0; $i < @words; $i++) {
		my $word = $words[$i];
		$word = hyphenate($word);
		if (($i + 1) < @words) {
			my $compound = compound($word, $words[$i+1]);
			if ($compound) { $word = $compound; $i++; }
		}
		$word = unplural($word);
		$word = translate($word);
		push(@newWords, $word);
	}
	my $phrase = join('-', @newWords);
	return $phrase;
}

sub normalizeAddress {
	my $input = shift || return;
	my $output;
	
	if (!ref($input)) { $output = _normalizeAddress($input); }
	elsif (ref($input) eq 'SCALAR') { $output = _normalizeAddress(${$input}); }
	elsif (ref($input) eq 'ARRAY') {
		$output = [];
		foreach my $value (@{$input}) {
			push(@{$output}, _normalizeAddress($value));
		}
	} elsif (ref($input) eq 'HASH') {
		while (my($name, $value) = each(%{$input})) {
			$output->{$name} = _normalizeAddress($value);
		}
	}
	
	return $output;
}

sub _normalizeAddress {
	my $phrase = shift;
	$phrase = cleanAddress($phrase);
	$phrase = normalizeTitle($phrase);
	$phrase = convertNumbers($phrase);
	$phrase = _convertSaints($phrase);
	
	my @words = split('-', $phrase);
	
	my @newWords;
	for (my $i = 0; $i < @words; $i++) {
		my $word = $words[$i];
		$word = hyphenate($word);
		if (($i + 1) < @words) {
			my $compound = compound($word, $words[$i+1]);
			if ($compound) { $word = $compound; $i++; }
		}
		$word = translate($word);
		$word = unabbreviateAddress($word);
		push(@newWords, $word);
	}
	my $phrase = join('-', @newWords);
	return $phrase;
}

sub _convertSaints {
	my $phrase = shift || return;
	if ($phrase !~ /\bst\-([a-z]+)\b/) { return $phrase; }
	my $name = $1;
	loadSaints();
	if ($SitemasonPl::Normalize::saints->{$name}) {
		$phrase =~ s/\bst\-$name\b/saint-$name/g;
	} elsif ($name =~ /s$/) {
		my $nonpossessive = $name;
		$nonpossessive =~ s/s$//;
		if ($SitemasonPl::Normalize::saints->{$nonpossessive}) {
			$phrase =~ s/\bst\-$name\b/saint-$name/g;
		}
	} elsif ($phrase =~ /\bst\-st\-([a-z]+)\b/) {
		my $name = $1;
		if ($SitemasonPl::Normalize::saints->{$name}) {
			$phrase =~ s/\bst\-$name\b/saint-$name/g;
		} elsif ($name =~ /s$/) {
			my $nonpossessive = $name;
			$nonpossessive =~ s/s$//;
			if ($SitemasonPl::Normalize::saints->{$nonpossessive}) {
				$phrase =~ s/\bst\-$name\b/saint-$name/g;
			}
		}
	}
	return $phrase;
}

sub stripBoxFromAddress {
	my $input = shift || return;
	my $address = $input;
	if (isHash($input)) { $address = $input->{address}; }
	elsif (ref($input)) { return; }
	
# 	$address =~ s/\b(?:\s*[,-\\]\s*)?(?:r\.?\s*r\.?|h\.?\s*c\.?|rte?\.?|(?:rural\s+|business\s+)?route|r\.?\s*f\.?\s*d\.?|p\.?\s*m\.?\s*b\.?|subway)\s*#?\w+//ig;
	$address =~ s/\b(?:\s*[,-\\]\s*)?(?:r\.?\s*r\.?|h\.?\s*c\.?|(?:rural\s+|business\s+)route|r\.?\s*f\.?\s*d\.?|p\.?\s*m\.?\s*b\.?|subway)\s*#?\w+//ig;
	$address =~ s/\b(?:p\.?\s*o\.?\s*|campus\s+|post\s+office\s+)?box\s*#?\d[\w-]*//ig;
	$address =~ s/\b(?:p\.?o\.?\s*|campus\s+|post\s+office\s+)box\s+\w[\w-]*//ig;
	$address =~ s/\b(?:p\.?o\.?\s*|campus\s+|post\s+office\s+)box//ig;
	$address =~ s/(?:^\s*[,\-\/]|[,\-\/]\s*$)//g;
	$address =~ s/(?:^\s+|\s+$)//g;
	if (isHash($input)) { $input->{address} = $address; return $input; }
	return $address;
}

sub cleanAddress {
	my $address = shift || return;
	my $debug;
	$debug && print STDERR "original:   $address\n";
	$address = stripOutside($address, 'colon');
	$debug && print STDERR "strip 1:    $address\n";
	
	# Directions
	$address =~ s/((?:\&\s+|\band\s+)?(?:for|get|to)\s+(?:address|directions|info|location|reservations)|\bto\s+r\.?s\.?v\.?p\.?|r\.?s\.?v\.?p\.?\s+to)//ig;
	$debug && print STDERR "directions: $address\n";
	# URLs
	$address =~ s/(?:(?:\bat|\band|\bor|\bin|\bis|\bto|\-+)\s+)?https?:\/\/(?:[a-z0-9][a-z0-9-]{0,62}\.)*([a-z0-9][a-z0-9-]{0,62}\.[a-z]{2,})\.?(?:\/\S*)?//ig;
	$debug && print STDERR "urls:       $address\n";
	# Email
	$address =~ s/(?:(?:\bat|\band|\bor|\bin|\bis|\bto|\-+)\s+)?(?:e\-?mail\s+)?[a-z0-9!#$%&'*+\/=?^_`{|}~-]+(?:\.[a-z0-9!#$%&'*+\/=?^_`{|}~-]+)*\@(?:[a-z0-9-]{1,63}\.)*[a-z0-9-]{1,63}\.([a-z]{2,})\b//ig;
	$debug && print STDERR "email:      $address\n";
	# Phone numbers
	$address =~ s/(?:(?:\bat|\band|\bor|\bin|\bis|\bto|\-+)\s+)?(?<!\d)(?:\+?\d{1,2}[ -])?(?:\(\d{3}\)|\d{3})[ .-]?\d{3}[ .-]?\d{4}(?!\d)//ig;
	$debug && print STDERR "phone:      $address\n";
	# Dates
	$address =~ s/(?:(?:\bat|\band|\bor|\bin|\bis|\bto|\-+)\s+)?(?:(?:sun|mon|tue|wed|thur?|fri|sat)[,.]?\s+)?(?:jan|feb|mar|apr|may|june?|july?|aug|sept?|oct|nov|dec)\.?\s+\d+(?:st|rd|th)?[\s,.-]+(?:\d{4})?//ig;
	$debug && print STDERR "dates:      $address\n";
	# m/d/y Dates
	$address =~ s/(?:(?:\bat|\band|\bor|\bin|\bis|\bto|\-+)\s+)?(?<!\d)(?:1[012]|[1-9])\/(?:0[1-9]|[12]\d|3[01]|[1-9])\/(?:\d{4}|\d\d)\b//ig;
	$debug && print STDERR "dates 2:    $address\n";
	# Times
	$address =~ s/(?:(?:\bat|\band|\bor|\bin|\bis|\bto|\-+)\s+)?(?<!\d)(?:(?:2[0-3]|1?[0-9]):[0-5]\d(?:\s*[ap]\.?m\b\.?)?|(?:2[0-3]|1?[0-9])(?::[0-5]\d)?\s*[ap]\.?m\b\.?)//ig;
	$debug && print STDERR "times:      $address\n";
	# Prepositional phrase
	if ($address !~ /, in/i) {
		$address =~ s/(?:(?:entrance|located|parking)\s+)?(?:\bat|\bin|\bto)\s+.*//i;
	}
	$debug && print STDERR "phrases:    $address\n";
	$address = stripOutside($address, 'colon');
	$debug && print STDERR "strip 2:    $address\n";
	
	# Strip content around a colon
	$address =~ s/^.*? (?:address|location|office):\s*//ig;
	if ($address =~ /^\d+\s/) { $address =~ s/\s*:.*//; }
	else { $address =~ s/.*?:\s*//; }
	$debug && print STDERR "colon:      $address\n";
	
	# Strip PO Boxes
	$address = stripBoxFromAddress($address);
	$debug && print STDERR "strip box:  $address\n";
	$address = stripOutside($address, 'period');
	$debug && print STDERR "strip 3:    $address\n";
	
	# Strip c/o
	$address =~ s/,\s*c\/o .*?$//i;
	$debug && print STDERR "strip c/o:  $address\n";
	$address = stripOutside($address, 'period');
	$debug && print STDERR "strip 4:    $address\n\n";
	
	return $address;
}



sub normalizeCity {
	my $phrase = shift;
	$phrase = normalizeTitle($phrase);
	
	my @words = split('-', $phrase);
	my @newWords;
	for (my $i = 0; $i < @words; $i++) {
		my $word = $words[$i];
		if ($word eq 'st') { $word = 'saint'; }
		else { $word = unabbreviateAddress($word); }
		push(@newWords, $word);
	}
	my $phrase = join('-', @newWords);
	
	# unplural
	$phrase =~ s/([bcdfghjklmnpqrtvwxz])s\b/$1/g;
	
	# more
	$phrase =~ s/\bisles?\b/island/g;
	return $phrase;
}

sub areSimilar {
	my $phrase1 = shift;
	my $phrase2 = shift;
	if (normalizeFull($phrase1) eq normalizeFull($phrase2)) { return TRUE; }
}

sub getTimeZone {
	my $tz = shift || return;
	loadTimeZones();
	my $norm = normalize($tz);
	return $SitemasonPl::Normalize::timeZones->{$norm};
}

sub loadTimeZones {
	if (!isHash($SitemasonPl::Normalize::timeZones)) {
		my $names = DateTime::TimeZone->all_names;
		foreach my $name (@{$names}) {
			my $norm = normalize($name);
			$SitemasonPl::Normalize::timeZones->{$norm} = $name;
		}
		my $links = DateTime::TimeZone->links;
		while (my($link, $name) = each(%{$links})) {
			my $norm = normalize($link);
			$SitemasonPl::Normalize::timeZones->{$norm} = $name;
		}
	}
}

# Could add niners, etc.
sub loadNumbers {
	if (!isHash($SitemasonPl::Normalize::numbers)) {
		$SitemasonPl::Normalize::numbers = {
			one => { n => '1' },
			two => { n => '2' },
			three => { n => '3' },
			four => { n => '4' },
			five => { n => '5' },
			six => { n => '6' },
			seven => { n => '7' },
			eight => { n => '8' },
			nine => { n => '9' },
			ten => { n => '10' },
			eleven => { n => '11' },
			twelve => { n => '12' },
			thirteen => { n => '13' },
			fourteen => { n => '14' },
			fiveteen => { n => '15' },
			sixteen => { n => '16' },
			seventeen => { n => '17' },
			eighteen => { n => '18' },
			nineteen => { n => '19' },
			twenty => { n => '20' },
			thirty => { n => '30' },
			forty => { n => '40' },
			fourty => { n => '40' },
			fifty => { n => '50' },
			sixty => { n => '60' },
			seventy => { n => '70' },
			eighty => { n => '80' },
			ninety => { n => '90' },
			hundred => { n => '100' },
			thousand => { n => '1000' },
			million => { n => '1000000' },
			ones => { n => '1' },
			twos => { n => '2' },
			threes => { n => '3' },
			fours => { n => '4' },
			fives => { n => '5' },
			sixes => { n => '6' },
			sevens => { n => '7' },
			eights => { n => '8' },
			nines => { n => '9' },
			tens => { n => '10' },
			elevens => { n => '11' },
			twelves => { n => '12' },
			thirteens => { n => '13' },
			fourteens => { n => '14' },
			fiveteens => { n => '15' },
			sixteens => { n => '16' },
			seventeens => { n => '17' },
			eighteens => { n => '18' },
			nineteens => { n => '19' },
			twenties => { n => '20' },
			thirties => { n => '30' },
			forties => { n => '40' },
			fourties => { n => '40' },
			fifties => { n => '50' },
			sixties => { n => '60' },
			seventies => { n => '70' },
			eighties => { n => '80' },
			nineties => { n => '90' },
			hundreds => { n => '100' },
			thousands => { n => '1000' },
			millions => { n => '1000000' },
			first => { n => '1', o => 'st' },
			second => { n => '2', o => 'nd' },
			third => { n => '3', o => 'rd' },
			fourth => { n => '4', o => 'th' },
			fifth => { n => '5', o => 'th' },
			fiver => { n => '5', o => 'er' },
			fivers => { n => '5', o => 'ers' },
			sixth => { n => '6', o => 'th' },
			sixer => { n => '6', o => 'er' },
			sixers => { n => '6', o => 'ers' },
			seventh => { n => '7', o => 'th' },
			eighth => { n => '8', o => 'th' },
			ninth => { n => '9', o => 'th' },
			niner => { n => '9', o => 'er' },
			niners => { n => '9', o => 'ers' },
			tenth => { n => '10', o => 'th' },
			eleventh => { n => '11', o => 'th' },
			twelveth => { n => '12', o => 'th' },
			thirteenth => { n => '13', o => 'th' },
			fourteenth => { n => '14', o => 'th' },
			fiveteenth => { n => '15', o => 'th' },
			sixteenth => { n => '16', o => 'th' },
			seventeenth => { n => '17', o => 'th' },
			eighteenth => { n => '18', o => 'th' },
			nineteenth => { n => '19', o => 'th' },
			twentieth => { n => '20', o => 'th' },
			thirtieth => { n => '30', o => 'th' },
			fortieth => { n => '40', o => 'th' },
			fourtieth => { n => '40', o => 'th' },
			fiftieth => { n => '50', o => 'th' },
			sixtieth => { n => '60', o => 'th' },
			seventieth => { n => '70', o => 'th' },
			eightieth => { n => '80', o => 'th' },
			ninetieth => { n => '90', o => 'th' },
			hundredth => { n => '100', o => 'th' },
			thousandth => { n => '1000', o => 'th' },
			millionth => { n => '1000000', o => 'th' }
		};
	}
}

sub loadHyphenated {
	if (!isHash($SitemasonPl::Normalize::hyphenated)) {
		$SitemasonPl::Normalize::hyphenated = {
			ablebodied => 'able-bodied',
			absentminded => 'absent-minded',
			adlib => 'ad-lib',
			afterall => 'after-all',
			cashflow => 'cash-flow',
			checkin => 'check-in',
			childcare => 'child-care',
			cleancut => 'clean-cut',
			clearinghouse => 'clearing-house',
			closeup => 'close-up',
			coursework => 'course-work',
			emptyhanded => 'empty-handed',
			everytime => 'every-time',
			factfinding => 'fact-finding',
			factsheet => 'fact-sheet',
			farflung => 'far-flung',
			faroff => 'far-off',
			followthrough => 'follow-through',
			followup => 'follow-up',
			foodshelf => 'food-shelf',
			frameup => 'frame-up',
			frontrunner => 'front-runner',
			gettogether => 'get-together',
			gettough => 'get-tough',
			grassroots => 'grass-roots',
			groundwater => 'ground-water',
			halfmast => 'half-mast',
			halfstaff => 'half-staff',
			handpicked => 'hand-picked',
			hankypanky => 'hanky-panky',
			hardcore => 'hard-core',
			helpdesk => 'help-desk',
			hifi => 'hi-fi',
			hightech => 'high-tech',
			hohum => 'ho-hum',
			hushhush => 'hush-hush',
			indepth => 'in-depth',
			inlaw => 'in-law',
			knowhow => 'know-how',
			lifesize => 'life-size',
			lifespan => 'life-span',
			mindblowing => 'mind-blowing',
			mindboggling => 'mind-boggling',
			mindframe => 'mind-frame',
			moreso => 'more-so',
			narrowminded => 'narrow-minded',
			nittygritty => 'nitty-gritty',
			onsite => 'on-site',
			onesided => 'one-sided',
			paperflow => 'paper-flow',
			passerby => 'passer-by',
			pellmell => 'pell-mell',
			poohpooh => 'pooh-pooh',
			proforma => 'pro-forma',
			prorata => 'pro-rata',
			reelect => 're-elect',
			reelection => 're-election',
			redhaired => 'red-haired',
			redhot => 'red-hot',
			rolypoly => 'roly-poly',
			schoolday => 'school-day',
			schoolyear => 'school-year',
			secondrate => 'second-rate',
			selfservice => 'self-service',
			shrinkwrap => 'shrink-wrap',
			signin => 'sign-in',
			signon => 'sign-on',
			softspoken => 'soft-spoken',
			startup => 'start-up',
			straightlaced => 'straight-laced',
			strongarm => 'strong-arm',
			strongwilled => 'strong-willed',
			timeconsuming => 'time-consuming',
			timeframe => 'time-frame',
			timeline => 'time-line',
			timesaver => 'time-saver',
			touchpoint => 'touch-point',
			voicemail => 'voice-mail',
			voiceover => 'voice-over',
			votegetter => 'vote-getter',
			waitingroom => 'waiting-room',
			walkthrough => 'walk-through',
			warmup => 'warm-up',
			weakkneed => 'weak-kneed',
			wellbeing => 'well-being',
			wheelerdealer => 'wheeler-dealer',
			wordprocessing => 'word-processing',
			workrelease => 'work-release',
			wornout => 'worn-out',
			writeout => 'write-out',
			yearend => 'year-end',
		};
	}
}

sub loadCompounds {
	if (!isHash($SitemasonPl::Normalize::compounds)) {
		$SitemasonPl::Normalize::compounds = {
			'after-thought' => 'afterthought',
			'any-time' => 'anytime',
			'any-where' => 'anywhere',
			'awe-struck' => 'awestruck',
			'back-up' => 'backup',
			'back-yard' => 'backyard',
			'before-hand' => 'beforehand',
			'break-down' => 'breakdown',
			'breath-taking' => 'breathtaking',
			'build-up' => 'buildup',
			'burn-out' => 'burnout',
			'by-product' => 'byproduct',
			'can-not' => 'cannot',
			'care-giver' => 'caregiver',
			'carry-over' => 'carryover',
			'check-out' => 'checkout',
			'church-goer' => 'churchgoer',
			'city-wide' => 'citywide',
			'clean-up' => 'cleanup',
			'color-blind' => 'colorblind',
			'co-operative' => 'cooperative',
			'copy-edit' => 'copyedit',
			'country-side' => 'countryside',
			'co-worker' => 'coworker',
			'bank-card' => 'bankcard',
			'data-base' => 'database',
			'day-care' => 'daycare',
			'day-long' => 'daylong',
			'easy-going' => 'easygoing',
			'et-cetera' => 'etc',
			'extra-curricular' => 'extracurricular',
			'fall-off' => 'falloff',
			'free-lance' => 'freelance',
			'front-line' => 'frontline',
			'fund-raiser' => 'fundraiser',
			'fund-raising' => 'fundraising',
			'ghost-write' => 'ghostwrite',
			'good-will' => 'goodwill',
			'grown-up' => 'grownup',
			'health-care' => 'healthcare',
			'hold-up' => 'holdup',
			'home-owner' => 'homeowner',
			'hour-long' => 'hourlong',
			'kick-off' => 'kickoff',
			'life-style' => 'lifestyle',
			'make-up' => 'makeup',
			'market-place' => 'marketplace',
			'mean-time' => 'meantime',
			'month-long' => 'monthlong',
			'nation-wide' => 'nationwide',
			'never-the-less' => 'nevertheless',
			'non-compliance' => 'noncompliance',
			'non-conforming' => 'nonconforming',
			'non-conformity' => 'nonconformity',
			'none-the-less' => 'nonetheless',
			'non-profit' => 'nonprofit',
			'not-withstanding' => 'notwithstanding',
			'no-where' => 'nowhere',
			'office-holder' => 'officeholder',
			'on-board' => 'onboard',
			'on-going' => 'ongoing',
			'on-line' => 'online',
			'over-exposure' => 'overexposure',
			'over-generalization' => 'overgeneralization',
			'over-generalize' => 'overgeneralize',
			'paper-work' => 'paperwork',
			'per-cent' => 'percent',
			'policy-maker' => 'policymaker',
			'post-script' => 'postscript',
			'pre-empt' => 'preempt',
			'pre-emptive' => 'preemptive',
			'print-out' => 'printout',
			'pro-active' => 'proactive',
			'proof-read' => 'proofread',
			'pot-hole' => 'pothole',
			'red-headed' => 'redheaded',
			'roll-out' => 'rollout',
			'school-mate' => 'schoolmate',
			'school-room' => 'schoolroom',
			'school-teacher' => 'schoolteacher',
			'school-work' => 'schoolwork',
			'school-yard' => 'schoolyard',
			'some-where' => 'somewhere',
			'spread-sheet' => 'spreadsheet',
			'spring-time' => 'springtime',
			'state-wide' => 'statewide',
			'stock-holder' => 'stockholder',
			'stock-room' => 'stockroom',
			'story-teller' => 'storyteller',
			'summer-time' => 'summertime',
			'table-cloth' => 'tablecloth',
			'take-out' => 'takeout',
			'there-of' => 'thereof',
			'time-saving' => 'timesaving',
			'toss-up' => 'tossup',
			'turn-around' => 'turnaround',
			'wait-person' => 'waitperson',
			'web-page' => 'webpage',
			'web-site' => 'website',
			'week-day' => 'weekday',
			'week-end' => 'weekend',
			'week-long' => 'weeklong',
			'white-out' => 'whiteout',
			'winter-time' => 'wintertime',
			'work-bench' => 'workbench',
			'work-day' => 'workday',
			'work-flow' => 'workflow',
			'work-force' => 'workforce',
			'work-group' => 'workgroup',
			'work-load' => 'workload',
			'work-out' => 'workout',
			'work-place' => 'workplace',
			'work-room' => 'workroom',
			'work-sheet' => 'worksheet',
			'work-station' => 'workstation',
			'work-table' => 'worktable',
			'work-week' => 'workweek',
			'work-woman' => 'workwoman',
			'wrong-doing' => 'wrongdoing',
			'year-long' => 'yearlong'
		};
	}
}

sub loadTranslations {
	if (!isHash($SitemasonPl::Normalize::translations)) {
		$SitemasonPl::Normalize::translations = {
			january		=> 'jan',
			february	=> 'feb',
			febuary		=> 'feb',
			march		=> 'mar',
			april		=> 'apr',
			june		=> 'jun',
			july		=> 'jul',
			august		=> 'aug',
			september	=> 'sep',
			sept		=> 'sep',
			october		=> 'oct',
			november	=> 'nov',
			december	=> 'dec',
			
			barbecue		=> 'bbq',
			barbeque		=> 'bbq',
			barbie			=> 'bbq',
			cooperative		=> 'co-op',
			cmnty			=> 'community',
			ctr				=> 'center',
			incorporated	=> 'inc',
			intl			=> 'international',
			mount			=> 'mt',
			ounce			=> 'oz',
			ounces			=> 'oz',
			rstrnt			=> 'restaurant',
			
			versus			=> 'vs',
			etcetera		=> 'etc',
			
			aeroplane => 'airplane',
			aesthetic => 'esthetic',
			aestheticly => 'estheticly',
			ageing => 'aging',
			aluminium => 'aluminum',
			amoeba => 'ameba',
			anaemia => 'anemia',
			anaesthesia => 'anesthesia',
			analyse => 'analyze',
			analysed => 'analyzed',
			analyser => 'analyzer',
			analysing => 'analyzing',
			analogue => 'analog',
			annexe => 'annex',
			apologise => 'apologize',
			apologised => 'apologized',
			apologising => 'apologizing',
			archaeology => 'archeology',
			archaeologist => 'archeologist',
			armour => 'armor',
			arse => 'ass',
			artefact => 'artifact',
			authorise => 'authorize',
			behaviour => 'behavior',
			broncho => 'bronco',
			caesium => 'cesium',
			chamomile => 'camomile',
			cancelled => 'canceled',
			cancelling => 'canceling',
			carburettor => 'carburetor',
			catalogue => 'catalog',
			centre => 'center',
			cheque => 'check',
			chequer => 'checker',
			cypher => 'cipher',
			civilise => 'civilize',
			civilisation => 'civilization',
			civilised => 'civilized',
			civilising => 'civilizing',
			colonise => 'colonize',
			colonisation => 'colonization',
			colonised => 'colonized',
			colonising => 'colonizing',
			colour => 'color',
			cosy => 'cozy',
			counsellor => 'counselor',
			counselling => 'counseling',
			defence => 'defense',
			demagogue => 'demagog',
			dialled => 'dialed',
			dialler => 'dialer',
			dialling => 'dialing',
			dialogue => 'dialog',
			diarrhoea => 'diarrhea',
			disc => 'disk',
			distention => 'distension',
			distil => 'distill',
			doughnut => 'donut',
			draught => 'draft',
			dreamt => 'dreamed',
			emphasise => 'emphasize',
			emphasised => 'emphasized',
			emphasising => 'emphasizing',
			encyclopaedia => 'encyclopedia',
			oenology => 'enology',
			enrolment => 'enrollment',
			equalling => 'equaling',
			oesophagus => 'esophagus',
			oestrogen => 'estrogen',
			oedema => 'edema',
			endeavour => 'endeavor',
			favourite => 'favorite',
			faeces => 'feces',
			fibre => 'fiber',
			foetid => 'fetid',
			foetus => 'fetus',
			flautist => 'flutist',
			flavour => 'flavor',
			flavoured => 'flavored',
			flavouring => 'flavoring',
			fulfil => 'fulfill',
			furore => 'furor',
			fuelling => 'fueling',
			gaol => 'jail',
			generalise => 'generalize',
			generalisation => 'generalization',
			glycerine => 'glycerin',
			grey => 'gray',
			gynaecology => 'gynecology',
			gynaecologist => 'gynecologist',
			haemophilia => 'hemophilia',
			haematology => 'hematology',
			haematologist => 'hematologist',
			haem => 'heme',
			harbour => 'harbor',
			harmonise => 'harmonize',
			harmonisation => 'harmonization',
			harmonised => 'harmonized',
			harmonising => 'harmonizing',
			homologue => 'homolog',
			honour => 'honor',
			honoured => 'honored',
			honouring => 'honoring',
			honourable => 'honorable',
			honourably => 'honorably',
			honouree => 'honoree',
			humour => 'humor',
			humoured => 'humored',
			humouring => 'humoring',
			instalment => 'installment',
			italicise => 'italicize',
			italicised => 'italicized',
			italicising => 'italicizing',
			jewellery => 'jewelry',
			judgement => 'judgment',
			kerb => 'curb',
			kilometre => 'kilometer',
			labour => 'labor',
			laboured => 'labored',
			labouring => 'laboring',
			leapt => 'leaped',
			learnt => 'learned',
			leukaemia => 'leukemia',
			licence => 'license',
			licenced => 'licensed',
			licencing => 'licensing',
			liquorice => 'licorice',
			litre => 'liter',
			manoeuvre => 'maneuver',
			marvellous => 'marvelous',
			marvellously => 'marvelously',
			mediaeval => 'medieval',
			metre => 'meter',
			modelling => 'modeling',
			mould => 'mold',
			moulded => 'molded',
			moulding => 'molding',
			mollusc => 'mollusk',
			moult => 'molt',
			moulted => 'molted',
			moulting => 'molting',
			mum => 'mom',
			monologue => 'monolog',
			moustache => 'mustache',
			moisturised => 'moisturized',
			moisturiser => 'moisturizer',
			moisturising => 'moisturizing',
			neighbour => 'neighbor',
			neighboured => 'neighbored',
			neighbouring => 'neighboring',
			neighbourly => 'neighborly',
			neighbourhood => 'neighborhood',
			oenology => 'enology',
			oesophagus => 'esophagus',
			oestrogen => 'estrogen',
			odour => 'odor',
			offence => 'offense',
			omelette => 'omelet',
			organise => 'organize',
			organised => 'organized',
			organising => 'organizing',
			organisation => 'organization',
			orthologue => 'ortholog',
			orthopaedic => 'orthopedic',
			paediatric => 'pediatric',
			paedophile => 'pedophile',
			pyjamas => 'pajamas',
			paralyse => 'paralyze',
			paralysed => 'paralyzed',
			paralysing => 'paralyzing',
			parlour => 'parlor',
			pedagogue => 'pedagog',
			plough => 'plow',
			practise => 'practice',
			practised => 'practiced',
			practising => 'practicing',
			pretence => 'pretense',
			prise => 'prize',
			programme => 'program',
			quarrelled => 'quarreled',
			quarrelling => 'quarreling',
			realise => 'realize',
			realised => 'realized',
			realising => 'realizing',
			realisation => 'realization',
			rigour => 'rigor',
			routeing => 'routing',
			saviour => 'savior',
			savoury => 'savory',
			sceptic => 'skeptic',
			scepticly => 'skepticly',
			shew => 'show',
			signalling => 'signaling',
			skilful => 'skillful',
			speciality => 'specialty',
			spelt => 'spelled',
			spoilt => 'spoiled',
			storey => 'story',
			sulphur => 'sulfur',
			shoppe => 'shop',
			theatre => 'theater',
			tyre => 'tire',
			tranquillity => 'tranquility',
			travelled => 'traveled',
			traveller => 'traveler',
			travelling => 'traveling',
			tumour => 'tumor',
			urbanisation => 'urbanization',
			valour => 'valor',
			vyce => 'vise',
			victual => 'vittle',
			vigour => 'vigor',
			vigourous => 'vigorous',
			whisky => 'whiskey',
			woollen => 'woolen',
			yoghurt => 'yogurt',
		};
	}
}

sub loadSynonyms {
	isArray($SitemasonPl::Normalize::synonyms) && return;
	$SitemasonPl::Normalize::synonyms = [
		['arena', 'amphitheater', 'auditorium', 'ballpark', 'center', 'coliseum', 'community-center', 'concert-hall', 'exhibition-hall', 'field', 'hall', 'park', 'sportsplex', 'stadium'],
		['racetrack', 'race-track', 'racecourse', 'race-course', 'raceway', 'speedway', 'velodrome'],
		['theater', 'amphitheater', 'auditorium', 'cabaret', 'concert-hall', 'exhibition-hall', 'hall', 'playhouse'],
		['cinema', 'drive-in-theater', 'drive-in', 'movie-theater', 'multiplex', 'movie-house', 'nickelodeon', 'theater'],
		['restaurant', 'bar', 'bistro', 'cabaret', 'cafe', 'caffe', 'caterer', 'coffee-shop', 'gourmet', 'grill', 'house', 'kitchen', 'pizzeria', 'taqueria'],
		['japanese', 'cafe', 'fugu', 'grill', 'hibachi', 'japan', 'kitchen', 'noodle', 'okinawa', 'okinawan', 'restaurant', 'saki', 'steakhouse', 'teriyaki', 'ramen', 'yakitori', 'soba', 'izakaya', 'tonkatsu', 'sushi', 'sashimi', 'tempura', 'shabu-shabu', 'takoyaki', 'kare-raisu', 'udon', 'okonomiyaki', 'monjayaki', 'gyuudon', 'kushiage', 'champon', 'teishoku', 'hambagu', 'kaiseki', 'yakiniku', 'kaisendon', 'tendon', 'motsunabe', 'teppanyaki', 'shojin', 'youshoku', 'tofu', 'yuba', 'ryouri', 'houtou', 'sukiyaki'],
		['chinese', 'cafe', 'gourmet', 'hot-pot', 'house', 'kitchen', 'noodle', 'restaurant', 'anhui', 'asia', 'cantonese', 'china', 'fujian', 'hunan', 'jiangsu', 'mongolian', 'shandong', 'shanghai', 'sichuan', 'szechuan', 'tibetan', 'xinjiang', 'yunnan', 'zhejiang'],
		['store', 'shop', 'shoppe']
	];
}

sub loadCommonWords {
	isHash($SitemasonPl::Normalize::commonWords) && return;
	loadSynonyms();
	$SitemasonPl::Normalize::commonWords = {
		and		=> TRUE,
		as		=> TRUE,
		at		=> TRUE,
		but		=> TRUE,
		but		=> TRUE,
		by		=> TRUE,
		for		=> TRUE,
		for		=> TRUE,
		in		=> TRUE,
		into	=> TRUE,
		nor		=> TRUE,
		of		=> TRUE,
		off		=> TRUE,
		on		=> TRUE,
		or		=> TRUE,
		out		=> TRUE,
		per		=> TRUE,
		so		=> TRUE,
		to		=> TRUE,
		yet		=> TRUE
	};
	foreach my $set (@{$SitemasonPl::Normalize::synonyms}) {
		foreach my $word (@{$set}) {
			$SitemasonPl::Normalize::commonWords->{$word} = TRUE;
		}
	}
}

sub loadCommonAddressWords {
	isHash($SitemasonPl::Normalize::commonAddressWords) && return;
	loadAddressAbbreviations();
	$SitemasonPl::Normalize::commonAddressWords = {};
	while (my($abbr, $word) = each(%{$SitemasonPl::Normalize::addressAbbreviations})) {
		$SitemasonPl::Normalize::commonAddressWords->{$word} = TRUE;
	}
}

sub loadAddressAbbreviations {
	if (!isHash($SitemasonPl::Normalize::addressAbbreviations)) {
		$SitemasonPl::Normalize::addressAbbreviations = {
			's'		=> 'south',
			'sw'	=> 'southwest',
			'se'	=> 'southeast',
			'n'		=> 'north',
			'nw'	=> 'northwest',
			'ne'	=> 'northeast',
			'w'		=> 'west',
			'e'		=> 'east',
			'allee' => 'alley',
			'alleys' => 'alley',
			'ally' => 'alley',
			'aly' => 'alley',
			'anex' => 'annex',
			'annexes' => 'annex',
			'anx' => 'annex',
			'apartments' => 'apartment',
			'apt' => 'apartment',
			'arc' => 'arcade',
			'arcades' => 'arcade',
			'av' => 'avenue',
			'ave' => 'avenue',
			'aven' => 'avenue',
			'avenu' => 'avenue',
			'avenues' => 'avenue',
			'avn' => 'avenue',
			'avnue' => 'avenue',
			'basements' => 'basement',
			'bsmt' => 'basement',
			'bayoos' => 'bayoo',
			'bayou' => 'bayoo',
			'bayous' => 'bayoo',
			'byu' => 'bayoo',
			'bch' => 'beach',
			'beaches' => 'beach',
			'bends' => 'bend',
			'bnd' => 'bend',
			'blf' => 'bluff',
			'blfs' => 'bluff',
			'bluf' => 'bluff',
			'bluffs' => 'bluff',
			'bot' => 'bottom',
			'bottm' => 'bottom',
			'bottoms' => 'bottom',
			'btm' => 'bottom',
			'blvd' => 'boulevard',
			'boul' => 'boulevard',
			'boulevards' => 'boulevard',
			'boulv' => 'boulevard',
			'br' => 'branch',
			'branches' => 'branch',
			'brnch' => 'branch',
			'brdge' => 'bridge',
			'brg' => 'bridge',
			'bridges' => 'bridge',
			'bdwy' => 'broadway',
			'bway' => 'broadway',
			'brk' => 'brook',
			'brks' => 'brook',
			'brooks' => 'brook',
			'bldg' => 'building',
			'buildings' => 'building',
			'bg' => 'burg',
			'bgs' => 'burg',
			'burgs' => 'burg',
			'byp' => 'bypass',
			'bypa' => 'bypass',
			'bypas' => 'bypass',
			'bypasses' => 'bypass',
			'byps' => 'bypass',
			'camps' => 'camp',
			'cmp' => 'camp',
			'cp' => 'camp',
			'canyn' => 'canyon',
			'canyons' => 'canyon',
			'cnyn' => 'canyon',
			'cyn' => 'canyon',
			'capes' => 'cape',
			'cpe' => 'cape',
			'causeways' => 'causeway',
			'causway' => 'causeway',
			'cswy' => 'causeway',
			'cen' => 'center',
			'cent' => 'center',
			'centers' => 'center',
			'centr' => 'center',
			'centre' => 'center',
			'cnter' => 'center',
			'cntr' => 'center',
			'ctr' => 'center',
			'ctrs' => 'center',
			'cir' => 'circle',
			'circ' => 'circle',
			'circl' => 'circle',
			'circles' => 'circle',
			'cirs' => 'circle',
			'crcl' => 'circle',
			'crcle' => 'circle',
			'clf' => 'cliff',
			'clfs' => 'cliff',
			'cliffs' => 'cliff',
			'clb' => 'club',
			'clubs' => 'club',
			'cmn' => 'common',
			'commons' => 'common',
			'cor' => 'corner',
			'corners' => 'corner',
			'cors' => 'corner',
			'courses' => 'course',
			'crse' => 'course',
			'courts' => 'court',
			'crt' => 'court',
			'ct' => 'court',
			'cts' => 'court',
			'coves' => 'cove',
			'cv' => 'cove',
			'cvs' => 'cove',
			'ck' => 'creek',
			'cr' => 'creek',
			'creeks' => 'creek',
			'crk' => 'creek',
			'crecent' => 'crescent',
			'crecents' => 'crescent',
			'cres' => 'crescent',
			'crescents' => 'crescent',
			'cresent' => 'crescent',
			'crscnt' => 'crescent',
			'crsent' => 'crescent',
			'crsnt' => 'crescent',
			'crests' => 'crest',
			'crst' => 'crest',
			'crossings' => 'crossing',
			'crssing' => 'crossing',
			'crssng' => 'crossing',
			'xing' => 'crossing',
			'xings' => 'crossing',
			'crossroads' => 'crossroad',
			'xrd' => 'crossroad',
			'xrds' => 'crossroad',
			'curv' => 'curve',
			'curves' => 'curve',
			'dales' => 'dale',
			'dl' => 'dale',
			'dams' => 'dam',
			'dm' => 'dam',
			'departments' => 'department',
			'dept' => 'department',
			'div' => 'divide',
			'divides' => 'divide',
			'dv' => 'divide',
			'dvd' => 'divide',
			'dr' => 'drive',
			'driv' => 'drive',
			'drives' => 'drive',
			'drs' => 'drive',
			'drv' => 'drive',
			'est' => 'estate',
			'estates' => 'estate',
			'ests' => 'estate',
			'exp' => 'expressway',
			'expr' => 'expressway',
			'express' => 'expressway',
			'expressways' => 'expressway',
			'expw' => 'expressway',
			'expy' => 'expressway',
			'ext' => 'extension',
			'extensions' => 'extension',
			'extn' => 'extension',
			'extnsn' => 'extension',
			'exts' => 'extension',
			'falls' => 'fall',
			'fls' => 'fall',
			'ferrys' => 'ferry',
			'frry' => 'ferry',
			'fry' => 'ferry',
			'fields' => 'field',
			'fld' => 'field',
			'flds' => 'field',
			'flats' => 'flat',
			'flt' => 'flat',
			'flts' => 'flat',
			'fl' => 'floor',
			'floors' => 'floor',
			'fords' => 'ford',
			'frd' => 'ford',
			'frds' => 'ford',
			'forests' => 'forest',
			'frst' => 'forest',
			'forg' => 'forge',
			'forges' => 'forge',
			'frg' => 'forge',
			'frgs' => 'forge',
			'forks' => 'fork',
			'frk' => 'fork',
			'frks' => 'fork',
			'forts' => 'fort',
			'frt' => 'fort',
			'ft' => 'fort',
			'freeways' => 'freeway',
			'freewy' => 'freeway',
			'frway' => 'freeway',
			'frwy' => 'freeway',
			'fwy' => 'freeway',
			'frnt' => 'front',
			'fronts' => 'front',
			'gardens' => 'garden',
			'gardn' => 'garden',
			'gdn' => 'garden',
			'gdns' => 'garden',
			'grden' => 'garden',
			'grdn' => 'garden',
			'grdns' => 'garden',
			'gateways' => 'gateway',
			'gatewy' => 'gateway',
			'gatway' => 'gateway',
			'gtway' => 'gateway',
			'gtwy' => 'gateway',
			'glens' => 'glen',
			'gln' => 'glen',
			'glns' => 'glen',
			'greens' => 'green',
			'grn' => 'green',
			'grns' => 'green',
			'grov' => 'grove',
			'groves' => 'grove',
			'grv' => 'grove',
			'grvs' => 'grove',
			'hangars' => 'hangar',
			'hngr' => 'hangar',
			'harb' => 'harbor',
			'harbors' => 'harbor',
			'harbr' => 'harbor',
			'hbr' => 'harbor',
			'hbrs' => 'harbor',
			'hrbor' => 'harbor',
			'havens' => 'haven',
			'havn' => 'haven',
			'hvn' => 'haven',
			'height' => 'heights',
			'hgts' => 'heights',
			'ht' => 'heights',
			'hts' => 'heights',
			'hghlnd' => 'highland',
			'hghlnds' => 'highlands',
			'highways' => 'highway',
			'highwy' => 'highway',
			'hiway' => 'highway',
			'hiwy' => 'highway',
			'hway' => 'highway',
			'hwy' => 'highway',
			'hills' => 'hill',
			'hl' => 'hill',
			'hls' => 'hill',
			'hllw' => 'hollow',
			'hollows' => 'hollow',
			'holw' => 'hollow',
			'holws' => 'hollow',
			'inlets' => 'inlet',
			'inlt' => 'inlet',
			'is' => 'island',
			'islands' => 'island',
			'islnd' => 'island',
			'islnds' => 'island',
			'iss' => 'island',
			'isles' => 'isle',
			'jct' => 'junction',
			'jction' => 'junction',
			'jctn' => 'junction',
			'jctns' => 'junction',
			'jcts' => 'junction',
			'junctions' => 'junction',
			'junctn' => 'junction',
			'juncton' => 'junction',
			'keys' => 'key',
			'ky' => 'key',
			'kys' => 'key',
			'knl' => 'knoll',
			'knls' => 'knoll',
			'knol' => 'knoll',
			'knolls' => 'knoll',
			'lakes' => 'lake',
			'lk' => 'lake',
			'lks' => 'lake',
			'landings' => 'landing',
			'lndg' => 'landing',
			'lndng' => 'landing',
			'la' => 'lane',
			'lanes' => 'lane',
			'ln' => 'lane',
			'lgt' => 'light',
			'lgts' => 'light',
			'lights' => 'light',
			'lf' => 'loaf',
			'loafs' => 'loaf',
			'loaves' => 'loaf',
			'lbby' => 'lobby',
			'lobbys' => 'lobby',
			'lck' => 'lock',
			'lcks' => 'lock',
			'locks' => 'lock',
			'ldg' => 'lodge',
			'ldge' => 'lodge',
			'lodg' => 'lodge',
			'lodges' => 'lodge',
			'loops' => 'loop',
			'lowers' => 'lower',
			'lowr' => 'lower',
			'manors' => 'manor',
			'mnr' => 'manor',
			'mnrs' => 'manor',
			'mdw' => 'meadow',
			'mdws' => 'meadow',
			'meadows' => 'meadow',
			'medows' => 'meadow',
			'mills' => 'mill',
			'ml' => 'mill',
			'mls' => 'mill',
			'missions' => 'mission',
			'missn' => 'mission',
			'msn' => 'mission',
			'mssn' => 'mission',
			'motorways' => 'motorway',
			'mtwy' => 'motorway',
			'mnt' => 'mount',
			'mounts' => 'mount',
			'mt' => 'mount',
			'mntain' => 'mountain',
			'mntn' => 'mountain',
			'mntns' => 'mountain',
			'mountains' => 'mountain',
			'mountin' => 'mountain',
			'mtin' => 'mountain',
			'mtn' => 'mountain',
			'mtns' => 'mountain',
			'nck' => 'neck',
			'necks' => 'neck',
			'ofc' => 'office',
			'offices' => 'office',
			'orch' => 'orchard',
			'orchards' => 'orchard',
			'orchrd' => 'orchard',
			'ovals' => 'oval',
			'ovl' => 'oval',
			'opas' => 'overpass',
			'overpasses' => 'overpass',
			'parks' => 'park',
			'pk' => 'park',
			'prk' => 'park',
			'parkways' => 'parkway',
			'parkwy' => 'parkway',
			'pkway' => 'parkway',
			'pkwy' => 'parkway',
			'pkwys' => 'parkway',
			'pky' => 'parkway',
			'passages' => 'passage',
			'psge' => 'passage',
			'paths' => 'path',
			'penthouses' => 'penthouse',
			'ph' => 'penthouse',
			'pikes' => 'pike',
			'pines' => 'pine',
			'pne' => 'pine',
			'pnes' => 'pine',
			'pl' => 'place',
			'places' => 'place',
			'plaines' => 'plain',
			'plains' => 'plain',
			'pln' => 'plain',
			'plns' => 'plain',
			'plazas' => 'plaza',
			'plz' => 'plaza',
			'plza' => 'plaza',
			'points' => 'point',
			'pt' => 'point',
			'pte' => 'point',
			'pts' => 'point',
			'ports' => 'port',
			'prt' => 'port',
			'prts' => 'port',
			'pr' => 'prairie',
			'prairies' => 'prairie',
			'prarie' => 'prairie',
			'prr' => 'prairie',
			'rad' => 'radial',
			'radials' => 'radial',
			'radiel' => 'radial',
			'radl' => 'radial',
			'ranches' => 'ranch',
			'ranchs' => 'ranch',
			'rnch' => 'ranch',
			'rnchs' => 'ranch',
			'rapids' => 'rapid',
			'rpd' => 'rapid',
			'rpds' => 'rapid',
			'rests' => 'rest',
			'rst' => 'rest',
			'rdg' => 'ridge',
			'rdge' => 'ridge',
			'rdgs' => 'ridge',
			'ridges' => 'ridge',
			'riv' => 'river',
			'rivers' => 'river',
			'rivr' => 'river',
			'rvr' => 'river',
			'rd' => 'road',
			'rds' => 'road',
			'roads' => 'road',
			'rm' => 'room',
			'rooms' => 'room',
			'routes' => 'route',
			'rte' => 'route',
			'shl' => 'shoal',
			'shls' => 'shoal',
			'shoals' => 'shoal',
			'shoar' => 'shore',
			'shoars' => 'shore',
			'shores' => 'shore',
			'shr' => 'shore',
			'shrs' => 'shore',
			'skwy' => 'skyway',
			'skyways' => 'skyway',
			'spaces' => 'space',
			'spc' => 'space',
			'spg' => 'spring',
			'spgs' => 'spring',
			'spng' => 'spring',
			'spngs' => 'spring',
			'springs' => 'spring',
			'sprng' => 'spring',
			'sprngs' => 'spring',
			'spurs' => 'spur',
			'sq' => 'square',
			'sqr' => 'square',
			'sqre' => 'square',
			'sqrs' => 'square',
			'sqs' => 'square',
			'squ' => 'square',
			'squares' => 'square',
			'sta' => 'station',
			'stations' => 'station',
			'statn' => 'station',
			'stn' => 'station',
			'stra' => 'stravenue',
			'strav' => 'stravenue',
			'strave' => 'stravenue',
			'straven' => 'stravenue',
			'stravenues' => 'stravenue',
			'stravn' => 'stravenue',
			'strvn' => 'stravenue',
			'strvnue' => 'stravenue',
			'streams' => 'stream',
			'streme' => 'stream',
			'strm' => 'stream',
			'st' => 'street',
			'str' => 'street',
			'streets' => 'street',
			'strt' => 'street',
			'sts' => 'street',
			'ste' => 'suite',
			'suites' => 'suite',
			'smt' => 'summit',
			'sumit' => 'summit',
			'sumitt' => 'summit',
			'summits' => 'summit',
			'ter' => 'terrace',
			'terr' => 'terrace',
			'terraces' => 'terrace',
			'throughways' => 'throughway',
			'trwy' => 'throughway',
			'twp' => 'township',
			'traces' => 'trace',
			'trce' => 'trace',
			'tracks' => 'track',
			'trak' => 'track',
			'trk' => 'track',
			'trks' => 'track',
			'trafficways' => 'trafficway',
			'trfy' => 'trafficway',
			'tr' => 'trail',
			'trails' => 'trail',
			'trl' => 'trail',
			'trls' => 'trail',
			'trailers' => 'trailer',
			'trlr' => 'trailer',
			'tunel' => 'tunnel',
			'tunl' => 'tunnel',
			'tunls' => 'tunnel',
			'tunnels' => 'tunnel',
			'tunnl' => 'tunnel',
			'tpk' => 'turnpike',
			'tpke' => 'turnpike',
			'trnpk' => 'turnpike',
			'trpk' => 'turnpike',
			'turnpikes' => 'turnpike',
			'turnpk' => 'turnpike',
			'underpasses' => 'underpass',
			'upas' => 'underpass',
			'un' => 'union',
			'unions' => 'union',
			'uns' => 'union',
			'uppers' => 'upper',
			'uppr' => 'upper',
			'valleys' => 'valley',
			'vally' => 'valley',
			'vlly' => 'valley',
			'vly' => 'valley',
			'vlys' => 'valley',
			'vdct' => 'viaduct',
			'via' => 'viaduct',
			'viadct' => 'viaduct',
			'viaducts' => 'viaduct',
			'views' => 'view',
			'vw' => 'view',
			'vws' => 'view',
			'vill' => 'village',
			'villag' => 'village',
			'villages' => 'village',
			'villg' => 'village',
			'villiage' => 'village',
			'vlg' => 'village',
			'vlgs' => 'village',
			'villes' => 'ville',
			'vl' => 'ville',
			'vis' => 'vista',
			'vist' => 'vista',
			'vistas' => 'vista',
			'vst' => 'vista',
			'vsta' => 'vista',
			'walks' => 'walk',
			'ways' => 'way',
			'wy' => 'way',
			'wells' => 'well',
			'wl' => 'well',
			'wls' => 'well'
		};
	}
}

# http://en.wikipedia.org/wiki/List_of_saints
sub loadSaints {
	if (!isHash($SitemasonPl::Normalize::saints)) {
		$SitemasonPl::Normalize::saints = {};
		my @saints = qw(
abadiu abakuh abamun abanoub abaskhayroun abban abbo abdas abel abib
abo abraam abraham abuna abundius acacius acca achilleus adalbert adalgar
adalgott adamo adelaide adelhelm adelin adeodatus adomnan adrian aethelberht afan
agapetus agapitus agatha agatho agnes aidan alban albans alberic alberto
albertus alcuin alda alexander alexandra alexei alexis alfred alice alipy
aloysius alphege alphonsa alypius amand amant ambrose ammon amphilochius anastasia
anastasius andre andrei andrew andrews andronicus angela anianus ann anna
anne anselm ansgar anthony antoine aphrodisius apollo apollonia apollos aprax
arnold arnulf athanasius augustine avilius avitus baldred barbatus barsanuphius basil
beatrix benedetta benedict berlinda bernadette bernard bernardino bernardo bernice birinus
bonaventure boniface bonifacius boris botolph brendan bridget brigid brioc bruno
budoc caesarius cajetan camillus candidus canute carantoc casimir catald catharine
catherine cedd celadion celestine cettin chad charbel charles christina christopher
chrysanthus ciaran clair claire clairsville clare claude claudus clement cleopatra
clodoald clotilde cloud colette columba columbanus comgall congar conrad constantine
cosmas cristobal croix cunigunde cuthbert cynllo cyriacus cyril cyrus dado
damian damien daniel danilo dasya david daydara declan demetrius demiana
dennis desiderius deusdedit dewi didier didymus dietrich dimitry dionysius dioscorus
doherty dominic donatus dorothea dorotheus douai drogo dunstan dymphna eanflaed
eanswythe edburga edith editha edmund edward edwin egbert eligius elisabeth
elizabeth elmo emeric emma emmelia emmeram enda engelbert erbin erentrude
ermengol ermenilda etheldreda eugene eulogius eumenes euphemia euphrosyne eustochia euthymius
eysteinn fachanan faro faustina faustus feichin felix ferdinand ferreol fiacre
fidelis filan finbarr florentina florian franca frances francesca francis francisville
francois frei frideswide fructuosus fulgentius gabriel gaetano gal gall gallicanus
gaspar gaudentius gelasius gelert gemma genesius genevieve george georges gerard
gerasimus gereon germain gerulfus ghislain gianna gilbert giovanni goar godehard
godric gonsalo gotthard gratus gregorio gregory grellan guinefort gunther hallvard
hedwig helen helena helens helier henry herman herve hilaire hilarius
hilda hildebrand hildegard hormisdas hubertus hugh hyacinth hyacintha ignace ignatius
igor illuminata inigoes innocencio innocent ioann irene isaac isabel isfrid
isidore ite ivo jacob jacobo jadwiga james jean jo joan
joaquina job joe john johnland johns johnsbury johnsville josaphat josemaria
joseph josephine josse jozef juan judoc julian juliana julie just
justin jutta kassia katharine kea kessog kevin king kinga kirill
konstantin ladislaus lambert landry laura laurent lawrence lazar leander leo
leodegar leon leonard leopold libory lidwina livinus lorcan lorenzo louis
louise louisville lucas lucie lucy ludolph luke lupus lutgardis machar
magdalen magdalene malachy malo marcellin marcouf margaret marguerite maria marianita
marie maries mark marks martin martins martinville martyr martyrs mary
marys matthew matthews maurice maurontius maximillian maximus meinrad methodius michael
michaels miguel milburga modwen moninne mother narcisa naum nazianz nectan
neot nicephorus nicholas nikola nikolai nil nilus nimattullah noel norbert
nothelm nuno odile odo olaf olga oliver onge opportuna oswald
osyth ouen paraskeva paris paschal patrick paul paulina paulinus pauls
pavel pedro peregrine pete peter peters petersburg petroc petrus philip
philothei photios pierre pio piran pius praejectus praetextatus pyr quinidius
quintian rabanus rafqa rainerius ralph raphael raymond regis remigius rene
richard rictrude rimbert rita robert roch roger rognvald romuald roque
rosa rosalia rose sabbas sadalberga saethryth salonius salvius samson sava
scholastica seaxburh seraphim seraphina sergei sergius severinus sharbel sigeberht silverius
simeon simon simons simplicius sophia sophronius stephen stephens stylianos swithun
symeon symmachus tarasios tathan tatiana tekle teresa theodore theodosius theophan
theophanes therese thomas thorlak tikhon turibius tydfil ubald ulrich urbicius
ursicinus ursmar ursula varghese varvara venantius veranus vergilius veronica vicelinus
vicente vietnamese vincent virginia vitalian vitalis vitonus vladimir vrain waningus
wenceslaus werburgh wiborada wilfrid willehad william willibrord wolfeius wolfgang wolfhelm
wulfram xavier xenia xenophon yaropolk yegor yrieix zachary zdislava zita
zofia zosimas zygmunt
		);
		foreach my $saint (@saints) {
			$SitemasonPl::Normalize::saints->{$saint} = TRUE;
		}
	}
}


=head1 CHANGES

  20140410 TJM - moved from scripts to Sitemason7
  20171109 TJM - v8.0 Moved to SitemasonPL open source project

=head1 AUTHOR

  Tim Moses <tim@moses.com>
  Sitemason Open Source <https://github.com/sitemason>

=cut

1;
