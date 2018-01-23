package SitemasonPl::Debug 8.0;

=head1 NAME

SitemasonPl::Debug

=head1 DESCRIPTION

Debug contains timer, logging, and Leftronic dashboard functions.

=head1 METHODS

=cut


use v5.012;
use strict;
use utf8;
use constant TRUE => 1;
use constant FALSE => 0;

use Benchmark::Timer;
use SitemasonPl::Common;
use SitemasonPl::Database;


#=====================================================

=head2 B<new>

 $self->{debug} = Sitemason::Debug->new({
 	logLevel	=> 'debug',		# log items with matching tags of this level or higher
 	logLevelAll	=> 'notice',	# log all items of this level or higher
 	logTags		=> []
 });

=cut
#=====================================================
sub new {
	my ($class, %arg) = @_;
	$class || return;
	
	my $self = {
		locale		=> $arg{locale},
		logLevel	=> $arg{logLevel} || 'debug',
		logLevelAll	=> $arg{logLevelAll} || 'debug',
		logTags		=> $arg{logTags},
		client		=> $arg{client},
		errors		=> []
	};
	if (!is_array($arg{logTags})) { $self->{logTags} = [$arg{logTags}]; }
	if ($arg{indent}) { $self->{indent} = '    '; }
	if ($arg{label}) { $self->{timerArgs}->{label} = $arg{label}; }
	if (defined($arg{header}) && !$arg{header}) { $self->{header} = FALSE; }
	
	bless $self, $class;
	$self->{logLevelNum} = $self->_convertToErrorNum($self->{logLevel});
	$self->{logLevelAllNum} = $self->_convertToErrorNum($self->{logLevelAll});
	
	$self->{startTime} = $self->_getLogTime;
	
	if ($arg{req}) {
		$self->{client}->{ip} = $arg{req}->headers_in->{'x-forwarded-for'};
	}
	
	$self->{boldStart} = $self->{boldEnd} = '';
	if (($ENV{TERM} && ($ENV{TERM} ne 'dumb') && ($ENV{TERM} ne 'tty')) || $ENV{SSH_AUTH_SOCK}) {
		$ENV{TERM} ||= 'xterm-256color';
		$self->{isPerson} = TRUE;
		if ($ENV{TERM} && ($ENV{TERM} ne 'dumb') && ($ENV{TERM} ne 'tty')) {
			$self->{boldStart} = "\e[1m";
			$self->{boldEnd} = "\e[m";
			
			$self->{term} = {
				reset			=> "\e[m",	# yes
				bold			=> "\e[1m",	# yes
				faint			=> "\e[2m",	# yes
				italic			=> "\e[3m",
				underline		=> "\e[4m",	# yes
				blink			=> "\e[5m",	# yes
				rapid			=> "\e[6m",
				inverse			=> "\e[7m",	# yes
				conceal			=> "\e[8m",	# yes
				crossed			=> "\e[9m",
				
				boldOff			=> "\e[21m",
				faintOff		=> "\e[22m",
				italicOff		=> "\e[23m",
				underlineOff	=> "\e[24m",
				blinkOff		=> "\e[25m",
				inverseOff		=> "\e[27m",
				concealOff		=> "\e[28m",
				crossedOff		=> "\e[29m",
				
				black			=> "\e[30m",
				red				=> "\e[31m",
				green			=> "\e[32m",
				yellow			=> "\e[33m",
				blue			=> "\e[34m",
				magenta			=> "\e[35m",
				cyan			=> "\e[36m",
				white			=> "\e[37m",
				default			=> "\e[39m",
				onBlack			=> "\e[30m",
				onRed			=> "\e[31m",
				onGreen			=> "\e[32m",
				onYellow		=> "\e[33m",
				onBlue			=> "\e[34m",
				onMagenta		=> "\e[35m",
				onCyan			=> "\e[36m",
				onWhite			=> "\e[37m",
				onDefault		=> "\e[39m",
				
				blackHigh		=> "\e[90m",
				redHigh			=> "\e[91m",
				greenHigh		=> "\e[92m",
				yellowHigh		=> "\e[93m",
				blueHigh		=> "\e[94m",
				magentaHigh		=> "\e[95m",
				cyanHigh		=> "\e[96m",
				whiteHigh		=> "\e[97m",
				onBlackHigh		=> "\e[100m",
				onRedHigh		=> "\e[101m",
				onGreenHigh		=> "\e[102m",
				onYellowHigh	=> "\e[103m",
				onBlueHigh		=> "\e[104m",
				onMagentaHigh	=> "\e[105m",
				onCyanHigh		=> "\e[106m",
				onWhiteHigh		=> "\e[107m",
			};
		}
	}
	
	return $self;
}

#=====================================================
#
# Timer functions
#
#=====================================================

=head2 B<timerInit>

 $self->{debug}->timerInit;

=cut
#=====================================================
sub init_timer { return timerInit(@_); }
sub timerInit {
	my $self = shift || return;
	my $args = shift;
	
	unless ($self->{timerArgs}->{suppress}) {
		my $time = $self->_getLogTime;
		
		my $info = $self->{timerArgs}->{label};
		unless ($info) {
			$info = (caller(1))[3];
			$info =~ /::new$/;
		}
# 		my $ipInfo;
# 		if ($self->{client}->{ip}) {
# 			$ipInfo = ' [' . $self->{client}->{ip} . ']';
# 		}
# 		
# 		print STDERR "[$time] [info]$ipInfo $info\n";
	}
	unless ($self->{timer}) {
		$self->{timer} = Benchmark::Timer->new();
		$self->{timerList} = [];
		$self->{isTimingStarted} = TRUE;
		$self->{timerArgs} = $args;
		$self->{activeTimers} = {};
		$self->timerStart('full');
	}
}


#=====================================================

=head2 B<timerStart>

 $self->{debug}->timerStart('tag');

