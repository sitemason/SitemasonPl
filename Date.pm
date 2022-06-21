package SitemasonPl::Date 8.0;

=head1 NAME

SitemasonPl::Date

=head1 DESCRIPTION


=head1 METHODS

=cut

use v5.012;
use strict;
use DateTime;

use SitemasonPl::Common;
use SitemasonPl::IO qw(mark print_object trace);


#== new ==============================================

=head2 B<new>

Creates and returns a date handle.

 my $date = SitemasonPl::Date->new( debug => $debug );

=cut
#=====================================================
sub new {
	my ($class, %arg) = @_;
	$class || return;
	my $self = {
		io			=> $arg{io},
		timeZone	=> $arg{timeZone} || 'US/Central'
	};
	if (!$self->{io}) { $self->{io} = SitemasonPl::IO->new; }
	bless $self, $class;
	
	return $self;
}


sub dayOfWeek {
	my $self = shift || return;
	my $year = shift;
	my $month = shift;
	my $day = shift;
	# Good for 1700 - 2299
	my $mcList = [6, 2, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4];
	my $ycList = [5, 3, 1, 0, -2, -4, -6];
	my $century = int($year / 100);
	my $yc;
	if (($century >= 17) && ($century <= 22)) { $yc = $ycList->[$century - 17]; }
	if (($year < 1752) || (($year == 1752) && ($month <= 9))) {
		$yc = $yc - 10;
	}
	my $leapYear = $self->isLeapYear($year);
	my $twoYear = ($year % 100);
	my $dow = (($twoYear + int($twoYear / 4) + $mcList->[$month-1] + $day + $yc) % 7);
	if ($leapYear && (($month == 1) || ($month == 2))) { $dow--; }
	if ($dow < 0) { $dow = $dow + 7; }
	elsif ($dow > 6) { $dow = $dow - 7; }
	return $dow;
}

sub isLeapYear {
	my $self = shift || return;
	my $year = shift;
	my $leapYear;
	if ((!($year % 4) && ($year % 100)) || !($year % 400)) {
		$leapYear = 1;
	}
	return $leapYear;
}

sub weeksInMonth {
	my $self = shift || return;
	my $year = shift;
	my $month = shift;
	if (($month == 9) && ($year == 1752)) { return 3; }
	my $dow = $self->dayOfWeek($year, $month, 1);
	my $dom = $self->daysInMonth($year, $month);
	my $diff = $dow + $dom - 28;
	my $wim = 5;
	if ($diff <= 0 ) { $wim = 4; }
	elsif ($diff >= 8) { $wim = 6; }
	return $wim;
}

sub daysInMonth {
	my $self = shift || return;
	my $year = shift;
	my $month = shift;
	my $domList = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
	my $leapYear = $self->isLeapYear($year);
	my $dom = $domList->[$month-1];
	if (($month == 2) && $leapYear) {
		$dom = 29;
	} elsif (($month == 9) && ($year == 1752)) {
		$dom = 19;
	}
	return $dom;
}

sub makeOrdinal {
	my $self = shift || return;
	my $number = shift || return;
	my $ordinal = $number;
	if (($number =~ /1$/) && ($number !~ /11$/)) { $ordinal .= 'st'; }
	elsif (($number =~ /2$/) && ($number !~ /12$/)) { $ordinal .= 'nd'; }
	elsif (($number =~ /3$/) && ($number !~ /13$/)) { $ordinal .= 'rd'; }
	elsif ($number =~ /\d$/) { $ordinal .= 'th'; }
	return $ordinal;
}

sub dayToWeek {
	my $self = shift || return;
	my $year = shift;
	my $month = shift;
	my $day = shift;
	($year, $month, $day) = $self->nextSaturday($year, $month, $day);
	my $dow = $self->dayOfWeek($year, $month, 1);
	my $week = int(($day + $dow) / 7);
	return ($year, $month, $week);
}

