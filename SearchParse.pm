package SitemasonPl::SearchParse 8.0;

=head1 NAME

SitemasonPl::SearchParse

=head1 DESCRIPTION

SearchParse parses a single string into multiple search parameters.

=head1 METHODS

=cut

use v5.012;
use strict;
use SitemasonPl::Common;
use SitemasonPl::Debug;
use SitemasonPl::Database;
use SitemasonPl::Date;

use DateTime;


#=====================================================

=head2 B<new>

Creates and returns a calendar object. One of id or id_list are required.

 my $searchparse = SitemasonPl::SearchParse->new(
	options		=> {				# optional, by default all are on
		quotes	=> 1,	# parse quoted text as single what
		times	=> 1,	# parse common time words, like today for when
		dates	=> 1,	# parse common date formats for when
		time	=> 1	# parse common time formats for when
	}
	
	# pass original script's debug to share timing and logging
	debug		=> $debug
 );

=cut
#=====================================================
sub new {
	my ($class, %arg) = @_;
	$class || return;
	
	my $self = {
		options		=> $arg{options},
		time_zone	=> $arg{timeZone} || 'US/Central',
		log			=> {
			parsers	=> 0
		}
	};
	bless $self, $class;
	
	if ($arg{debug}) {
		$self->{debug} = $arg{debug};
	} else {
		$self->{debug} = SitemasonPl::Debug->new;
	}
	$self->{debug}->call;
	
	return $self;
}


#=====================================================

=head2 B<parse>

 my $search_criteria = $searchparse->parse($search_string);

=cut
#=====================================================
sub parse {
	my $self = shift || return; $self->{debug}->call;
	my $orig_search = shift;
	my $search = lc($orig_search);
	
	my $options = $self->{options};
	unless (defined($self->{options})) {
		$options = {
			quotes	=> 1,
			times	=> 1,
			dates	=> 1,
			time	=> 1
		};
	}
	
	my $results = {
		when	=> [],
		where	=> [],
		dates	=> [],
		what	=> []
	};
	
	my $unabbr = $search;
	if ($options->{times} || $options->{dates}) {
		$unabbr = unabbr_date($search);
	}
	
	$self->traverse( {
		search		=> $unabbr,
		options		=> $options,
		results		=> $results,
		limit		=> 0
	} );
	
	if ($options->{times} || $options->{dates}) {
		my ($start_date, $end_date);
		my ($sd, $ed);
		my @date_array;
		if ($results->{when} && @{$results->{when}}) {
			push(@date_array, @{$results->{when}});
		}
		if ($results->{dates} && @{$results->{dates}}) {
			push(@date_array, @{$results->{dates}});
		}
		if (@date_array) {
			foreach my $when (@date_array) {
				if ($when->{start_time}) {
					my ($year, $month, $day, $hour, $minute) = $when->{start_time} =~ /^(\d+)\-(\d+)\-(\d+)(?:\s+(\d+):(\d+))?/;
					unless (($month > 0) && ($day > 0)) { next; }
					my $start = DateTime->new(
						year	=> $year,
						month	=> $month,
						day		=> $day,
						hour	=> $hour || 0,
						minute	=> $minute || 0
					);
					if (!$start_date || ($start < $sd)) { $start_date = $when->{start_time}; $sd = $start; }
					if (!$end_date || ($start > $ed)) { $end_date = $when->{start_time}; $ed = $start; }
				}
				if ($when->{end_time}) {
					my ($year, $month, $day, $hour, $minute) = $when->{end_time} =~ /^(\d+)\-(\d+)\-(\d+)(?:\s+(\d+):(\d+))?/;
					my $end = DateTime->new(
						year	=> $year,
						month	=> $month,
						day		=> $day,
						hour	=> $hour || 0,
						minute	=> $minute || 0
					);
					if ($end_date || ($end > $ed)) { $end_date = $when->{end_time}; $ed = $end; }
					if (!$start_date || ($end < $sd)) { $start_date = $when->{end_time}; $sd = $end; }
				}
			}
# 			if ($end_date !~ /\d+:\d{2}$/) {
# 				$ed->add( days => 1 );
# 				$end_date = $ed->ymd;
# 			}
		}
		unless ($start_date || $options->{noDefaultDate}) {
			my $dt = DateTime->now( time_zone => $self->{time_zone} );
			$start_date = $dt->ymd;
		}
		$results->{start_date} = $start_date;
		$results->{end_date} = $end_date;
	}
	
	if ($results->{alternates} && @{$results->{alternates}}) {
		foreach my $alternate (@{$results->{alternates}}) {
			my $search = $orig_search;
			$search =~ s/$alternate->{original}/$alternate->{replacement}/i;
			my $qsearch = $search;
			$qsearch =~ s/ /+/g;
			$alternate->{query} = '?q=' . $qsearch;
		}
	}
	$self->{alternates} = $results->{alternates};
	
	return $results;
}


#== date, time, and parsing functions ================

=head2 B<date, time, and parsing functions>

=cut
#=====================================================