=cut
#=====================================================
sub timer_start { return timerStart(@_); }
sub timerStart {
	my $self = shift || return;
	my $tag = shift || return;
	$self->{isDisabled} && return;
	$self->{timer} || return;
	if ($self->{activeTimers}->{$tag}) { return; }
	$self->{timer}->start($tag);
	$self->{activeTimers}->{$tag} = TRUE;
}


#=====================================================

=head2 B<timerStop>

 my $seconds = $self->{debug}->timerStop('tag');
 
=cut
#=====================================================
sub timer_stop { return timerStop(@_); }
sub timerStop {
	my $self = shift || return;
	my $tag = shift || return;
	$self->{timer} || return;
	if (!$self->{activeTimers}->{$tag}) { return; }
	my $duration = $self->{timer}->stop($tag);
	$self->{timers}->{$tag}->{duration} += $duration;
	$self->{timers}->{$tag}->{count}++;
	delete $self->{activeTimers}->{$tag};
	return round($duration, 3);
}


#=====================================================

=head2 B<timerPrint>

 $self->{debug}->timerPrint('tag');

=cut
#=====================================================
sub timerPrint {
	my $self = shift || return;
	my $tag = shift;
	my $seconds = $self->timerStop($tag);
	
	$self->post({ level => 'debug', message => "Timer '$tag' - $seconds s", tags => [$tag, 'timer'], start => 1 });
	return $seconds;
}


#=====================================================

=head2 B<timerResult>

=cut
#=====================================================
sub timerResult {
	my $self = shift || return;
	my $tag = shift || 'full';
	my $total = $self->{timer}->result($tag);
	return round($total, 2);
}

#=====================================================

=head2 B<timerResults>

Prints to STDERR the timer results stored in $self->{timer}. This should be the last thing an app calls before returning.

 my $fullSeconds = $self->{debug}->timerResults;

=cut
#=====================================================
sub timer_results { return timerResults(@_); }
sub timerResults {
	my $self = shift || return;
	my $message = shift;
	my $req;
	if (is_object($message)) { $req = $message; undef $message; }
	$self->{timer} || return;
	my $threshold = $self->{locale}->{timer_threshold} || 4;
	my $testThreshold = $self->{locale}->{test_threshold};
	
	unless ($self->{isTimingStarted}) {
		return '0';
	}
	
	$self->timerStop('full');
	$self->{isTimingStarted} = 0;
	if ($self->{timerArgs}->{suppress}) { return; }
	my $time = $self->_getLogTime;
	if ($self->{startTime}) { $time = $self->{startTime} . " - $time"; }
	
	my $full = $self->timerResult;
	
	my $info = $self->{timerArgs}->{label};
	unless ($info) {
		if ($self->{timerArgs}->{is_admin}) {
			$info = "members $self->{timerArgs}->{user_id} ($self->{timerArgs}->{power_user_id}) /$self->{timerArgs}->{element_name}";
			if ($self->{timerArgs}->{element_id_enc}) { $info .= "/$self->{timerArgs}->{element_id_enc}"; }
		} elsif ($self->{timerArgs}->{id_enc}) {
			$info = "$self->{timerArgs}->{id_enc} $self->{timerArgs}->{user_id} $self->{timerArgs}->{url}";
		} else {
			$info = (caller(1))[3];
			$info =~ /::\w+$/;
		}
	}
	$info .= ' - ';
	if ($message) { $info .= $message . ' - '; }
	my $ipInfo;
	if ($self->{client}->{ip}) {
		$ipInfo = ' [' . $self->{client}->{ip} . ']';
	} elsif ($req) {
		my $ip = $req->headers_in->{'x-forwarded-for'};
		$ipInfo = " [$ip]";
	}
	
	print STDERR "[$time] [info]$ipInfo $info - ${full}s\n";
	if ($self->{timerArgs}->{display_full} || ($full > $threshold) || ($self->{timerArgs}->{id} && ($self->{timerArgs}->{id} == $self->{locale}->{test_instance_id}))) {
		my $results = $self->{timer}->results;
		
		my $max;
		my $name;
		foreach (@{$results}) {
			if ($name) { undef $name; }
			else { $name = $_; if (length($name) >= $max) { $max = length($name); } }
		}
		foreach (@{$results}) {
			if ($name) {
				if (($_ > $testThreshold) || ($self->{timerArgs}->{id} && ($self->{timerArgs}->{id} == $self->{locale}->{test_instance_id}))) {
					my $duration = $_;
					my $count;
					if ($self->{timers}->{$name}->{duration}) { $duration = $self->{timers}->{$name}->{duration}; }
					if ($self->{timers}->{$name}->{count}) { $count = $self->{timers}->{$name}->{count}; }
					my $out = sprintf("      %-${max}s : % 9.5f  %8d", $name, $duration, $count);
					print STDERR "$out\n";
					undef $name;
				}
			} else {
				$name = $_;
			}
		}
	}
	return $full;
}


#=====================================================

=head2 B<timerSet>

=cut
#=====================================================
sub timerSet {
	my $self = shift || return;
	my $name = shift || return;
	my $value = shift;
	
	if ($name =~ /^(?:label|message)$/) {
		$self->{timerArgs}->{$name} = $value;
	}
}


#=====================================================

=head2 B<timerDisable>

=cut
#=====================================================
sub timerDisable {
	my $self = shift || return;
	$self->{isDisabled} = TRUE;
}



#=====================================================
#
# Logging functions
#
#=====================================================

=head2 B<_convertToErrorNum>

 my $errorNum = $self->_convertToErrorNum($level);

=cut
#=====================================================
sub _convertToErrorNum {
	my $self = shift || return;
	my $level = shift || return;
	
	# Error that could take down the system or a serious hack event
	if ($level eq 'emergency') { return 7; }
	# Major code bug that should be addressed promptly or minor hack event
	elsif ($level eq 'alert') { return 6; }
	# Minor code bug. Add to bug labs
	elsif ($level eq 'critical') { return 5; }
	# Major error for user, like denial based on permissions
	elsif ($level eq 'error') { return 4; }
	# Correctible error for user, like bad input
	elsif ($level eq 'warning') { return 3; }
	# Notice message for user
	elsif ($level eq 'notice') { return 2; }
	# Short messages showing status or location in code
	elsif ($level eq 'info') { return 1; }
	# All the details, like SQL statements or XML output
	elsif ($level eq 'debug') { return 0; }
}