sub startOfWeek {
	my $self = shift || return;
	my $year = shift;
	my $month = shift;
	my $week = shift;
	my $dow = $self->dayOfWeek($year, $month, 1);
	my $day = (($week - 1) * 7) - $dow + 1;
	my $dt = DateTime->new(
		year	=> $year,
		month	=> $month,
		day		=> 1
	);
	if ($day < 1) {
		$dt->subtract( days => $dow );
	} else {
		$dt->set( day => $day );
	}
	return ($dt->year, $dt->month, $dt->day);
}

sub endOfWeek {
	my $self = shift || return;
	my $year = shift;
	my $month = shift;
	my $week = shift;
	my $dow = $self->dayOfWeek($year, $month, 1);
	my $day = ($week * 7) - $dow;
	my $lastDay = $self->daysInMonth($year, $month);
	my $dt = DateTime->new(
		year	=> $year,
		month	=> $month,
		day		=> $lastDay
	);
	if ($day > $lastDay) {
		my $dow = $self->dayOfWeek($year, $month, $lastDay);
		$dt->add( days => (6 - $dow) );
	} else {
		$dt->set( day => $day );
	}
	return ($dt->year, $dt->month, $dt->day);
}

sub lastSunday {
	my $self = shift || return;
	my $year = shift;
	my $month = shift;
	my $day = shift;
	my $dow = $self->dayOfWeek($year, $month, $day);
	my $dt = DateTime->new(
		year	=> $year,
		month	=> $month,
		day		=> $day
	);
	$dt->subtract( days => $dow );
	return ($dt->year, $dt->month, $dt->day);
}

sub nextSaturday {
	my $self = shift || return;
	my $year = shift;
	my $month = shift;
	my $day = shift;
	my $dow = $self->dayOfWeek($year, $month, $day);
	my $dt = DateTime->new(
		year	=> $year,
		month	=> $month,
		day		=> $day
	);
	$dt->add( days => (6 - $dow) );
	return ($dt->year, $dt->month, $dt->day);
}

#=====================================================

=head2 B<dayByNum>

=cut
#=====================================================
sub dayByNum {
	my $self = shift || return;
	my $start = shift;
	my ($ord, $day) = $start =~ /(\-?\d+)?(\w+)/;
	my @days = (qw(SU MO TU WE TH FR SA));
	my $num = 0;
	foreach my $byDay (@days) {
		if ($day eq $byDay) { $day = $num; last; }
		$num++;
	}
	return ($num, $ord);
}

#=====================================================

=head2 B<getTime>

 my $st = $date->getTime( {
	date		=> $startDate,
	time		=> $startTime,
	meridian	=> $startMeridian,
	default		=> 'now' || 'today'
 } );