sub traverse {
	my $self = shift || return; $self->{debug}->call;
	my $args = shift;
	my $search = $args->{search};
	my $options = $args->{options};
	my $results = $args->{results};
	my $last_date = $args->{last_date};
	my $limit = $args->{limit};
	$limit++;
	if ($limit > 30) { return; }
	
	my ($quotes, $times, $date1, $date2, $date3, $date4, $date5, $date6, $date7, $date8, $date9, $time);
	
	if ($options->{quotes}) { $quotes = parse_quotes($search); } else { $quotes->{depth} = 10000; }
	if ($options->{times}) { $times = parse_times($search, $self->{time_zone}); } else { $times->{depth} = 10000; }
	if ($options->{dates}) { $date1 = parse_date1($search); } else { $date1->{depth} = 10000; }
	if ($options->{dates}) { $date2 = parse_date2($search); } else { $date2->{depth} = 10000; }
	if ($options->{dates}) { $date3 = parse_date3($search); } else { $date3->{depth} = 10000; }
	if ($options->{dates}) { $date4 = parse_date4($search); } else { $date4->{depth} = 10000; }
	if ($options->{dates}) { $date5 = parse_date5($search); } else { $date5->{depth} = 10000; }
	if ($options->{dates}) { $date6 = parse_date6($search); } else { $date6->{depth} = 10000; }
	if ($options->{dates}) { $date7 = parse_date7($search); } else { $date7->{depth} = 10000; }
	if ($options->{dates}) { $date8 = parse_date8($search); } else { $date8->{depth} = 10000; }
	if ($options->{dates}) { $date9 = parse_date9($search); } else { $date9->{depth} = 10000; }
	if ($options->{time}) { $time = parse_time($search); } else { $time->{depth} = 10000; }
	
	# recognize days of week (Monday), month (January), month year (January, 2006)
	
	if ($self->{log}->{parsers}) {
		print STDERR "$limit search: $search\n";
		if ($options->{quotes}) { print STDERR "	quotes $quotes->{depth}: $quotes->{answer} | $quotes->{remainder}\n"; }
		if ($options->{times}) { print STDERR "	times $times->{depth}: $times->{answer} | $times->{remainder}\n"; }
		if ($options->{dates}) { print STDERR "	date1 $date1->{depth}: $date1->{date} | $date1->{remainder}\n"; }
		if ($options->{dates}) { print STDERR "	date2 $date2->{depth}: $date2->{date} | $date2->{remainder}\n"; }
		if ($options->{dates}) { print STDERR "	date3 $date3->{depth}: $date3->{date} | $date3->{remainder}\n"; }
		if ($options->{dates}) { print STDERR "	date4 $date4->{depth}: $date4->{date} | $date4->{remainder}\n"; }
		if ($options->{dates}) { print STDERR "	date5 $date5->{depth}: $date5->{date} | $date5->{remainder}\n"; }
		if ($options->{dates}) { print STDERR "	date6 $date6->{depth}: $date6->{date} | $date6->{remainder}\n"; }
		if ($options->{dates}) { print STDERR "	date7 $date7->{depth}: $date7->{date}$date7->{repeat_freq} | $date7->{remainder}\n"; }
		if ($options->{dates}) { print STDERR "	date8 $date8->{depth}: $date8->{date}$date8->{repeat_freq} | $date8->{remainder}\n"; }
		if ($options->{dates}) { print STDERR "	date9 $date9->{depth}: $date9->{date}$date9->{repeat_freq} | $date9->{remainder}\n"; }
		if ($options->{time}) { print STDERR "	time $time->{depth}: $time->{start_time} | $time->{remainder}\n"; }
	}
	
	my $date;
	if (($date1->{depth} <= $date2->{depth}) && ($date1->{depth} <= $date3->{depth}) && ($date1->{depth} <= $date4->{depth})
		 && ($date1->{depth} <= $date5->{depth}) && ($date1->{depth} <= $date6->{depth}) && ($date1->{depth} <= $date7->{depth}) && ($date1->{depth} <= $date8->{depth}) && ($date1->{depth} <= $date9->{depth})) {
		$date = $date1; if ($self->{log}->{parsers}) { print STDERR "parse_date1\n"; }
	} elsif (($date2->{depth} <= $date3->{depth}) && ($date2->{depth} <= $date4->{depth})
		 && ($date2->{depth} <= $date5->{depth}) && ($date2->{depth} <= $date6->{depth}) && ($date2->{depth} <= $date7->{depth}) && ($date2->{depth} <= $date8->{depth}) && ($date2->{depth} <= $date9->{depth})) {
		$date = $date2; if ($self->{log}->{parsers}) { print STDERR "parse_date2\n"; }
	} elsif (($date3->{depth} <= $date4->{depth}) && ($date3->{depth} <= $date5->{depth}) && ($date3->{depth} <= $date6->{depth}) && ($date3->{depth} <= $date7->{depth}) && ($date3->{depth} <= $date8->{depth}) && ($date3->{depth} <= $date9->{depth})) {
		$date = $date3; if ($self->{log}->{parsers}) { print STDERR "parse_date3\n"; }
	} elsif (($date4->{depth} <= $date5->{depth}) && ($date4->{depth} <= $date6->{depth}) && ($date4->{depth} <= $date7->{depth}) && ($date4->{depth} <= $date8->{depth}) && ($date4->{depth} <= $date9->{depth})) {
		$date = $date4; if ($self->{log}->{parsers}) { print STDERR "parse_date4\n"; }
	} elsif (($date5->{depth} <= $date6->{depth}) && ($date5->{depth} <= $date7->{depth}) && ($date5->{depth} <= $date8->{depth}) && ($date5->{depth} <= $date9->{depth})) {
		$date = $date5; if ($self->{log}->{parsers}) { print STDERR "parse_date5\n"; }
	} elsif (($date6->{depth} <= $date7->{depth}) && ($date6->{depth} <= $date8->{depth}) && ($date6->{depth} <= $date9->{depth})) {
		$date = $date6; if ($self->{log}->{parsers}) { print STDERR "parse_date6\n"; }
	} elsif (($date7->{depth} <= $date8->{depth}) && ($date7->{depth} <= $date9->{depth})) {
		$date = $date7; if ($self->{log}->{parsers}) { print STDERR "parse_date7\n"; }
	} elsif ($date8->{depth} <= $date9->{depth}) {
		$date = $date8; if ($self->{log}->{parsers}) { print STDERR "parse_date8\n"; }
	} else {
		$date = $date9; if ($self->{log}->{parsers}) { print STDERR "parse_date9\n"; }
	}
	
	my $remainder;
	my $depth = 10000;
	
	# Find nearest match
	# if quotes are closest
	if ($quotes->{answer} && ($quotes->{depth} <= $times->{depth}) && ($quotes->{depth} <= $date->{depth}) && ($quotes->{depth} <= $time->{depth})) {
		push(@{$results->{what}}, $quotes->{answer});
		$remainder = $quotes->{remainder};
		$depth = $quotes->{depth};
		if ($self->{log}->{parsers}) { print STDERR "parse_quotes\n"; }
	}
	# if time is closest
	elsif ($times->{answer} && ($times->{depth} <= $date->{depth}) && ($times->{depth} <= $time->{depth})) {
		push(@{$results->{when}}, $times->{answer});
		$remainder = $times->{remainder};
		$depth = $times->{depth};
		if ($self->{log}->{parsers}) { print STDERR "parse_times\n"; }
	}
	# if date and time is closest
	elsif (($date->{date} || $date->{repeat_freq}) && exists($time->{depth}) && $time->{start_time}) {
		# Found a time
		if ($date->{depth} > $time->{depth}) {
			if ($last_date->{date} || $last_date->{repeat_freq}) {
				push(@{$results->{dates}}, merge($last_date, $time, $self->{time_zone}));
				$last_date->{used} = 1;
				$remainder = $time->{remainder};
				$depth = $time->{depth};
				if ($self->{log}->{parsers}) { print STDERR "parse_time\n"; }
			}
		}
		# Found a date
		else {
			if (($last_date->{date} || $last_date->{repeat_freq}) && (!$last_date->{used})) {
				$last_date->{is_all_day} = 1;
				push(@{$results->{dates}}, merge($last_date, {}, $self->{time_zone}));
			}
			$remainder = $date->{remainder};
			$depth = $date->{depth};
			$last_date = $date;
			if ($self->{log}->{parsers}) { print STDERR "parse_date\n"; }
		}
	}
	# Found only date
	elsif ($date->{date} || $date->{repeat_freq}) {
		if (($last_date->{date} || $last_date->{repeat_freq}) && (!$last_date->{used})) {
			$last_date->{is_all_day} = 1;
			push(@{$results->{dates}}, merge($last_date, {}, $self->{time_zone}));
		}
		$remainder = $date->{remainder};
		$depth = $date->{depth};
		$last_date = $date;
		if ($self->{log}->{parsers}) { print STDERR "parse_date only\n"; }
	}
	# Found only time
	elsif ($time->{start_time}) {
		if ($last_date->{date} || $last_date->{repeat_freq}) {
			push(@{$results->{dates}}, merge($last_date, $time, $self->{time_zone}));
			$last_date->{used} = 1;
			$remainder = $time->{remainder};
			$depth = $time->{depth};
			if ($self->{log}->{parsers}) { print STDERR "parse_time only\n"; }
		}
	}
	
	if ($remainder && ($remainder ne $search)) {
		if ($depth > 3) {
			my ($what) = $search =~ /^(.{$depth})/;
			$what =~ s/^\s*(and|at|in|on|of|or|to|thru|through|from)\b\s*//;
			$what =~ s/\s*\b(and|at|in|on|of|or|to|thru|through|from)\s*$//;
			$what =~ s/^\s*\W+\s*//;
			$what =~ s/\s*\W+\s*$//;
			if (length($what) > 2) { push(@{$results->{what}}, $what); }
		}
		$self->traverse( {
			search		=> $remainder,
			options		=> $options,
			results		=> $results,
			last_date	=> $last_date,
			limit		=> $limit
		} );
	} else {
		if (($last_date->{date} || $last_date->{repeat_freq}) && (!$last_date->{used})) {
			$last_date->{is_all_day} = 1;
			push(@{$results->{dates}}, merge($last_date, {}, $self->{time_zone}));
		}
		if ($depth == 10000) {
			my $whats = parse_what($search);
			if ($whats && @{$whats}) { push(@{$results->{what}}, @{$whats}); }
		} elsif ($remainder) {
			my $whats = parse_what($remainder);
			if ($whats && @{$whats}) { push(@{$results->{what}}, @{$whats}); }
		} elsif (($limit == 1) && ($depth > 3)) {
			my ($what) = $search =~ /^(.{$depth})/;
			$what =~ s/^\s*(and|at|in|on|of|or|to|thru|through|from)\b\s*//;
			$what =~ s/\s*\b(and|at|in|on|of|or|to|thru|through|from)\s*$//;
			$what =~ s/^\s*\W+\s*//;
			$what =~ s/\s*\W+\s*$//;
			if (length($what) > 2) { push(@{$results->{what}}, $what); }
		}
	}
}