#=====================================================

=head2 B<post>

 $self->{debug}->post( {
 	caller		=> [caller(0)],
 	level		=> 'critical',	# required, one of eight levels, see below
 	message		=> "This field is an unknown type.",	#required, this is the error message
 	tags		=> 'sql'		# string or array of tags
 	header		=> FALSE,		# displays header; defaults to TRUE
 	indent		=> '    ',		# text to put before the message
 	output		=> 'STDOUT'		# sets the output handler, defaults to STDERR
 } );

 $self->{debug}->post({ level => 'warning', message => "Error", fullCaller => 1 });

Possible levels are as follows:

	emergency - Error that could take down the system or a serious hack event
	alert - Major code bug that should be addressed promptly or minor hack event
	critical - Minor code bug. Add to bug labs. Ha ha.
	error - Major error for user, like denial based on permissions
	warning - Correctible error for user, like bad input
	notice - Notice message for user
	info - Short messages showing status or location in code
	debug - All the details, like SQL statements or XML output

=cut
#=====================================================
sub post {
	my $self = shift || return;
	my $error = shift || return;
	my $start = $error->{start} || 0;
	
	my $outputHandler = \*STDERR;
	if (lc($error->{output}) eq 'stdout') { $outputHandler = \*STDOUT; }
	
	$error->{levelNum} = $self->_convertToErrorNum($error->{level});
	
	if ($error->{tags} && !is_array($error->{tags})) { $error->{tags} = [$error->{tags}]; }
	
	my ($line) = (caller($start))[2]; $start++;
	my ($package, $parentLine) = (caller($start))[3,2]; $start++;
	my ($parent) = (caller($start))[3];
	my $drawHeader = 1;
	if ($error->{fullCaller} || $error->{full_caller}) {
		my $cnt = 0;
		while ((caller($cnt))[0]) {
			if ($cnt > 12) { last; }
			$error->{location} .= "\n$cnt - " . (caller($cnt))[0] . ' (' . (caller($cnt))[2] . ') -> ' . (caller($cnt))[3];
			$cnt++;
		}
	} elsif ($error->{caller}) {
		$error->{location} = "$error->{caller}->[0] ($error->{caller}->[2]) -> $error->{caller}->[3] ($line)";
	} else {
		$error->{location} = "$parent ($parentLine) -> $package ($line)";
	}
	
	if ($package) {
		my @tags = split('::', $package);
		push(@{$error->{tags}}, @tags);
	}
	
	if ($error->{level}) { push(@{$error->{tags}}, $error->{level}); }
	
	my $shouldPrint;
#	print STDERR "$error->{levelNum}, $self->{logLevelNum}, $self->{logLevelAllNum}\n";
	if ($error->{levelNum} >= $self->{logLevelNum}) {
		if (($error->{levelNum} >= $self->{logLevelAllNum}) || ($self->_includeStatus($error->{tags}, $self->{logTags}))) {
			my $lastCaller;
			my $drawHeader = TRUE;
			if (defined($self->{header}) && !$self->{header}) {
				$drawHeader = FALSE;
			} elsif (defined($error->{header}) && !$error->{header}) {
				$drawHeader = FALSE;
			} elsif ($error->{caller}) {
				if ($error->{caller}->[3] eq $self->{lastCaller}) { $drawHeader = FALSE; }
				$lastCaller = $error->{caller}->[3];
			} else {
				if ($package eq $self->{lastCaller}) { $drawHeader = FALSE; }
				$lastCaller = $package;
			}
			
			my $indent = $error->{indent} || $self->{indent};
			if ($drawHeader) {
				my $logTime = $self->_getLogTime;
				print $outputHandler $indent . "[" . $logTime . "] [$error->{level}] $error->{location}";
#				print STDERR "\n" . $indent . '  ' . join(', ', @{$error->{tags}});
				if (($error->{message} =~ /\n/) || !$error->{line}) { print $outputHandler "\n"; }
			}
			$self->{lastLocation} = $error->{location};
			
			my $message = $self->adjustPlurals($error->{message});
			if ($error->{levelNum} >= 3) { $message = $self->{boldStart} . $message . $self->{boldEnd}; }
			
			if ($error->{message} =~ /\n/) {
				print $outputHandler $indent . "$message\n";
			} elsif ($error->{line}) {
				print $outputHandler $indent . "  $message\n";
			} elsif ($error->{message}) {
				print $outputHandler $indent . "  $message\n";
			}
			$shouldPrint = TRUE;
			if ($lastCaller) { $self->{lastCaller} = $lastCaller; }
		}
	}
	
	if ($error->{isInternal}) { return $shouldPrint; }
	
# 	push(@{$self->{errors}}, {
# 		level		=> $error->{level},
# 		levelNum	=> $error->{levelNum},
# 		location	=> $error->{location},
# 		message		=> $error->{message},
# 		tags		=> $error->{tags},
# 		duration	=> $error->{duration}
# 	} );
}

sub adjustPlurals {
	my $self = shift || return;
	my $message = shift || return '';
	$message =~ s/\b0E0/0/g;
	$message =~ s/\b(\d+)([a-zA-Z\s]*?\s+)([A-Za-z]*[a-z])S\b/"$1$2" . pluralize($3, $1)/eg;
	return $message;
}

sub emergency {
	my $self = shift || return; my $message = shift || return; my $args = shift;
	$self->post( new_hash({ level => 'emergency', message => $message, start => 1 }, $args) );
}

sub alert {
	my $self = shift || return; my $message = shift || return; my $args = shift;
	$self->post( new_hash({ level => 'alert', message => $message, start => 1 }, $args) );
}

sub critical {
	my $self = shift || return; my $message = shift || return; my $args = shift;
	$self->post( new_hash({ level => 'critical', message => $message, start => 1 }, $args) );
}