=cut
#=====================================================
sub getTime {
	my $self = shift || return;
	my $args = shift || return;
	
	my $dt = DateTime->now( time_zone => $self->{timeZone} );
	my $unabbr = unabbrDate($args->{date});
	my ($year, $month, $day);
	my ($date, $time, $meridian);
	if ($unabbr =~ /^\d+-/) {
		($date, $time, $meridian) = $unabbr =~ m#^(\d+-\d+-\d+)(?: (\d+(?::\d+(?::\d+)?)?)(?:\.\d+)?(?: ([ap]m))?)?#i;
		($year, $month, $day) = $date =~ m#(\d+)-(\d+)-(\d+)#;
	} elsif ($unabbr =~ /^\d+\//) {
		($date, $time, $meridian) = $unabbr =~ m#^(\d+/\d+/\d+)(?: (\d+(?::\d+(?::\d+)?)?)(?:\.\d+)?(?: ([ap]m))?)?#i;
		($month, $day, $year) = $date =~ m#(\d+)/(\d+)/(\d+)#;
	}
	
	$year = cleanYear($year);
	if ($year) {
		if ($month < 1) { $month = 1; }
		elsif ($month > 12) { $month = 12; }
		my $dom = $self->daysInMonth($year, $month);
		if ($day < 1) { $day = 1; }
		elsif ($day > $dom) { $day = $dom; }
	} elsif (($args->{default} eq 'today') || ($args->{default} eq 'now')) {
		$year = $dt->year;
		$month = $dt->month;
		$day = $dt->day;
	}
	
	if ($args->{time}) {
		$time = unabbrDate($args->{time});
	}
	$meridian ||= $args->{meridian};
	my $ft;
	my ($hour, $minute, $second);
	if ($time =~ /^\d+(?::\d+(?::\d+)?)?/) {
		my $mer;
		if ($time =~ /[ap]m/i) { $mer = lc($1); }
		($hour, $minute, $second) = split(':', $time);
		$meridian ||= $mer;
		$hour = $self->convert12To24($hour, $meridian);
		if ($hour < 1) { $hour = 0; }
		elsif ($hour > 23) { $hour = 23; }
		if ($minute < 1) { $minute = 0; }
		elsif ($minute > 59) { $minute = 59; }
		if ($second < 1) { $second = 0; }
		elsif ($second > 59) { $second = 59; }
	} elsif ($args->{default} eq 'now') {
		$hour = $dt->hour;
		$minute = $dt->minute;
		$second = $dt->second;
	}
	
	if (defined($hour)) {
		eval {
			$ft = DateTime->new(
				year	=> $year,
				month	=> $month,
				day		=> $day,
				hour	=> $hour,
				minute	=> $minute,
				second	=> $second,
				time_zone => $self->{timeZone}
			);
		};
		if ($@) { return; }
	} elsif (defined($month)) {
		$ft = DateTime->new(
			year	=> $year,
			month	=> $month,
			day		=> $day
		);
	}
	
	return $ft;
}

#=====================================================

=head2 B<convert24To12>

 my ($hour, $meridian) = $date->convert24To12($hour);

=cut
#=====================================================
sub convert24To12 {
	my $self = shift || return;
	my $hour = shift;
	
	my $meridian = 'am';
	if ($hour >= 12) { $meridian = 'pm'; }
	if ($hour == 0) { $hour = 12; }
	elsif ($hour > 12) { $hour -= 12; }
	return ($hour, $meridian);
}

#=====================================================

=head2 B<convert12To24>

 my $hour = $date->convert12To24($hour, $meridian);

=cut
#=====================================================
sub convert12To24 {
	my $self = shift || return;
	my $hour = shift;
	my $meridian = lc(shift);
	
	if (($hour >= 1) && ($hour <= 12) && $meridian) {
		if ($meridian eq 'pm') {
			if ($hour < 12) { $hour += 12; }
		} elsif ($hour == 12) { $hour = 0; }
	}
	
	return $hour;
}

#=====================================================

=head2 B<compare>

=cut
#=====================================================
sub compare {
	my $self = shift || return;
	my $a = shift || return;
	my $b = shift || return;
	
	my $at = $self->getTime( { date => $a } );
	my $bt = $self->getTime( { date => $b } );
	
	my $answer = DateTime->compare($at, $bt);
	return $answer;
}

#=====================================================

=head2 B<nextDate>

=cut
#=====================================================
sub nextDate {
	my $self = shift || return;
	my @dates = compressRef(@_);
	my $dt = DateTime->now( time_zone => $self->{timeZone} );
	my $mt;
	foreach my $date (@dates) {
		my $ct = $self->getTime( { date => $date } );
		if (DateTime->compare($dt, $ct) < 0) {
			if ($mt) {
				if (DateTime->compare($mt, $ct) > 0) { $mt = $ct; }
			} else { $mt = $ct; }
		}
	}
	my $nextDate;
	if ($mt) { $nextDate = $mt->ymd . ' ' . $mt->hms; }
	return $nextDate;
}

#=====================================================

=head2 B<sortByDate>

=cut
#=====================================================
sub sortByDate {
	my $self = shift || return;
	my @dates = compressRef(@_);
	my @sortedDates = sort byDate @dates;
	return @sortedDates;
}

#=====================================================

=head2 B<byDate>

=cut
#=====================================================
sub byDate {
	my $date = SitemasonPl::Date->new;
	return $date->compare($a, $b);
}

#=====================================================

=head2 B<now>