sub parse_quotes {
	my $search = shift;
	my $results = {};
	if ($search =~ /"(.*?)"/) {
		$results = {
			original	=> $&,
			answer		=> $1,
			remainder	=> $',
			depth		=> length($`)
		};
	}
	return $results;
}
	
sub parse_what {
	my $search = shift;
	my $results = [];
	my @searches = split(/\s*(\/|,|;|\:|&amp;|\band\b|\bor\b|\bto\b)\s*/,$search);
	foreach my $what (@searches) {
		$what =~ s/^\s*(at|in|on|of|\W+)\b\s*//;
		$what =~ s/\s*\b(at|in|on|of|\W+)\s*$//;
		if (length($what) > 2) { push(@{$results}, $what); }
	}
	return $results;
}
	
# Pull times
sub parse_times {
	my $search = shift;
	my $time_zone = shift;
	my $results = { depth => 10000 };
	my $timeReg = '(?:\s+|\b)(?:in(?:\s+the)?\s+|on\s+|and\s+|or\s+|^\s*|,\s*|;\s*)?(today|tomorrow|yesterday|(?:this|next|last) (?:month|week(?:end)?)|future|(?:\d+)\s*(?:day|week|month)s?\s+ago|(?:next\s*|last\s*)?(?:\d+)\s*(?:day|week|month)s?|any ?(?:time|date))\b';
	$search =~ s/\bone\b/1/g;
	$search =~ s/\btwo\b/2/g;
	$search =~ s/\bthree\b/3/g;
	$search =~ s/\bfour\b/4/g;
	$search =~ s/\bfive\b/5/g;
	$search =~ s/\bsix\b/6/g;
	$search =~ s/\bseven\b/7/g;
	$search =~ s/\beight\b/8/g;
	$search =~ s/\bnine\b/9/g;
	$search =~ s/\bten\b/10/g;
	$search =~ s/\beleven\b/11/g;
	$search =~ s/\btwelve\b/12/g;
	if ($search =~ /$timeReg/) {
		my $time = $1;
		$results = {
			original	=> $&,
			remainder	=> $',
			depth		=> length($`)
		};
		my $when;
		my $ct = DateTime->now( time_zone => $time_zone );
		my ($start_date, $end_date);
# 		my $dt = DateTime->new(
# 			year   => $year,
# 			month  => $month,
# 			day    => $day
# 		);
# 		$dt->add( days => 1 );
# 		$joint->{end_time} = $dt->ymd . ' ' . $time->{end_time};
		if ($time eq 'today') {
			$start_date = $ct->ymd;
			$end_date = $ct->ymd;
			$when = 'today';
		}
		elsif ($time eq 'tomorrow') {
			$ct->add( days => 1 );
			$start_date = $ct->ymd;
			$end_date = $ct->ymd;
			$when = $time;
		}
		elsif ($time eq 'yesterday') {
			$ct->subtract( days => 1 );
			$start_date = $ct->ymd;
			$end_date = $ct->ymd;
			$when = $time;
		}
		elsif ($time eq 'this weekend') {
			my $dow = $ct->dow;
			my $sday = 5-$dow;
			my $eday = 7-$dow;
			if ($sday < 0) { $sday = 0; }
			$ct->add( days => $sday );
			$start_date = $ct->ymd;
			$ct->add( days => ($eday-$sday) );
			$end_date = $ct->ymd;
			$when = $time;
		}
		elsif ($time eq 'next weekend') {
			my $dow = $ct->dow;
			my $day = 12-$dow;
			$ct->add( days => $day );
			$start_date = $ct->ymd;
			$ct->add( days => 2 );
			$end_date = $ct->ymd;
			$when = $time;
		}
		elsif ($time eq 'last weekend') {
			my $dow = $ct->dow;
			my $day = 12-$dow;
			$ct->add( days => $day );
			$ct->subtract( days => 7 );
			$start_date = $ct->ymd;
			$ct->add( days => 2 );
			$end_date = $ct->ymd;
			$when = $time;
		}
		elsif ($time eq 'this week') {
			my $dow = $ct->dow;
			my $day = 7-$dow;
			$ct->add( days => $day );
			$ct->subtract( days => 7 );
			$start_date = $ct->ymd;
			$ct->add( days => 6 );
			$end_date = $ct->ymd;
			$when = $time;
		}
		elsif ($time eq 'next week') {
			my $dow = $ct->dow;
			my $day = 7-$dow;
			$ct->add( days => $day );
			$start_date = $ct->ymd;
			$ct->add( days => 6 );
			$end_date = $ct->ymd;
			$when = $time;
		}
		elsif ($time eq 'last week') {
			my $dow = $ct->dow;
			my $day = 7-$dow;
			$ct->add( days => $day );
			$ct->subtract( days => 14 );
			$start_date = $ct->ymd;
			$ct->add( days => 6 );
			$end_date = $ct->ymd;
			$when = $time;
		}
		elsif ($time eq 'this month') {
			my $month = $ct->set( day => 1 );
			$start_date = $ct->ymd;
			$ct->add( months => 1 );
			$ct->subtract( days => 1 );
			$end_date = $ct->ymd;
			$when = $time;
		}
		elsif ($time eq 'next month') {
			my $month = $ct->set( day => 1 );
			$ct->add( months => 1 );
			$start_date = $ct->ymd;
			$ct->add( months => 1 );
			$ct->subtract( days => 1 );
			$end_date = $ct->ymd;
			$when = $time;
		}
		elsif ($time eq 'last month') {
			my $month = $ct->set( day => 1 );
			$ct->subtract( months => 1 );
			$start_date = $ct->ymd;
			$ct->add( months => 1 );
			$ct->subtract( days => 1 );
			$end_date = $ct->ymd;
			$when = $time;
		}
		elsif ($time =~ /(next|last)?\s*(\d+) ?days?(\s*ago)?/) {
			my $direction = $1 || $3;
			my $interval = $2 - 1;
			if ($direction =~ /last/) {
				$end_date = $ct->ymd;
				$ct->subtract( days => $interval );
				$start_date = $ct->ymd;
				$when = "last${interval}days";
			} elsif ($direction =~ /ago/) {
				$ct->subtract( days => $interval );
				$start_date = $ct->ymd;
				$end_date = $ct->ymd;
				$when = "${interval}days ago";
			} else {
				$start_date = $ct->ymd;
				$ct->add( days => $interval );
				$end_date = $ct->ymd;
				$when = "next${interval}days";
			}
		}
		elsif ($time =~ /(next|last)?\s*(\d+) ?weeks?(\s*ago)?/) {
			my $direction = $1 || $3;
			my $interval = $2;
			if ($direction =~ /last/) {
				$end_date = $ct->ymd;
				$ct->subtract( weeks => $interval );
				$start_date = $ct->ymd;
				$when = "last${interval}weeks";
			} elsif ($direction =~ /ago/) {
				$ct->subtract( weeks => $interval );
				$start_date = $ct->ymd;
				$ct->add( days => 6 );
				$end_date = $ct->ymd;
				$when = "${interval}weeks ago";
			} else {
				$start_date = $ct->ymd;
				$ct->add( weeks => $interval );
				$end_date = $ct->ymd;
				$when = "next${interval}weeks";
			}
		}
		elsif ($time =~ /(next|last)?\s*(\d+) ?months?(\s*ago)?/) {
			my $direction = $1 || $3;
			my $interval = $2;
			if ($direction =~ /last/) {
				$end_date = $ct->ymd;
				$ct->subtract( months => $interval );
				$start_date = $ct->ymd;
				$when = "last${interval}months";
			} elsif ($direction =~ /ago/) {
				$ct->subtract( months => $interval );
				$ct->set( day => 1 );
				$start_date = $ct->ymd;
				$ct->add( months => 1 );
				$ct->subtract( days => 1 );
				$end_date = $ct->ymd;
				$when = "${interval}months ago";
			} else {
				$start_date = $ct->ymd;
				$ct->add( months => $interval );
				$end_date = $ct->ymd;
				$when = "next${interval}months";
			}
		}
		elsif ($time eq 'future') {
			$start_date = $ct->ymd;
			$end_date = '2099-12-31';
			$when = 'future';
		}
		elsif ($time =~ /any ?(?:time|date)/) {
			$when = 'any';
		}
		if ($when) { $results->{answer} = { when => $when, start_time => $start_date, end_time => $end_date }; }
	}
	return $results;
}