sub error {
	my $self = shift || return; my $message = shift || return; my $args = shift;
	$self->post( new_hash({ level => 'error', message => $message, start => 1 }, $args) );
}

sub warning {
	my $self = shift || return; my $message = shift || return; my $args = shift;
	$self->post( new_hash({ level => 'warning', message => $message, start => 1 }, $args) );
}

sub notice {
	my $self = shift || return; my $message = shift || return; my $args = shift;
	$self->post( new_hash({ level => 'notice', message => $message, start => 1 }, $args) );
}

sub info {
	my $self = shift || return; my $message = shift || return; my $args = shift;
	$self->post( new_hash({ level => 'info', message => $message, start => 1 }, $args) );
}

sub debug {
	my $self = shift || return; my $message = shift || return; my $args = shift;
	$self->post( new_hash({ level => 'debug', message => $message, start => 1 }, $args) );
}

#=====================================================

=head2 B<printList>

=cut
#=====================================================
sub printList {
	my $self = shift || return;
	my $array = shift;
	my $header = shift;
	my $args = shift;
	is_array($array) || return;
	
	my $max = $header;
	foreach my $item (@{$array}) {
		if (length($item) > length($max)) { $max = $item; }
	}
	my $width = length($max) + 2;
	my $content = '=' x $width . "\n";
	if ($header) {
		$content .= $self->{boldStart} . $header . $self->{boldEnd} . "\n" . '-' x $width . "\n";
	}
	$content .= '  ' . join("\n  ", @{$array}) . "\n";
	$content .= '=' x $width;
	$self->post( new_hash({ level => 'info', message => $content, start => 1 }, $args) );
}




sub call {
	my $self = shift || return;
	my $level = shift || 'debug';
	my ($package) = (caller(1))[3];
	
	my $tags = ['call'];
	if (($package !~ /::_init$/) && ($package =~ /::_\w+$/)) { push(@{$tags}, 'privateMethod'); }
	else { push(@{$tags}, 'publicMethod'); }
	
	$self->post( {
		start		=> 1,
		level		=> $level,
		tags		=> $tags
	} );
}



#=====================================================

=head2 B<getStatus>