=cut
#=====================================================
sub now {
	my $self = shift || return;
	my $dt = DateTime->now( time_zone => $self->{timeZone} );
	return $dt->ymd . ' ' . $dt->hms;
}














#== _checkDates =====================================

=head2 B<_checkDates>

Internal method for verifying timestamps before saving them to the database.

($year, $month, $day, $hour, $minute) = _checkDates($year, $month, $day, $hour, $minute);

=cut
#=====================================================
sub _checkDates {
	my ($cyear, $cmonth, $cday) = (localtime())[5,4,3];
	$cyear += 1900;
	$cmonth++;
	
	my $year = shift || $cyear;
	my $month = shift || $cmonth;
	my $day = shift || $cday;
	my $hour = shift;
	my $minute = shift;
	
	if ($year < -4713) { $year = -4713; }
	if ($year > 1465001) { $year = 1465001; }
	if ($month < 1) { $month = 1; }
	if ($month > 12) { $month = 12; }
	if ($day < 1) { $day = 1; }
	if ($day > 31) { $day = 31; }
	if ($hour < 0) { $hour = 0; }
	if ($hour > 23) { $hour = 23; }
	if ($minute < 0) { $minute = 0; }
	if ($minute > 59) { $minute = 59; }
	
	return($year, $month, $day, $hour, $minute);
}


#=====================================================

=head2 B<convertDatetimeForDisplay>

 my $datetime = $date->convertDatetimeForDisplay($datetime, $timeZone);

=cut
#=====================================================
sub convertDatetimeForDisplay {
	my $self = shift || return;
	my $datetime = shift || return;
	my $timeZone = shift;
	
	my ($date, $time, $meridian) = split(' ', $datetime);
	my ($year, $month, $day, $tz);
	if ($date =~ /^(\d{4})\-(\d{1,2})\-(\d{1,2})$/) {
		$year = $1; $month = $2; $day = $3;
		$date = sprintf("%d/%d/%d", $month, $day, $year);
	}
	if (!$meridian && ($time =~ /^(\d{1,2}):(\d{2})(?::\d{2})?$/)) {
		my $hour = $1;
		my $min = $2;
		($hour, $meridian) = $self->convert24To12($hour);
		if ($timeZone) {
			my $dt;
			eval {
				$dt = DateTime->new(
					year	=> $year,
					month	=> $month,
					day		=> $day,
					hour	=> $hour,
					minute	=> $min,
					time_zone => $timeZone
				);
			};
			if ($@) { return; }
			$tz = ' ' . $dt->time_zone_short_name;
		}
		$time = sprintf("%d:%02d", $hour, $min);
	}
	my $dateDisplay = $date;
	my $timeDisplay;
	if ($time) { $timeDisplay = $time . ' ' . $meridian . $tz; }
	return ($dateDisplay, $timeDisplay);
}


#=====================================================

=head2 B<buildDateSummary>

 my $time = {
	startTime			=> '2006-09-21 14:00',
	endTime			=> '2006-09-21 15:00',
	isAllDay			=> 0,	# unused
	repeatFreq			=> 'weekly', # daily, weekly, monthly, yearly
	repeatCount		=> 10,
	repeatInterval		=> 1,
	repeatByDay		=> 'SU MO',
	repeatByMonth		=> ?,
	repeatByMonthDay	=> 2,
	repeatUntil		=> '2007-09-21'
 }
 
 my ($summary, $repeatSummary) = $date->buildDateSummary($time, $timeZone);