sub merge {
	my $date = shift;
	my $time = shift;
	my $time_zone = shift;
	
	unless ($date->{date}) {
		my $ct = DateTime->now( time_zone => $time_zone );
		if ($date->{repeat_freq} eq 'weekly') {
			if ($date->{repeat_byday}) {
				my $weekday = weekday_abbr_to_number($date->{repeat_byday});
				my $cdow = $ct->dow;
				my $dow_diff = $weekday - $cdow;
				if ($dow_diff < 0) { $dow_diff += 7; }
				$ct->add( days => $dow_diff );
			}
		} elsif ($date->{repeat_freq} eq 'monthly') {
			if ($date->{repeat_bymonth}) {
				my $month = $date->{repeat_bymonth};
				my $cmon = $ct->month;
				my $mon_diff = $month - $cmon;
				if ($mon_diff < 0) { $mon_diff += 12; }
				$ct->add( months => $mon_diff );
			}
			if ($date->{repeat_byday}) {
				my $cmon = $ct->month;
				my $month = $date->{repeat_bymonth} || $cmon;
				$ct->set( day => 1 );
				my ($wom, $wd) = $date->{repeat_byday} =~ /(-?\d+)(\w+)/;
				my $weekday = weekday_abbr_to_number($wd);
				my $cwom = $ct->weekday_of_month;
				my $cdow = $ct->dow;
				
				my $dow_diff = $weekday - $cdow;
				if ($dow_diff < 0) { $dow_diff += 7; }
				
				my $week_adjust = ($wom-1) * 7 + $dow_diff;
				$ct->add( days => $week_adjust );
			}
		}
		my $ctime = current_time();
		$date->{date} = $ct->ymd;
	}
	
	my $joint;
	%{$joint} = %{$date};
	
	$joint->{start_time} = $date->{date};
	if ($time->{start_time}) { $joint->{start_time} .= ' ' . $time->{start_time}; }
	$joint->{origtime} = $time->{original};
	if ($time->{end_time}) {
		my ($shour, $smin) = $time->{start_time} =~ /(\d+):(\d+)/;
		my ($ehour, $emin) = $time->{end_time} =~ /(\d+):(\d+)/;
		if (($ehour < $shour) || (($ehour == $shour) && ($emin < $smin))) {
			my ($year, $month, $day) = $date->{date} =~ /(\d+)-(\d+)-(\d+)/;
			my $dt = DateTime->new(
				year   => $year,
				month  => $month,
				day    => $day
			);
			$dt->add( days => 1 );
			$joint->{end_time} = $dt->ymd . ' ' . $time->{end_time};
		} else {
			$joint->{end_time} = $date->{date} . ' ' . $time->{end_time};
		}
	}
	return $joint;
}