Returns an array of errors of the specified level or above. The optional second argument will further filter to only errors marked with that tag.

 my $status = $self->{debug}->getStatus('critical', $tag);
 if ($self->{debug}->getStatus('info') { return; }

=cut
#=====================================================
sub getStatus {
	my $self = shift || return;
	my $level = shift;
	my $searchTagList = shift;
	if ($searchTagList && (ref($searchTagList) ne 'ARRAY')) { $searchTagList = [$searchTagList]; }
	
	my $errorNum;
	if ($level =~ /^\d$/) { $errorNum = $level; }
	else { $errorNum = $self->_convertToErrorNum($level); }
	
	my $negativeTag;
	my $positiveTag;
	if ($searchTagList && @{$searchTagList}) {
		foreach my $searchTag (@{$searchTagList}) {
			if ($searchTag =~ /^\!/) { $negativeTag = 1; }
			else { $positiveTag = 1; }
		}
	}
	
	my $errorList = [];
	foreach my $error (@{$self->{errors}}) {
		if ($error->{levelNum} >= $errorNum) {
			if ($self->_includeStatus($error->{tags}, $searchTagList)) {
				push(@{$errorList}, $error);
			}
		}
	}
	return $errorList;
}

sub _includeStatus {
	my $self = shift || return;
	my $errorTagList = shift;
	my $searchTagList = shift;
	
	if (is_array_with_content($searchTagList)) {
		foreach my $searchTag (@{$searchTagList}) {
			my $testTag = $searchTag; my $isPos = 1; my $found;
			if ($searchTag =~ /^\!(.+)$/) { $testTag = $1; $isPos = 0; $found = 1; }
			
			if (is_array_with_content($errorTagList)) {
				foreach my $errorTag (@{$errorTagList}) {
					if (!$isPos && ($1 eq $errorTag)) { undef($found); last; }
					elsif ($isPos && ($searchTag eq $errorTag)) { $found = 1; }
				}
			}
			$found || return;
		}
	} else { return; }
	return TRUE;
}


#=====================================================

=head2 B<getMessages>

 my $messages = $self->{debug}->getMessages('debug', ['call', 'publicMethod']);

=cut
#=====================================================
sub getMessages {
	my $self = shift || return;
	my $level = shift;
	my $searchTagList = shift;
	my $status = $self->getStatus($level, $searchTagList);
	my $messageList = [];
	foreach my $item (@{$status}) {
		if ($item->{message}) { push(@{$messageList}, $item->{message}); }
	}
	return $messageList;
}


#=====================================================

=head2 B<getOutput>

 my $output = $self->{debug}->getOutput('debug', ['call', 'publicMethod']);

=cut
#=====================================================
sub getOutput {
	my $self = shift || return;
	my $level = shift;
	my $searchTagList = shift;
	my $status = $self->getStatus($level, $searchTagList);
	my $output = [];
	foreach my $st (@{$status}) {
		push(@{$output}, {
			level		=> $st->{level},
			levelNum	=> $st->{levelNum},
			message		=> $st->{message}
		});
	}
	return $output;
}


#=====================================================

=head2 B<getTrace>

Assumes 'call' tag. First argument should be 'public' or 'all' to show only public methods or all methods. The second argument is an optional list of module folders and names to narrow the list. An array of locations is returned.

 my $locations = $self->{debug}->getTrace(['Sitemason6', 'Library']);

=cut
#=====================================================
sub getTrace {
	my $self = shift || return;
	my $method = shift || 'all';
	my $searchTagList = shift || [];
	if ($method eq 'all') { push(@{$searchTagList}, 'call'); }
	else { push(@{$searchTagList}, 'call', 'publicMethod'); }
	my $status = $self->getStatus('debug', $searchTagList);
	my $locationList = [];
	foreach my $item (@{$status}) {
		if ($item->{location}) {
			my ($caller, $method) = split(' -> ', $item->{location});
			$method =~ s/ \(.*$//;
			push(@{$locationList}, "$method <- $caller");
		}
	}
	return $locationList;
}


#== printObject =====================================

=head2 B<printObject>

Pass a variable and it will spit out its contents and the contents of any hash refs or array refs in it to STDERR.

Simplest version:
	$app->printObject($self->{files}->{views});

There is a second optional argument for printing a label first:
	$app->printObject($self->{files}->{views}, 'Here is the fileView object');

Finally, there is an optional hash of arguments you can pass. 'limit' lets you set how deep it will navigate. It has a default of 5. 'classList' is an array ref of class prefixes that should be navigated. It doesn't navigate classes by default.
	$app->printObject($self->{files}->{views}, 'Here is the fileView object', {
		limit				=> 5,
		suppressParents	=> 1,
		showNulls			=> 1,
		classList	=> [
			'Sitemason::System::File::',
			'Sitemason::System::Data::'
		]
	} );

=cut
#=====================================================
sub print_object { my $self = shift; $self->printObject(@_); }
sub printObject {
	my $self = shift;
	my $data = shift;
	my $header = shift;
	my $options = shift;
	my $limit = $options->{limit} || 5;
	my $depth = shift || 1;
	my $space = ' ' x 13;
	my $tabs = ': . ' x $depth;
	my $indent = $self->{indent};
	
	if ($depth == 1) {
		my $continue = $self->post( {
			start		=> 1,
			level		=> $options->{level} || 'info',
			isInternal	=> TRUE,
			tags		=> $options->{tags}
		} );
		$continue || return;
	}
	
	if (ref($data) eq 'DateTime') {
		printf STDERR ("$header: DateTime: %s %s %s\n", $data->ymd, $data->hms, $data->time_zone_long_name);
		return;
	}
	if (!ref($data)) {
		if (($data+0) eq $data) { print STDERR "$header: $data\n"; }
		elsif (length($data) > 0) { print STDERR "$header: '$data'\n"; }
		elsif (defined($data)) { print STDERR "$header: <BLANK>\n"; }
		else { print STDERR "$header: <N>\n"; }
		return;
	}
	
	if ($limit < $depth) {
		print STDERR "$indent${tabs}** LIMIT ($depth) **\n";
		return;
	}
	
	if ($depth == 1) {
		print STDERR <<"EOM";
$indent======================================================
EOM
	}
	if ($header) {
		print STDERR <<"EOM";
$indent$header
$indent------------------------------------------------------
EOM
	}
	if (($depth == 1) && ref($data)) {
		printf STDERR ("${indent}REF: %s\n", $data);
	}
	my $ok;
	if (ref($data)) {
		foreach (@{$options->{classList}}){
			if (ref($data) =~ /^$_/) {
				$ok = TRUE;
				last;
			}
		}
	}
	if (!ref($data)) {
		my $value = $data;
		if ($value || ($value =~ /\./)) { print STDERR "$indent${tabs}SCALAR: $data\n"; }
		elsif (defined($value)) { print STDERR "$indent${tabs}SCALAR: <BLANK>\n"; }
		elsif ($options->{showNulls}) { print STDERR "$indent${tabs}SCALAR: <N>\n"; }
	}
	elsif (ref($data) eq 'SCALAR') {
		my $value = ${$data};
		if (ref($value) eq 'DateTime') {
			printf STDERR ("$indent${tabs} DateTime: %s %s %s\n", $value->ymd, $value->hms, $value->time_zone_long_name);
		} elsif (ref($value)) {
			printf STDERR ("$indent${tabs}REF: %s\n", $value);
			$self->printObject($value,undef,$options,$depth+1);
		}
		elsif ($value =~ /./) { printf STDERR ("$indent${tabs}%s\n", $value); }
		elsif (defined($value)) { printf STDERR ("$indent${tabs}%s\n", '<BLANK>'); }
		elsif ($options->{showNulls}) { printf STDERR ("$indent${tabs}%s\n", '<N>'); }
	}
	elsif (ref($data) eq 'ARRAY') {
		my $cnt = 0;
		foreach my $value (@{$data}) {
			if (ref($value) eq 'DateTime') {
				printf STDERR ("$indent${tabs}\[ %3d ]$space DateTime: %s %s %s\n", $cnt, $value->ymd, $value->hms, $value->time_zone_long_name);
			} elsif (ref($value)) {
				printf STDERR ("$indent${tabs}\[ %3d ]$space REF: %s\n", $cnt, $value);
				$self->printObject($value,undef,$options,$depth+1);
			}
			elsif ($value =~ /./) { printf STDERR ("$indent${tabs}\[ %3d ]$space %s\n", $cnt, $value); }
			elsif (defined($value)) { printf STDERR ("$indent${tabs}\[ %3d ]$space %s\n", $cnt, '<BLANK>'); }
			elsif ($options->{showNulls}) { printf STDERR ("$indent${tabs}\[ %3d ]$space %s\n", $cnt, '<N>'); }
			$cnt++;
		}
	}
	elsif ((ref($data) eq 'HASH') || ($depth == 1) || $ok) {
		foreach my $name (sort(keys(%{$data}))) {
			my $value = $data->{$name};
			if (ref($value) eq 'DateTime') {
				printf STDERR ("$indent${tabs}%-20s DateTime: %s %s %s\n", $name, $value->ymd, $value->hms, $value->time_zone_long_name);
			} elsif (is_boolean($value)) {
				printf STDERR ("$indent${tabs}%-20s Boolean: %s\n", $name, $value);
			} elsif (ref($value)) {
				printf STDERR ("$indent${tabs}%-20s REF: %s\n", $name, $value);
				if ($options->{suppressParents} && ($name =~ /parent/i)) { print STDERR "$indent${tabs}** Suppressing parent references **\n"; }
				else { $self->printObject($value,undef,$options,$depth+1); }
			}
			elsif ($value =~ /./) { printf STDERR ("$indent${tabs}%-20s %s\n", $name, $value); }
			elsif (defined($value)) { printf STDERR ("$indent${tabs}%-20s %s\n", $name, '<BLANK>'); }
			elsif ($options->{showNulls}) { printf STDERR ("$indent${tabs}%-20s %s\n", $name, '<N>'); }
		}
	}
	else {
		print STDERR "$indent${tabs}- Not displayed -\n";
	}
	if ($depth == 1) {
		print STDERR <<"EOM";
$indent======================================================
EOM
	}
}

sub toString {
	my $self = shift || return;
	my $value = shift;
	my $shouldQuote = shift;
	my $string;
	if (is_hash($value)) {
		my @keys = keys(%{$value});
		my @out;
		foreach my $key (sort @keys) { push(@out, "$key: '$value->{$key}'"); }
		$string = '{ ' . join(', ', @out) . ' }';
	}
	elsif (is_array($value)) {
		$string .= "['" . join("', '", @{$value}) . "']";
	}
	elsif (!defined($value)) { $string = '<N>'; }
	elsif (($value eq ($value+0)) && is_pos_int($value)) { $string = $value + 0; }
	elsif ($value) {
		if ($shouldQuote) { $string = "'$value'"; }
		else { $string = "$value"; }
	}
	else { $string = '<blank>'; }
	return $string;
}

#=====================================================

=head2 B<printChars>

=cut
#=====================================================
sub printChars {
	my $self = shift || return;
	my $text = shift || return;
	my $header = shift;
	my $indent = $self->{indent};
	print STDERR <<"EOM";
$indent======================================================
EOM
	if ($header) {
		print STDERR <<"EOM";
$indent$header
$indent------------------------------------------------------
EOM
	}
	my @chars = split('', $text);
	foreach my $char (@chars) {
		my $ord = ord($char);
		print STDERR "$indent  '$char' - $ord\n";
	}
	print STDERR <<"EOM";
$indent------------------------------------------------------
EOM
}


#=====================================================

=head2 B<pause>

 $self->{debug}->pause($secondsToPause);
 $self->{debug}->pause($secondsToPause, $label);

=cut
#=====================================================
sub pause {
	my $self = shift || return;
	my $seconds = shift || return;
	my $displayStart = shift;
	is_pos_int($seconds) || return;
	
	if (!$self->{isPerson}) { sleep $seconds; return; }
	
	if ($displayStart) { $displayStart .= ': '; }
	
	if ($seconds > 1) {
		my $lastLength;
		for (my $i = $seconds; $i > 0; $i--) {
			my $display = $self->{boldStart} . $displayStart . "==> $i <==" . $self->{boldEnd} . " ";
			$lastLength = length($display);
			if ($ENV{TERM} eq 'screen') { $lastLength = length($displayStart . "==> $i <== "); }
			print STDERR $display;
			sleep 1;
			print STDERR "\r";
		}
		print STDERR ' ' x $lastLength . "\r";
	} else {
		sleep 1;
	}
}


#=====================================================

=head2 B<progress>

Displays a progress bar at the given fraction of progress, a number between 0 and 1 inclusive.
Pass 'end' to cleanly stop the progress bar.

 $self->{debug}->progress($fractionOfProgress, [$label]);
 $self->{debug}->progress('end');

=cut
#=====================================================
sub progress {
	my $self = shift || return;
	my $fraction = shift || return;
	my $label = shift;
	my $debug;
	$self->{isPerson} || return;
	
	# end
	if ($fraction eq 'end') {
		if ($debug) { print STDERR "end\n"; }
		my $labelLength = 0;
		my $progressLength = 102;
		if ($ENV{TERM} ne 'screen') { $progressLength += length($self->{boldStart} . $self->{boldEnd}); }
		if ($self->{progressLabel}) { $labelLength = length($self->{progressLabel}) + 1; }
		print STDERR "\r" . ' ' x ($labelLength + $progressLength) . "\r";
		delete $self->{progress};
		delete $self->{progressLabel};
		return;
	}
	
	if ($fraction > 1) { $fraction = 1; }
	$fraction = int($fraction * 100);
	
	if ($debug) { $self->info("$fraction - $self->{progress}"); }
	
	# reset
	if (exists($self->{progress}) && ($fraction < $self->{progress})) {
		if ($debug) { print STDERR "reset\n"; }
		print STDERR "\n";
		delete $self->{progress};
		delete $self->{progressLabel};
	}
	
	# update
	if ($fraction - $self->{progress}) {
		if ($debug) { print STDERR "update\n"; }
		my $remaining = 100 - $fraction;
		my $cursorMove = $remaining + 1;
		if (!$remaining) { $cursorMove--; }
		if ($label) {
			print STDERR $self->{boldStart} . "\r$label |" . '-'x$fraction . ' 'x$remaining . '|' . "\b"x$cursorMove . $self->{boldEnd};
		} else {
			print STDERR $self->{boldStart} . "\r|" . '-'x$fraction . ' 'x$remaining . '|' . "\b"x$cursorMove . $self->{boldEnd};
		}
		$self->{progressLabel} = $label;
		$self->{progress} = $fraction;
	}
}


#=====================================================

=head2 B<truncate>

 my $truncatedString = $self->{debug}->truncate($string, $numOfChars);

=cut
#=====================================================
sub truncate {
	my $self = shift || return;
	my $text = shift || return '';
	my $width = shift || return $text;
	is_pos_int($width) || return $text;
	
	if (length($text) > $width) {
		return substr($text, 0, $width - 1) . '…';
	}
	return $text;
}

#=====================================================

=head2 B<_getLogTime>

 [04/Jan/2012:00:07:14 -0600]

=cut
#=====================================================
sub _getLogTime {
	my $self = shift || return;
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
	my @abbr = qw( Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec );
	my $month = $abbr[$mon];
	$mon++;
	$year += 1900;
	my $tz = '-0600';
	if ($isdst) { $tz = '-0500'; }
	
# 	return sprintf("%02d/%s/%04d:%02d:%02d:%02d", $mday, $month, $year, $hour, $min, $sec);
	return sprintf("%04d-%02d-%02d %02d:%02d:%02d", $year, $mon, $mday, $hour, $min, $sec);
}


#=====================================================
#
# Leftronic functions
#
#=====================================================

=head2 B<sendToLeftronic>

Call a single stream:
 sendToLeftronic($streamName, $pointHash or $arrayOfPointHashes);
 sendToLeftronic($streamName, 'clear');

Call multiple streams:
 sendToLeftronic({
 	$streamName		=> $pointHash or $arrayOfPointHashes,
 	$streamName2	=> 'clear'
 });
 sendToLeftronic( [ {
 	streamName		=> $streamName,
 	point			=> $pointHash or $arrayOfPointHashes
 }, {
 	streamName		=> $streamName2,
 	command			=> 'clear'
 } ] );

Example point hashes:
 Number
 { number => 15, [ prefix => "$" ], [ suffix => ' / 20' ] }
 { delta => 5, [ prefix => "$" ], [ suffix => '%' ] }
 Gallery
 { title => "title", msg => "body", imgUrl => "http://goo.gl/uqHsk" }
 HTML
 { html => "<h3>Hello World</h3>" }
 Label
 { label => "Some Label" }
 Leaderboard, Pie Chart, Bar Chart
 { leaderboard => [ { name => "Tim", value => 16, [ suffix => '%' ] }, { ... } ] }
 { leaderboardItem => [ { name => "Travis", value => 12, [ suffix => '%' ] } ] }
 { chart => [ { name => "Tim", value => 16, [ color => "red|blue|green|purple|yellow" ] }, { ... } ] }
 Line Graph/Sparkline
 { number => 15, timestamp => 1329205474 }
 List
 { list => [ { listItem => "Tim" }, { ... } ] }
 { listItem => "Tim" }
 Image
 { imgUrl => "http://goo.gl/uqHsk" }
 Map
 { latitude => 36.1443, longitude => -86.8144, [ color => "red|blue|green|purple|yellow" ] }
 Table
 { table => [ ["header1", ...], ["value1", ...], [...] ] }
 { tableRow => ["value1", ...] }
 Text Feed
 { title => "title", msg => "body", [ imgUrl => "http://goo.gl/uqHsk" ] }
 XY Graph
 { x => 15, y => 20 }

=cut
#=====================================================
sub sendToLeftronic {
	my $self = shift || return;
	my $streams = shift || return;
	my $points = shift;
	my $debug = shift;
	
	my $apiKey = 'leftronic_api_key';
	my $json = { accessKey => $apiKey };
	
	if (is_text($streams)) {
		$json->{streamName} = $streams;
		if (is_text($points) && ($points eq 'clear')) {
			$json->{command} = 'clear';
		} elsif (is_hash($points) || is_array($points)) {
			$json->{point} = $points;
		}
	} elsif (is_hash($streams)) {
		$json->{streams} = [];
		while (my($streamName, $points) = each(%{$streams})) {
			my $stream = { streamName => $streamName };
			if (is_text($stream->{command}) && ($stream->{command} eq 'clear')) {
				$stream->{command} = 'clear';
			} elsif (is_hash($points) || is_array($points)) {
				$stream->{point} = $points;
			} else {
				$self->warning("Invalid hash stream");
				$self->printObject($stream, '$stream');
				next;
			}
			push(@{$json->{streams}}, $stream);
		}
	} elsif (is_array($streams)) {
		$json->{streams} = [];
		foreach my $stream (@{$streams}) {
			if (is_text($stream->{streamName})) {
				if (is_text($stream->{command}) && ($stream->{command} eq 'clear')) {
					push(@{$json->{streams}}, $stream);
				} elsif (is_hash($stream->{point}) || is_array($stream->{point})) {
					push(@{$json->{streams}}, $stream);
				} elsif (is_text($stream->{point})) {
					push(@{$json->{streams}}, $stream);
				} else {
					$self->warning("Invalid array stream");
					$self->printObject($stream, '$stream');
					next;
				}
			}
		}
	} else {
		$self->error("Invalid input to sendToLeftronic");
	}
	my $url = 'https://www.leftronic.com/customSend/';
	my $jsonText = makeJSON($json, { compress => 1 });
	my $command = "curl -s -k -d '$jsonText' $url";
	if ($debug) { $self->debug($command); }
	my $response = `$command`;
	if ($debug) { $self->printObject($response, '$response'); }
	return $response;
}

#=====================================================

=head2 B<clearLeftronic>

 clearLeftronic($streamName);

=cut
#=====================================================
sub clearLeftronic {
	my $self = shift || return;
	my $streamName = shift || return;
	$self->sendToLeftronic($streamName, 'clear');
}

#=====================================================

=head2 B<sendToLeftronicNotice>

 sendToLeftronicNotice($streamName, $message);
 sendToLeftronicNotice($streamName, [$message]);

=cut
#=====================================================
sub sendToLeftronicNotice {
	my $self = shift || return;
	my $streamName = shift || return;
	my $messages = shift;
	my $debug = shift;
	if (is_text($messages)) { $messages = [$messages]; }
	if (!is_array($messages)) { return; }
	
	my $displayTime = localtime();
	$displayTime =~ s/(^\w+\s+|:\d+\s+\d+$)//g;
	my $points = [];
	foreach my $message (@{$messages}) {
		push(@{$points}, {
			title	=> $displayTime,
			msg		=> $message
		});
	}
	$self->sendToLeftronic($streamName, $points, $debug);
}

#=====================================================

=head2 B<mapToLeftronic>

 $options = {
 	color	=> $color,	# 'red', 'blue', 'green', 'purple', or 'yellow'
 	map		=> $map		# Crops out points that don't fall with the map. Choices: 'US'
 };

Map a single point
 mapToLeftronic($streamName, 36.1443, -86.8144, $options);
 mapToLeftronic($streamName, '(36.1443,-86.8144)', $options);	# PostgreSQL point
 mapToLeftronic($streamName, { lat => 36.1443, long => -86.8144 }, $options);
 mapToLeftronic($streamName, { latitude => 36.1443, longitude => -86.8144 }, $options );

Map multiple points
 mapToLeftronic($streamName, ['(36.1443,-86.8144)', '(36.137,-86.8307)'], $options );
 mapToLeftronic($streamName, [{ lat => 36.1443, long => -86.8144 },
 							  { lat => 36.137, long => -86.8307 }], $options );
 mapToLeftronic($streamName, [{ latitude => 36.1443, longitude => -86.8144 },
 							  { latitude => 36.137, longitude => -86.8307 }], $options );

=cut
#=====================================================
sub mapToLeftronic {
	my $self = shift || return;
	my $streamName = shift || return;
	my $coords = shift || return;
	my $longOrOptions = shift;
	my $options = shift;
	
	my $long;
	if (is_hash($longOrOptions)) { $options = $longOrOptions; }
	elsif (is_number($longOrOptions)) { $long = $longOrOptions; }
	
	my $points = toLatLongHash($coords, $long);
	if (!is_array($points)) { $points = [$points]; }
	if (!is_array_hash($points)) {
		$self->warning("Invalid coordinates");
		$self->printObject($coords, '$coords');
		return;
	}
	
	if ($options->{color} =~ /^(?:red|blue|green|purple|yellow)$/) {
		foreach my $point (@{$points}) {
			if (!$point->{color}) { $point->{color} = $options->{color}; }
		}
	}
	if ($options->{map}) {
		$points = _cropLeftronicPoints($options->{map}, $points);
	}
	
	if (!is_array_with_content($points)) { return; }
	return $self->sendToLeftronic($streamName, $points, $options->{debug});
}

sub _cropLeftronicPoints {
	my $map = shift || return;
	my $points = shift || return;
	if (!is_array_with_content($points)) { return; }
	my $cropped = [];
	foreach my $point (@{$points}) {
		if (lc($map) eq 'us') {
			my $lat = $point->{latitude};
			my $long = $point->{longitude};
			my $isInMap = FALSE;
			# Puerto Rico
			if (($lat >= 17.75) && ($lat <= 18.75) && ($long >= -67.5) && ($long <= -64)) { $isInMap = TRUE; }
			# Hawaii
			if (($lat >= 18.5) && ($lat <= 22.5) && ($long >= -161) && ($long <= -154.5)) { $isInMap = TRUE; }
			# Alaska
			if (($lat >= 54.5) && ($lat <= 72) && ($long >= -180) && ($long <= -129.5)) { $isInMap = TRUE; }
			# 48 states
			if (($lat >= 24) && ($lat <= 49.4) && ($long >= -125) && ($long <= -66)) { $isInMap = TRUE; }
			if ($isInMap) { push(@{$cropped}, $point); }
		}
		elsif (lc($map) eq 'uk') {
			my $lat = $point->{latitude};
			my $long = $point->{longitude};
			my $isInMap = FALSE;
			# UK
			if (($lat >= 49.9) && ($lat <= 60.9) && ($long >= -5.9) && ($long <= 1.9)) { $isInMap = TRUE; }
			# Northern Ireland and western Scotland
			if (($lat >= 54) && ($lat <= 58.6) && ($long >= -8.2) && ($long <= -5.9)) { $isInMap = TRUE; }
			if ($isInMap) { push(@{$cropped}, $point); }
		}
		elsif (lc($map) eq 'ireland') {
			my $lat = $point->{latitude};
			my $long = $point->{longitude};
			my $isInMap = FALSE;
			# Ireland
			if (($lat >= 51.4) && ($lat <= 54.4) && ($long >= -10.7) && ($long <= -5.9)) { $isInMap = TRUE; }
			# Northern part of Ireland, but not Northern Ireland
			if (($lat >= 54.4) && ($lat <= 55.4) && ($long >= -8.9) && ($long <= -6.9)) { $isInMap = TRUE; }
			if ($isInMap) { push(@{$cropped}, $point); }
		}
	}
	if (is_array_with_content($cropped)) { return $cropped; }
	return;
}

#=====================================================

=head2 B<mapSquareToLeftronic>

=cut
#=====================================================
sub mapSquareToLeftronic {
	my $self = shift || return;
	my $streamName = shift || return;
	my $lat = shift;
	my $long = shift;
	my $w = shift;
	my $options = shift;
	my $buffer = .03;
	my $color = 'red';
	my $map;
	if (is_hash($options)) {
		$color = $options->{color} || $color;
		$map = $options->{map};
		$buffer = $options->{buffer} || $buffer;
	}
	
	my $b = $w * $buffer;
	my $h = $w / 2;
	my $points = [
		{ latitude => $lat + $b, longitude => $long + $b },
		{ latitude => $lat + $h, longitude => $long + $b },
		{ latitude => $lat + $w - $b, longitude => $long + $b },
		{ latitude => $lat + $b, longitude => $long + $h },
		{ latitude => $lat + $h, longitude => $long + $h },
		{ latitude => $lat + $w - $b, longitude => $long + $h },
		{ latitude => $lat + $b, longitude => $long + $w - $b },
		{ latitude => $lat + $h, longitude => $long + $w - $b },
		{ latitude => $lat + $w - $b, longitude => $long + $w - $b }
	];
	$self->mapToLeftronic($streamName, $points, { color => $color, map => $map });
}








=head1 CHANGES

  20060822 TJM - v0.01 started development
  20081209 TJM - v1.05 cleaned up post
  20120105 TJM - v6.0 mostly the same
  20140124 TJM - v2.00 added Leftronic calls
  20140320 TJM - v7.0 merged 2.00 and 6.0
  20171109 TJM - v8.0 Moved to SitemasonPl open source project and merged with updates

=head1 AUTHOR

  Tim Moses <tim@moses.com>
  Sitemason Open Source <https://github.com/sitemason>

=cut

1;