=cut
#=====================================================
sub buildDateSummary {
	my $self = shift || return;
	my $time = shift || return;
	my $timeZone = shift;
	
	if ($timeZone eq $self->{timeZone}) { undef($timeZone); }
	
	my $summary;
	if ($time->{startTime} && !$time->{startTimeDisplay}) {
		($time->{startDateDisplay}, $time->{startTimeDisplay}) = $self->convertDatetimeForDisplay($time->{startTime}, $timeZone);
	}
	if ($time->{endTime} && !$time->{endTimeDisplay}) {
		($time->{endDateDisplay}, $time->{endTimeDisplay}) = $self->convertDatetimeForDisplay($time->{endTime}, $timeZone);
	}
	my ($startTime, $startTz) = $time->{startTimeDisplay} =~ /^(.+? \w+)(?: (\w+))?$/;
	my ($endTime, $endTz) = $time->{endTimeDisplay} =~ /^(.+? \w+)(?: (\w+))?$/;
	if (($startTz eq $endTz) && ($startTime ne $endTime)) { $summary = $time->{startDateDisplay} . ' ' . $startTime; }
	else { $summary = $time->{startDateDisplay} . ' ' . $time->{startTimeDisplay}; }
	if ($time->{endTimeDisplay}) {
		if ($time->{endDateDisplay} eq $time->{startDateDisplay}) {
			if ($endTime && ($endTime ne $startTime)) {
				$summary .= ' - ' . $time->{endTimeDisplay};
			}
		} else {
			$summary .= ' - ' . $time->{endDateDisplay} . ' ' . $time->{endTimeDisplay};
		}
	}
	
	my $summary2;
	if ($time->{repeatFreq}) {
		$time->{repeatInterval} ||= 1;
		my $freq;
		if ($time->{repeatFreq} eq 'daily') { $freq = 'day'; }
		elsif ($time->{repeatFreq} eq 'weekly') { $freq = 'week'; }
		elsif ($time->{repeatFreq} eq 'monthly') { $freq = 'month'; }
		elsif ($time->{repeatFreq} eq 'yearly') { $freq = 'year'; }
		if ($time->{repeatInterval} == 1) {
			$summary2 = ' every ' . $freq;
		} elsif ($time->{repeatInterval} == 2) {
			$summary2 = ' every other ' . $freq;
		} else {
			$summary2 = ' every ' . $time->{repeatInterval} . ' ' . $freq . 's';
		}
		
		if ($freq eq 'week') {
			if ($time->{repeatByDay}) {
				my @daysList;
				my $days = $time->{repeatByDay};
				my $weekend = 0;
				if ($days =~ /\bSU\b/) { push(@daysList, 'Sunday'); $weekend++; }
				if ($days =~ /\bMO\b/) { push(@daysList, 'Monday'); }
				if ($days =~ /\bTU\b/) { push(@daysList, 'Tuesday'); }
				if ($days =~ /\bWE\b/) { push(@daysList, 'Wednesday'); }
				if ($days =~ /\bTH\b/) { push(@daysList, 'Thursday'); }
				if ($days =~ /\bFR\b/) { push(@daysList, 'Friday'); }
				if ($days =~ /\bSA\b/) { push(@daysList, 'Saturday'); $weekend++; }
				if ($summary2 eq ' every week') {
					if (@daysList == 7) {
						$summary2 = ' every day of the week';
					} elsif ((@daysList == 5) && !$weekend) {
						$summary2 = ' every weekday';
					} elsif (@daysList) {
						$summary2 = ' ' . makeList(\@daysList, 1);
					}
				} else {
					if (@daysList == 7) {
						$summary2 .= ' on every day of the week';
					} elsif ((@daysList == 5) && !$weekend) {
						$summary2 .= ' on weekdays';
					} elsif (@daysList) {
						$summary2 .= ' on ' . makeList(\@daysList);
					}
				}
			}
		} elsif ($freq eq 'month') {
			my $summaryFreq = $summary2;
			if ($time->{repeatByDay}) {
				my ($ord, $day) = $time->{repeatByDay} =~ /(-?\d)(SU|MO|TU|WE|TH|FR|SA)\b/;
				if ($day) {
					if ($ord == -1) { $summary2 = ' on the last'; }
					elsif ($ord == 1) { $summary2 = ' on the first'; }
					elsif ($ord == 2) { $summary2 = ' on the second'; }
					elsif ($ord == 3) { $summary2 = ' on the third'; }
					elsif ($ord == 4) { $summary2 = ' on the fourth'; }
					if ($day eq 'SU') { $summary2 .= ' Sunday'; }
					elsif ($day eq 'MO') { $summary2 .= ' Monday'; }
					elsif ($day eq 'TU') { $summary2 .= ' Tuesday'; }
					elsif ($day eq 'WE') { $summary2 .= ' Wednesday'; }
					elsif ($day eq 'TH') { $summary2 .= ' Thursday'; }
					elsif ($day eq 'FR') { $summary2 .= ' Friday'; }
					elsif ($day eq 'SA') { $summary2 .= ' Saturday'; }
					$summary2 .= ' of' . $summaryFreq ;
				}
			} elsif ($time->{repeatByMonthDay} == '-1') {
				$summary2 = ' on the last day of' . $summaryFreq;
			}
		} elsif ($freq eq 'year') {
			if ($time->{repeatByDay}) {
				my ($ord, $day) = $time->{repeatByDay} =~ /(-?\d)(SU|MO|TU|WE|TH|FR|SA)\b/;
				if ($day) {
					if ($ord == -1) { $summary2 .= ' on the last'; }
					elsif ($ord == 1) { $summary2 .= ' on the first'; }
					elsif ($ord == 2) { $summary2 .= ' on the second'; }
					elsif ($ord == 3) { $summary2 .= ' on the third'; }
					elsif ($ord == 4) { $summary2 .= ' on the fourth'; }
					if ($day eq 'SU') { $summary2 .= ' Sunday'; }
					elsif ($day eq 'MO') { $summary2 .= ' Monday'; }
					elsif ($day eq 'TU') { $summary2 .= ' Tuesday'; }
					elsif ($day eq 'WE') { $summary2 .= ' Wednesday'; }
					elsif ($day eq 'TH') { $summary2 .= ' Thursday'; }
					elsif ($day eq 'FR') { $summary2 .= ' Friday'; }
					elsif ($day eq 'SA') { $summary2 .= ' Saturday'; }
				}
			} elsif ($time->{repeatByMonthDay} == '-1') {
				$summary2 .= ' on the last day';
			} else {
				my ($ordinal) = $time->{startDateDisplay} =~ /^\d+\/(\d+)\//;
				if (($ordinal % 10) == 1) { $ordinal .= 'st'; }
				elsif (($ordinal % 10) == 2) { $ordinal .= 'nd'; }
				elsif (($ordinal % 10) == 3) { $ordinal .= 'rd'; }
				else { $ordinal .= 'th'; }
				$summary2 .= ' on the ' . $ordinal;
			}
			my @months = loadMonths();
			my @byMonth = sort { $a <=> $b } (split(',', $time->{repeatByMonth}));
			my @monthList;
			foreach my $byMonth (@byMonth) {
				if ($months[$byMonth-1]) { push(@monthList, $months[$byMonth-1]); }
			}
			if (@monthList == 12) {
				$summary2 .= ' of every month of the year';
			} elsif (@monthList) {
				$summary2 .= ' of ' . makeList(\@monthList);
			}
		}
		
		if ($time->{repeatCount} == 1) {
			$summary2 .= ' for 1 time';
		} elsif ($time->{repeatCount}) {
			$summary2 .= ' for ' . $time->{repeatCount} . ' times';
		} elsif ($time->{repeatUntil}) {
			if ($time->{repeatUntil} && !$time->{repeatUntilDisplay}) {
				($time->{repeatUntilDisplay}) = $self->convertDatetimeForDisplay($time->{repeatUntil}, $timeZone);
			}
			$summary2 .= ' until ' . $time->{repeatUntilDisplay};
		} else {
			$summary2 .= ' forever';
		}
		
		if ($summary2) {
			$summary2 = 'repeats' . $summary2;
		}
	}
	
	return ($summary, $summary2);
}