sub parse_time {
	my $search = shift;
	my $results = { depth => 10000 };
	
	if ($search =~ /^\b(1[0-2]|[1-9])\-(2[0-3]|[01]?[0-9])\b/) {
		my $shour = $1;
		my $ehour = $2;
		if ($ehour > 12) {
			if ($shour < 12) { $shour += 12; }
		}
		$search =~ s/^(1[0-2]|[1-9])\-/$shour:00-/;
	}
	my $tre = '(?:2[0-3]|[01]?[0-9]):[0-5][0-9](?::[0-5][0-9])?';
	if ($search =~ /($tre)(?:-($tre))?/) {
		$results = {
			original	=> $&,
			start_time	=> $1,
			end_time	=> $2,
			remainder	=> $',
			depth		=> length($`)
		};
	}
	return $results;
}

sub parse_date1 {
	my $search = shift;
	my $results = { depth => 10000 };
	
	# January 1 or January 1-2 or Sunday, January 1st, 2005
	if ($search =~ /(?:(Sunday|Monday|Tuesday|Wednesday|Thursday|Friday|Saturday),?\s*)?(January|February|March|April|May|June|July|August|September|October|November|December)\s*\b(\d{1,2})(?:st|nd|rd|th)?(?:\s*-\s*(\d+)(?:st|nd|th)?)?(?:(?:,\s*|\s+)(\d{2,4})(?!:))?\b/i) {
		$results = {
			original	=> $&,
			remainder	=> $',
			depth		=> length($`)
		};
		my $month = clean_month($2);
		my $day = clean_day($3) || return { depth => 10000 };
		print STDERR "no return\n";
		my $year = clean_year($5) || fill_year($month, $day);
		if ($4) {
			my $new = $results->{original};
			$new =~ s/\d+(?:st|nd|th)?\s*-\s*(\d+)(?:st|nd|th)?/$1/;
			my $time;
			if ($results->{remainder} =~ /^\s*,?\s*(\d{1,2}:\d{2})/) { $time = "$1 "; }
			$results->{remainder} = $time . $new . $results->{remainder};
		}
		$results->{date} = "$year-$month-$day";
	}
	return $results;
}

sub parse_date2 {
	my $search = shift;
	my $results = { depth => 10000 };
	
	# 1 of January or Sunday, 1st of January, 2005
	if ($search =~ /(?:(Sunday|Monday|Tuesday|Wednesday|Thursday|Friday|Saturday),?\s*)?\b(\d{1,2})(?:st|nd|rd|th)?(?:\s+of)?\s+(January|February|March|April|May|June|July|August|September|October|November|December)(?:,?\s*(\d{2,4}))?\b/i) {
		$results = {
			original	=> $&,
			remainder	=> $',
			depth		=> length($`)
		};
		my $month = clean_month($3);
		my $day = clean_day($2);
		my $year = clean_year($4) || fill_year($month, $day);
		$results->{date} = "$year-$month-$day";
	}
	return $results;
}

sub parse_date3 {
	my $search = shift;
	my $results = { depth => 10000 };
	
	# 2005-1-1 or Sunday, 2005/01/01
	if ($search =~ /(?:(Sunday|Monday|Tuesday|Wednesday|Thursday|Friday|Saturday),?\s*)?\b(\d{4})[\/-](\d{1,2})[\/-](\d{1,2})\b/i) {
		$results = {
			original	=> $&,
			remainder	=> $',
			depth		=> length($`)
		};
		my $year = clean_year($2);
		my $month = clean_month($3);
		my $day = clean_day($4);
		$results->{date} = "$year-$month-$day";
	}
	return $results;
}

sub parse_date4 {
	my $search = shift;
	my $results = { depth => 10000 };
	
	# 1/1 or Sunday, 01-01-2005
	if ($search =~ /(?:(Sunday|Monday|Tuesday|Wednesday|Thursday|Friday|Saturday),?\s*)?\b(\d{1,2})[\/-](\d{1,2})(?:[\/-](\d{2,4}))\b/i) {
		$results = {
			original	=> $&,
			remainder	=> $',
			depth		=> length($`)
		};
		my $month = clean_month($2);
		my $day = clean_day($3);
		my $year = clean_year($4) || fill_year($month, $day);
		$results->{date} = "$year-$month-$day";
	}
	return $results;
}

sub parse_date5 {
	my $search = shift;
	my $results = { depth => 10000 };
	
	# January, Jan, 2007, or Jan 2007
	if ($search =~ /(January|February|March|April|May|June|July|August|September|October|November|December)(?:,?\s*(\d{2,4}))?\b/i) {
		$results = {
			original	=> $&,
			remainder	=> $',
			depth		=> length($`)
		};
		my $month = clean_month($1);
		my $day = 1;
		my $year = clean_year($2) || fill_year($month, $day);
		$results->{date} = "$year-$month-$day";
		# end date
		my $date = SitemasonPl::Date->new;
		my $dom = $date->daysInMonth($year, $month);
		$results->{remainder} = "$year-$month-$dom " . $results->{remainder};
	}
	return $results;
}