#=====================================================

=head2 B<makeList>

=cut
#=====================================================
sub makeList {
	my $list = shift || return;
	my $plural = shift;
	
	if ($plural) {
		for (my $i = 0; $i < @{$list}; $i++) {
			$list->[$i] .= 's';
		}
	}
	
	if ($list && @{$list}) {
		my $string;
		my $length = @{$list};
		if ($length > 2) {
			my $last = pop(@{$list});
			$string = join(', ', @{$list});
			$string .= ', and ' . $last;
		} elsif ($length == 2) {
			$string = $list->[0] . ' and ' . $list->[1];
		} elsif ($length == 1) {
			$string = $list->[0];
		}
		return $string;
	}
	return;
}

sub cleanOrdinal {
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

sub cleanDay {
	my $dirty = shift;
	my ($day) = $dirty =~ /(?:^|\D)(30|31|[1-2][0-9]|0?[1-9])(?:$|\D)/;
	unless ($day) { undef($day); }
	return $day;
}

sub cleanWeekday {
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

sub cleanMonth {
	my $dirty = shift;
	my $month;
	if ($dirty =~ /(January|February|March|April|May|June|July|August|September|October|November|December)/i) {
		my $tmp = $1;
		my @months = loadMonths();
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

sub cleanYear {
	my $dirty = shift;
	my ($year) = $dirty =~ /(\d+)/;
	unless (($year > 1) && ($year <= 9999)) { undef($year); }
	elsif ($year < 30) { $year += 2000; }
	elsif ($year < 100) { $year += 1900; }
	return $year;
}

sub fillYear {
	my $month = shift;
	my $day = shift;
	my $ctime = currentTime();
	my $year = $ctime->{year};
	if (($month == $ctime->{month}) && ($day < $ctime->{day})) { $year++; }
	if ($month < $ctime->{month}) { $year++; }
	return $year;
}

sub currentTime {
	my $time;
		($time->{second},$time->{minute},$time->{hour},$time->{mday},$time->{month},$time->{year},$time->{wday}) = gmtime(time);
	$time->{month}++; $time->{year} += 1900;
	return $time;
}

sub unabbrDate {
	my $search = shift;
	
	my $abbr = loadAbbr();
	my @months = loadMonths();
	my ($clean) = $search =~ /\s*(.+?)\s*$/s;
	$clean =~ s/\b(\d+(?::\d\d)?)\s*(?:\-|to|thru|through)\s*(\d+(?::\d\d)?\s*([ap])\.?m(?:\.|\b))/$1 ${3}m-$2/ig;
 	$clean =~ s/\b(\d+(?::\d\d)?)\s*(?:and|&|;|\|)\s*(\d+(?::\d\d)?\s*([ap])\.?m(?:\.|\b))/$1 ${3}m,$2/ig;
	$clean =~ s/\b(?:noon\b|mid\-?day\b|12(:00)?\s*p\.?m(?:\.|\b))/12:00/ig;
	$clean =~ s/\b(?:mid\-?night\b|mid\-?nite\b|12(:00)?\s*1\.?m(?:\.|\b))/0:00/ig;
	$clean =~ s/\b(\d+)(:\d\d)?\s*a\.?m(?:\.|\b)/$1.($2 || ':00')/eig;
	$clean =~ s/\b(\d+)(:\d\d)?\s*p\.?m(?:\.|\b)/($1+12).($2 || ':00')/eig;
	$clean =~ s/\bst(?:\.|\b)/Saint/ig;
	$clean =~ s/\bft(?:\.|\b)/Fort/ig;
	foreach my $check (@{$abbr}) {
		$clean =~ s/$check->{match}/$check->{replace}/ig;
	}
	return $clean;
}

sub loadMonths {
	return qw(January February March April May June July August September October November December);
}

sub loadWeekDays {
	return qw(Sunday Monday Tuesday Wednesday Thursday Friday Saturday);
}

sub weekdayAbbrToNumber {
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

sub loadAbbr {
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

  20050627 TJM - v0.01 started development as MLI::System::Calendar
  20060921 TJM - v0.02 started development as Sitemason::System::Date
  20120105 TJM - v6.0 moved from Sitemason::System to Sitemason7::Library
  20171109 TJM - v8.0 Moved to SitemasonPL open source project and merged with updates

=head1 AUTHOR

  Tim Moses <tim@moses.com>
  Sitemason Open Source <https://github.com/sitemason>

=cut

1;