sub parse_date6 {
	my $search = shift;
	my $results = { depth => 10000 };
	
	# 2008-04 or 4/2007
	my ($month, $end_month, $year);
	if ($search =~ /\b(\d{4})-(\d{1,2})\b/i) {
		$results = {
			original	=> $&,
			remainder	=> $',
			depth		=> length($`)
		};
		$month = $end_month = clean_month($2);
		$year = clean_year($1);
	} elsif ($search =~ /\b(\d{1,2})\/(\d{2,4})\b/i) {
		$results = {
			original	=> $&,
			remainder	=> $',
			depth		=> length($`)
		};
		$month = $end_month = clean_month($1);
		$year = clean_year($2);
	} elsif (($search =~ /\b(\d{4})\b/i) && _is_year_reasonable($1)) {
		$results = {
			original	=> $&,
			remainder	=> $',
			depth		=> length($`)
		};
		$month = 1;
		$end_month = 12;
		$year = clean_year($1);
	}
	if ($month && $year) {
		my $day = 1;
		$results->{date} = "$year-$month-$day";
		# end date
		my $date = SitemasonPl::Date->new;
		my $dom = $date->daysInMonth($year, $end_month);
		$results->{remainder} = "$year-$end_month-$dom " . $results->{remainder};
	}
	return $results;
}

sub _is_year_reasonable {
	my $year = shift || return;
	my $cyear = (localtime())[5] + 1900;
	if (($year > ($cyear - 20)) && ($year < ($cyear + 10))) { return 1; }
}

sub parse_date7 {
	my $search = shift;
	my $results = { depth => 10000 };
	
	# 1st Sunday or first Sunday or 2nd to the last Sunday (of every month|in January)
	if ($search =~ /(first|sec(?:ond)?|third|fourth|fifth|1st|2nd|3rd|4th|5th|last)(?:\s+(?:to\s+the\s+)?(last))?\s+(Sundays?|Mondays?|Tuesdays?|Wednesdays?|Thursdays?|Fridays?|Saturdays?)(?:\s+(?:of|in))?(?:\s+((every\s+|each\s+)?month|January|February|March|April|May|June|July|August|September|October|November|December))?/i) {
		$results = {
			original	=> $&,
			remainder	=> $',
			depth		=> length($`)
		};
		my $ord = clean_ordinal($1, $2);
		my $weekday = clean_weekday($3);
		my $month = clean_month($4);
		$results->{repeat_freq} = 'monthly';
		$results->{repeat_byday} = $ord . $weekday;
		$results->{repeat_bymonth} = $month;
	}
	return $results;
}

sub parse_date8 {
	my $search = shift;
	my $results = { depth => 10000 };
	
	# Sundays or every Sunday
	if ($search =~ /(?:every\s+|each\s+)?(Sundays?|Mondays?|Tuesdays?|Wednesdays?|Thursdays?|Fridays?|Saturdays?)/i) {
		$results = {
			original	=> $&,
			remainder	=> $',
			depth		=> length($`)
		};
		my $weekday = clean_weekday($1);
		$results->{repeat_freq} = 'weekly';
		$results->{repeat_byday} = $weekday;
	}
	return $results;
}

sub parse_date9 {
	my $search = shift;
	my $results = { depth => 10000 };
	
	# daily or every day
	if ($search =~ /(?:every\s+|each\s+)?(day|daily)/i) {
		$results = {
			original	=> $&,
			remainder	=> $',
			depth		=> length($`)
		};
		$results->{repeat_freq} = 'daily';
	}
	return $results;
}

sub clean_ordinal {
	my $dirty = lc(shift);
	my $last = shift;
	my $ord;
	if ($dirty =~ /(first|1st)/) { $ord = 1; }
	elsif ($dirty =~ /(sec(ond)?|2nd)/) { $ord = 2; }
	elsif ($dirty =~ /(third|3rd)/) { $ord = 3; }
	elsif ($dirty =~ /(fourth|4th)/) { $ord = 4; }
	elsif ($dirty =~ /(fifth|5th)/) { $ord = 5; }
	elsif ($dirty =~ /last/) { $ord = -1; }
	if ($last && $ord) { $ord = '-' . $ord; }
	unless ($ord) { undef($ord); }
	return $ord;
}

sub clean_day {
	my $dirty = shift;
	my ($day) = $dirty =~ /(?:^|\D)(30|31|[1-2][0-9]|0?[1-9])(?:$|\D)/;
	unless ($day) { undef($day); }
	return $day;
}

sub clean_weekday {
	my $dirty = shift;
	my $weekday;
	if ($dirty =~ /(Sunday|Monday|Tuesday|Wednesday|Thursday|Friday|Saturday)s?/i) {
		my $tmp = $1;
		($weekday) = $tmp =~ /^(\w\w)/;
		$weekday = uc($weekday);
	}
	unless ($weekday) { undef($weekday); }
	return $weekday;
}

sub clean_month {
	my $dirty = shift;
	my $month;
	if ($dirty =~ /(January|February|March|April|May|June|July|August|September|October|November|December)/i) {
		my $tmp = $1;
		my @months = load_months();
		my $cnt = 1;
		foreach my $mon (@months) {
			if (lc($mon) eq lc($tmp)) { $month = $cnt; last; }
			$cnt++;
		}
	} else {
		($month) = $dirty =~ /(?:^|\D)(1[0-2]|0?[1-9])(?:$|\D)/;
	}
	unless ($month) { undef($month); }
	return $month;
}

sub clean_year {
	my $dirty = shift;
	my ($year) = $dirty =~ /(\d+)/;
	if (!$year || ($year > 9999)) { undef($year); }
	elsif ($year < 30) { $year += 2000; }
	elsif ($year < 100) { $year += 1900; }
	return $year;
}

sub fill_year {
	my $month = shift;
	my $day = shift;
	my $ctime = current_time();
	my $year = $ctime->{year};
	if (($month == $ctime->{month}) && ($day < $ctime->{day})) { $year++; }
	if ($month < $ctime->{month}) { $year++; }
	return $year;
}

sub current_time {
	my $time;
		($time->{second},$time->{minute},$time->{hour},$time->{mday},$time->{month},$time->{year},$time->{wday}) = gmtime(time);
	$time->{month}++; $time->{year} += 1900;
	return $time;
}

sub unabbr_date {
	my $search = shift;
	
	my $abbr = load_abbr();
	my ($clean) = $search =~ /\s*(.+?)\s*$/s;
	$clean =~ s/\b(\d+(?::\d\d)?)\s*(?:\-|to|thru|through)\s*(\d+(?::\d\d)?\s*([ap])\.?m(?:\.|\b))/$1 ${3}m-$2/ig;
 	$clean =~ s/\b(\d+(?::\d\d)?)\s*(?:and|&|;|\|)\s*(\d+(?::\d\d)?\s*([ap])\.?m(?:\.|\b))/$1 ${3}m,$2/ig;
	$clean =~ s/\b(?:noon\b|mid\-?day\b|12(:00)?\s*p\.?m(?:\.|\b))/12:00/ig;
	$clean =~ s/\b(?:mid\-?night\b|mid\-?nite\b|12(:00)?\s*1\.?m(?:\.|\b))/0:00/ig;
	$clean =~ s/\b(\d+)(:\d\d)?\s*a\.?m(?:\.|\b)/$1.($2 || ':00')/eig;
	$clean =~ s/\b(\d+)(:\d\d)?\s*p\.?m(?:\.|\b)/($1+12).($2 || ':00')/eig;
	foreach my $check (@{$abbr}) {
		$clean =~ s/$check->{match}/$check->{replace}/ig;
	}
	return $clean;
}


sub load_months {
	return qw(January February March April May June July August September October November December);
}

sub load_week_days {
	return qw(Sunday Monday Tuesday Wednesday Thursday Friday Saturday);
}

sub weekday_abbr_to_number {
	my $weekday = shift || return;
	my $weekdays = {
		SU	=> 7,
		MO	=> 1,
		TU	=> 2,
		WE	=> 3,
		TH	=> 4,
		FR	=> 5,
		SA	=> 6
	};
	return $weekdays->{$weekday};
}

sub load_abbr {
	return [ {
		match	=> '\bSun?(\.|\b)',
		replace	=> 'Sunday'
	}, {
		match	=> '\bMon(\.|\b)',
		replace	=> 'Monday'
	}, {
		match	=> '\bTu(?:es?)?(\.|\b)',
		replace	=> 'Tuesday'
	}, {
		match	=> '\bWed?(\.|\b)',
		replace	=> 'Wednesday'
	}, {
		match	=> '\bTh(?:u(?:rs?)?)?(\.|\b)',
		replace	=> 'Thursday'
	}, {
		match	=> '\bFri?(\.|\b)',
		replace	=> 'Friday'
	}, {
		match	=> '\bSa(?:t(?:ur)?)?(\.|\b)',
		replace	=> 'Saturday'
	}, {
		match	=> '\bSa(?:t(?:ur)?)?(\.|\b)',
		replace	=> 'Saturday'
	}, {
		match	=> '\bJan(\.|\b)',
		replace	=> 'January'
	}, {
		match	=> '\bFeb(\.|\b)',
		replace	=> 'February'
	}, {
		match	=> '\bMar(\.|\b)',
		replace	=> 'March'
	}, {
		match	=> '\bApr(\.|\b)',
		replace	=> 'April'
	}, {
		match	=> '\bMay(\.|\b)',
		replace	=> 'May'
	}, {
		match	=> '\bJun(\.|\b)',
		replace	=> 'June'
	}, {
		match	=> '\bJul(\.|\b)',
		replace	=> 'July'
	}, {
		match	=> '\bAug(\.|\b)',
		replace	=> 'August'
	}, {
		match	=> '\bSept?(\.|\b)',
		replace	=> 'September'
	}, {
		match	=> '\bOct(\.|\b)',
		replace	=> 'October'
	}, {
		match	=> '\bNov(\.|\b)',
		replace	=> 'November'
	}, {
		match	=> '\bDec(\.|\b)',
		replace	=> 'December'
	} ];
}



=head1 CHANGES

  20050627 TJM - v0.01 started development
  20061025 TJM - v2.00 moved from old calendar to SearchParse
  20120105 TJM - v6.0 moved from Sitemason::System to Sitemason6::Library
  20140410 TJM - v7.0 moved to Sitemason7::Library
  20171109 TJM - v8.0 Moved to SitemasonPL open source project

=head1 AUTHOR

  Tim Moses <tim@moses.com>
  Sitemason Open Source <https://github.com/sitemason>

=cut

1;
