package SitemasonPl::CLI 8.0;

=head1 NAME

SitemasonPl::CLI

=head1 DESCRIPTION

Handy functions for providing a better command line interface for a script.

=cut

use v5.012;
use strict;
use warnings;
use utf8;
use constant TRUE => 1;
use constant FALSE => 0;

use Getopt::Long qw(:config bundling);
use Pod::Usage qw(pod2usage);
use Proc::ProcessTable;

use lib qw( /opt/lib/site_perl );
use SitemasonPl::Common;
use SitemasonPl::CLI::Table;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(mark print_object is_already_running is_already_running_with_args);

sub new {
#=====================================================

=head2 B<new>

 my $cli = SitemasonPl::CLI->new(
	exit_if_running		=> TRUE,
	commandline_args	=> []		# As defined in get_options; includes 'help' and 'version'
 );

=cut
#=====================================================
	my ($class, %arg) = @_;
	$class || return;
	
	my $self = {};
	bless $self, $class;
	($self->{script_name}) = $0 =~ /\/([^\/]+?)$/;
	
	if ($arg{exit_if_running}) {
		if (is_already_running()) { $self->warning("Another instance of $self->{script_name} is already running"); exit; }
	} elsif ($arg{exit_if_running_with_args}) {
		if (is_already_running_with_args()) { $self->warning("Another instance of $self->{script_name} is already running"); exit; }
	}
	
	if ($arg{commandline_args}) {
		if (!is_array($arg{commandline_args})) { $arg{commandline_args} = []; }
		push(@{$arg{commandline_args}}, 'help|h');
		push(@{$arg{commandline_args}}, 'version');
		$self->{options} = $self->get_options(@{$arg{commandline_args}});
		if ($self->{options}->{help} || $self->{options}->{usage}) { $self->print_usage; exit; }
		if ($self->{options}->{version}) { $self->print_version; exit; }
	}
	
	return $self;
}


sub is_already_running {
#=====================================================

=head2 B<is_already_running>

 if (is_already_running) { die "Already running"; }
 if (is_already_running) { $self->{cli}->is_person && $self->{debug}->warning("Already running"); exit; }

=cut
#=====================================================
	my $limit = shift || 1;
	
	my ($script) = $0 =~ /\/([^\/]+?)$/;
	my $pid = $$;
	my $ps = new Proc::ProcessTable( 'cache_ttys' => 1 );
	my $process_table = $ps->table;
	my $cnt = 0;
	foreach my $process (@{$process_table}) {
		my $fname = $process->fname;
		my $line = $process->cmndline;
		if (($script =~ /^($fname|perl)/) && ($line =~ /perl .*\Q$script\E(\s|$)/) && ($process->pid != $pid)) { $cnt++; }
	}
	if ($cnt > ($limit - 1)) { return TRUE; }
}


sub is_already_running_with_args {
#=====================================================

=head2 B<is_already_running_with_args>

 if (is_already_running_with_args()) { die "Already running"; }

=cut
#=====================================================
	my $limit = 1;
	
	my ($script) = $0 =~ /\/([^\/]+?)$/;
	my $cmdline = $script;
	if (is_array_with_content($_[0])) { $cmdline .= " " . join(' ', @{$_[0]}); }
	elsif ($_[0]) { $cmdline .= " " . join(' ', @_); }
	
	my $pid = $$;
	my $ps = new Proc::ProcessTable( 'cache_ttys' => 1 );
	my $process_table = $ps->table;
	my $cnt = 0;
	foreach my $process (@{$process_table}) {
		my $fname = $process->fname;
		my $line = $process->cmndline;
		if (($script =~ /^($fname|perl)/) && ($line =~ /perl .*\Q$cmdline\E$/) && ($process->pid != $pid)) {
			$cnt++;
		}
	}
	if ($cnt > ($limit - 1)) { return TRUE; }
}


sub get_options {
#=====================================================

=head2 B<get_options>

Given a list of acceptable options, returns a hash of the options with their values. Uses GetOpt::Long option definitions.
 http://search.cpan.org/~jv/Getopt-Long-2.50/lib/Getopt/Long.pm

 $option_definitions = [
 	'option',		# Simple option that accepts --option, -option, --o, -o as true (1)
 	'option!',		# Negated option also allows --nooption as false (0)
 	'option+',		# Incremental option returns the number of times an option is listed
 	'option=s',		# Requires a string argument --option=text, --option text, -o=text, -o text
 	'option=i',		# Requires an integer argument --option=42, --option 42, -o=42, -o 42
 	'option=f',		# Requires a decimal argument --option=3.14, --option 3.14, -o=3.14, -o 3.14
 	'option:s',		# Optional string argument; defaults to ""
 	'option:i',		# Optional integer argument; defaults to 0
 	'option:f',		# Optional decimal argument; defaults to 0
 	'option:f@',	# Accepts multiple occurrences as an array; works with all the previous options: -o 42 -o 3.14 -o
 	'option:i%',	# Accepts multiple occurrences as an array; works with all the previous options: -o a=1 -o b=2
 ];
 
 my $options = get_option($option_definitions);

=cut
#=====================================================
	my $self = shift || return;
	my @params = ();
	my $options = {};
	foreach my $arg (@_) {
		$arg || next;
		my $name = $arg;
		$name =~ s/\W.*$//;
		if ($arg =~ /\%$/) {
			$options->{$name} = {};
			push(@params, $arg, $options->{$name});
		} elsif ($arg =~ /\@$/) {
			$options->{$name} = [];
			push(@params, $arg, $options->{$name});
		} else {
			push(@params, $arg, \$options->{$name});
		}
	}
	GetOptions(@params);
	return $options;
}


sub print_usage {
	my $self = shift || return;
	pod2usage({ -indent => 4, -width => 140, -verbose => 99, -sections => ['USAGE'] });
	return TRUE;
}

sub print_version {
	my $self = shift || return;
	print $self->{script_name};
	if ($main::VERSION) { print " $main::VERSION"; }
	say "";
	return TRUE;
}




sub info {
	my $self = shift || return;
	my $text = shift;
	print "$text\n";
}

sub body {
	my $self = shift || return;
	my $text = shift;
	my $suppress_newline = shift;
	print $text;
	$suppress_newline || print "\n";
}

sub header {
	my $self = shift || return;
	my $text = shift;
	my $suppress_newline = shift;
	$self->print_bold($text);
	$suppress_newline || print "\n";
}

sub warning {
	my $self = shift || return;
	my $text = shift;
	my $suppress_newline = shift;
	$self->print_bold($text);
	$suppress_newline || print "\n";
}

sub error {
	my $self = shift || return;
	my $text = shift;
	my $suppress_newline = shift;
	$self->print_bold("ERROR: $text");
	$suppress_newline || print "\n";
}


sub get_answer {
#=====================================================

=head2 B<get_answer>

 defined(my $answer = get_answer) || return;
 defined(my $answer = get_answer($array_of_inputs) || return;

$array_of_answers is an array of inputs that should be used before STDIN. Good for grabbing some advance answers in the original command line args.

=cut
#=====================================================
	my $self = shift || return;
	my $inputs = shift;
	my $answer;
	print scalar $self->get_term_color('bold');
	if (is_array_with_content($inputs)) {
		$answer = shift(@{$inputs});
		print "$answer\n";
	} else {
		$answer = <STDIN>;
	}
	print scalar $self->get_term_color('reset');
	if (!defined($answer) || ord($answer) == 0) { print "\n"; return; }
	if ($answer =~ /^exit/) { print "\n"; return; }
	chomp($answer);
	$answer =~ s/(?:^\s+|\s+$)//g;
	if (!length($answer)) { return ""; }
	if (!$answer) { return '0'; }
	return $answer;
}

sub get_menu_answer {
#=====================================================

=head2 B<get_menu_answer>

Returns an answer from an array of choices:

 my $value = $self->{cli}->get_menu_answer($choices_as_array, $label) || exit;
 my $value = $self->{cli}->get_menu_answer($choices_as_array, $label, $preinputs) || exit;
 my $hash = $self->{cli}->get_menu_answer($choices_as_arrayhash, $label, $preinputs, $key_name) || exit;
 my $value = $self->{cli}->get_menu_answer($choices_as_arrayhash, $label, $preinputs, $key_name, $value_name) || exit;

=cut
#=====================================================
	my $self = shift || return;
	my $choices = shift || return;
	my $label = shift;
	my $inputs = shift;
	my $key_name = shift;
	my $value_name = shift;
	is_array_with_content($choices) || return;
	
	my $input;
	if (is_array_with_content($inputs)) { $input = shift(@{$inputs}); }
	
	my $array_length = @{$choices};
	my $index_width = length($array_length);
	my $pre_input;
	for (my $i = 0; $i < $array_length; $i++) {
		my $key = $choices->[$i];
		my $value = $choices->[$i];
		if (is_hash($key) && is_text($key_name)) { $key = $key->{$key_name}; }
		if (is_hash($value) && is_text($value_name)) { $value = $value->{$value_name}; }
		if (!$pre_input && is_text($input) && ($key =~ /^\Q$input\E/)) {
			$pre_input = $i + 1;
		}
		my $index_label = $self->make_color('[', ['gray', 'bold']) . $self->make_color(sprintf("%${index_width}d", $i+1), ['azure', 'bold']) . $self->make_color(']', ['gray', 'bold']);
		printf("  %s %s\n", $index_label, $self->make_color($key, 'maroon'));
	}
	
	my $answer;
	if ($pre_input && is_pos_int($pre_input)) { $pre_input = [$pre_input]; }
	while (42) {
		print "$label [1 - " . $array_length . "]: ";
		defined($answer = $self->get_answer($pre_input)) || return;
		if (is_pos_int($answer, 1, $array_length)) { last; }
		if (is_text($answer)) { $self->warning("The answer must be a number from 1 to " . $array_length); }
		else { $self->warning("An answer is required (CTRL-D to exit)"); }
	}
	
	my $value = $choices->[$answer - 1];
	if (is_hash($value) && is_text($value_name)) { $value = $value->{$value_name}; }
	return $value;
}



sub is_person {
	my $self = shift || return;
	if (($ENV{TERM} && ($ENV{TERM} ne 'dumb') && ($ENV{TERM} ne 'tty')) || $ENV{SSH_AUTH_SOCK}) {
		return TRUE;
	}
}

sub _term_supports_colors {
	if ($ENV{TERM} && ($ENV{TERM} ne 'dumb') && ($ENV{TERM} ne 'tty')) { return TRUE; }
}

sub _get_term_color_numbers {
	my $self = shift || return;
	# https://en.wikipedia.org/wiki/ANSI_escape_code
	# https://en.wikipedia.org/wiki/Web_colors
	my $debug = shift;
	state $term_colors = {};
	if (!$debug && is_hash_with_content($term_colors)) { return $term_colors; }
	
	my $colors = [
		{ name => 'reset',			num => 0 },
		{ name => 'default',		num => 39 },
		{ name => 'default_bg',		num => 49 },
		
		{ name => 'bold',			num => 1 },	# reset 21 # yes
		{ name => 'faint',			num => 2 },	# reset 22 # yes
		{ name => 'italic',			num => 3 },	# reset 23
		{ name => 'underline',		num => 4 },	# reset 24 # yes
		{ name => 'blink',			num => 5 },	# reset 25 # yes
		{ name => 'rapid',			num => 6 },	# reset 26
		{ name => 'inverse',		num => 7 },	# reset 27 # yes
		{ name => 'conceal',		num => 8 },	# reset 28 # yes
		{ name => 'crossed',		num => 9 },	# reset 29
		
		{ name => 'white',			num => 97 },
		{ name => 'silver',			num => 37 },
		{ name => 'gray',			num => 90 },
		{ name => 'black',			num => 30 },
		
		{ name => 'red',			num => 91 },
		{ name => 'maroon',			num => 31 },
		{ name => 'yellow',			num => 93 },
		{ name => 'olive',			num => 33 },
		{ name => 'lime',			num => 92 },
		{ name => 'green',			num => 32 },
		{ name => 'cyan',			num => 96 },
		{ name => 'teal',			num => 36 },
		{ name => 'blue',			num => 94 },
		{ name => 'azure',			num => 34 },
		{ name => 'pink',			num => 95 },
		{ name => 'magenta',		num => 35 },
		
		{ name => 'white_bg',		num => 107 },
		{ name => 'silver_bg',		num => 47 },
		{ name => 'silver_bg',			num => 100 },
		{ name => 'black_bg',		num => 40 },
		
		{ name => 'red_bg',			num => 101 },
		{ name => 'maroon_bg',		num => 41 },
		{ name => 'yellow_bg',		num => 103 },
		{ name => 'yellow_bg',		num => 43 },
		{ name => 'lime_bg',			num => 102 },
		{ name => 'green_bg',		num => 42 },
		{ name => 'cyan_bg',			num => 106 },
		{ name => 'teal_bg',			num => 46 },
		{ name => 'blue_bg',			num => 104 },
		{ name => 'azure_bg',		num => 44 },
		{ name => 'pink_bg',			num => 105 },
		{ name => 'magenta_bg',		num => 45 }
	];
	for (my $color = 0; $color < @{$colors}; $color++) {
		my $item = $colors->[$color];
		$term_colors->{$item->{name}} = $item->{num};
		if ($debug) {
			my $s = "\e[$item->{num}"; my $e = "\e[0m";
			if ($color < 12) {
				printf("%14s: ${s}m%s$e\n", $item->{name}, $item->{name});
			} else {
				if ($color == 12) {
					my $header = sprintf("%14s  %-14s %-14s %-14s %-14s", '', 'default', 'bold', 'faint', 'inverse');
					print "\n" . $self->make_color($header, ['bold', 'underline']) . "\n";
					printf("%14s: \e[39m%-14s$e \e[39;1m%-14s$e \e[39;2m%-14s$e \e[39;7m%-14s$e\n", 'default', 'default', 'default', 'default', 'default');
				} elsif ($color == 28) {
					print "\n";
				}
				my $name = $item->{name};
				$name =~ s/Bg$//;
				printf("%14s: ${s}m%-14s$e ${s};1m%-14s$e ${s};2m%-14s$e ${s};7m%-14s$e\n", $name, $name, $name, $name, $name);
			}
		}
	}
	if ($debug) { print "\n"; }
	return $term_colors;
}
sub get_term_color {
	# my $color_code = $cli->get_term_color($color_name);
	my $self = shift || return;
	my $name = shift;
	if ($name && _term_supports_colors()) {
		my $colors = $self->_get_term_color_numbers;
		if (defined($colors->{$name})) {
			return sprintf("\e[%dm", $colors->{$name});
		}
	}
	return '';
}

sub make_color {
	my $self = shift || return;
	my $text = shift;
	my $color = shift || 'bold';
	my $bg = shift;
	_term_supports_colors() || return $text;
	my $debug = shift;
	
	if ($bg) {
		if (is_array($color)) { push(@{$color}, "${bg}Bg"); }
		else { $color = [$color, "${bg}Bg"]; }
	}
	
	my $color_numbers = $self->_get_term_color_numbers($debug);
	if (is_array($color)) {
		my @color_list;
		foreach my $item (@{$color}) {
			if ($color_numbers->{$item}) { push(@color_list, $color_numbers->{$item}); }
		}
		@color_list || return $text;
		return sprintf("\e[%sm%s\e[0m", join(';', @color_list), $text);
	} elsif ($color_numbers->{$color}) {
		return sprintf("\e[%dm%s\e[0m", $color_numbers->{$color}, $text);
	}
	return $text;
}

sub reset_color {
	my $self = shift || return;
	my $colors = $self->get_term_color();
	if (exists($colors->{reset})) { return $colors->{reset}; }
	return '';
}

sub bold {
	my $self = shift || return;
	return $self->make_color(shift, 'bold');
}

sub print_bold {
	my $self = shift || return;
	print $self->make_color(shift, 'bold');
}

sub say_bold {
	my $self = shift || return;
	print $self->make_color(shift, 'bold') . "\n";
}


sub mark {
	my $self = shift;
	my $label;
	if (is_object($self)) {
		$label = shift;
	} else {
		$label = $self;
		$self = SitemasonPl::CLI->new();
	}
	if ($label) { $label .= ' '; } else { $label = ''; }
	
	my @returns = caller(-1);
	print_object(\@returns, '@returns');
	my $location = '';
	if ($returns[3]) { $location = "$returns[3] - Line $returns[2]"; }
	if (!@returns) { @returns = caller(0); $location = "$returns[1] - Line $returns[2]"; }
	
	state $counter = 0;
	print $self->make_color(' ' . $counter++ . ' ', ['bold', 'inverse']) . 
		$self->bold(" ${label}===> $location") . "\n";
}

sub print_object {
#=====================================================

=head2 B<print_object>

	print_object($object, $label, $indent, $limit);

	my $string = 'string';
	my $function = sub { print "Lambda\n"; };
	my $function2 = \&readCustomerConfig;
	my $object = {
		test => 'sdflkj',
		very_extra_long_key_name => 1,
		a => TRUE,
		an_array => [1, 'blue', undef, "Something with a\nnewline", { a => 0, b => 1, longer => 2 }, 6, 7, 8, [], 9, 10, 11],
		undefined => undef,
		scalarref => \$string,
		function => $function,
		function2 => $function2,
		object => $self,
		emptyHash => {},
		emptyArray => []
	};
	
	print_object($object, 'My Object', 5);
	print_object('test', 'My String', 5);
	print_object('test', undef, 5);
	print_object([], undef, 5);
	print_object($function2, undef, 5);

=cut
#=====================================================
	my $self = shift;
	my $object;
	if (is_object($self)) {
		$object = shift;
	} else {
		$object = $self;
		$self = SitemasonPl::CLI->new();
	}
	my $label = shift || '';
	my $indent = shift || 0;
	my $limit = shift;
	
	if ($label) { $label = $self->make_color($label, 'bold'); }
	my $string = $self->convert_object_to_string($object, undef, $limit);
	my $indentString = ' ' x $indent;
	$string =~ s/\n/\n$indentString/gs;
	$string =~ s/$indentString$//;
	if ($label) {
		print "$indentString$label: $string";
	} else {
		print "$indentString$string";
	}
}

sub _convert_object_to_string_key {
	my $self = shift || return;
	my $key = shift;
	my $value = shift;
	my $printKey = $key;
	if (is_hash($value)) { $printKey = $self->make_color($key, ['green', 'bold']); }
	elsif (is_array($value)) { $printKey = $self->make_color($key, ['azure', 'bold']); }
	else { $printKey = $self->make_color($key, ['gray', 'bold']); }
	return $printKey;
}
sub convert_object_to_string {
	my $self = shift || return;
	my $object = shift;
	my $level = shift || 0;
	my $limit = shift;
	my $key_size = 20;
	
	my $string = '';
	my $spacing = '.   ';
	if (_term_supports_colors()) { $spacing = $self->make_color('+---', 'silver'); }
	my $indent = $spacing x $level;
	
	if (is_hash($object)) {
		if (is_hash_with_content($object)) {
			my $opening = $self->make_color('{', ['green', 'bold']);
			my $closing = $self->make_color('}', ['green', 'bold']);
			
			if ($object =~ /^(.*?)=HASH/) {
				my $printObject = $self->make_color($1, 'teal');
				$string .= "$printObject $opening\n";
			} else {
				$string .= "$opening\n";
			}
			my $max = 0;
			foreach my $key (keys(%{$object})) {
				if ((length($key) > $max) && (length($key) <= $key_size)) { $max = length($key); }
			}
			my $cnt = 0;
			foreach my $key (sort { by_any($a,$b) } keys %{$object}) {
				my $value = $object->{$key};
				my $printKey = $self->_convert_object_to_string_key($key, $value);
				my $tempMax = $max + length($printKey) - length($key) ;
				$string .= sprintf("%s%s%-${tempMax}s => ", $indent, $spacing, $printKey);
				$string .= $self->convert_object_to_string($value, $level + 1);
				$cnt++;
				if (!$level && $limit && ($cnt >= $limit)) { last; }
			}
			$string .= "$indent$closing\n";
		} else {
			$string .= "{}\n";
		}
	} elsif (is_array($object)) {
		if (is_array_with_content($object)) {
			my $opening = $self->make_color('[', ['blue', 'bold']);
			my $closing = $self->make_color(']', ['blue', 'bold']);
			$string .= "$opening\n";
			my $arrayLength = @{$object};
			my $max = length($arrayLength);
			if ($max > $key_size) { $max = $key_size; }
			my $key = 0;
			foreach my $value (@{$object}) {
				my $fullKey = sprintf("[%${max}s]", $key);
				my $printKey = $self->_convert_object_to_string_key($fullKey, $value);
				$string .= sprintf("%s%s%s => ", $indent, $spacing, $printKey);
				$string .= $self->convert_object_to_string($value, $level + 1);
				$key++;
				if (!$level && $limit && ($key >= $limit)) { last; }
			}
			$string .= "$indent$closing\n";
		} else {
			$string .= "[]\n";
		}
	} elsif (ref($object) eq 'CODE') {
		my $cv = svref_2object ( $object );
		my $gv = $cv->GV;
		my $printObject = $self->make_color("sub " . $gv->NAME, 'blue');
		$string .= "$printObject\n";
	} elsif (ref($object) eq 'SCALAR') {
		my $output = ${$object} || '';
		$output =~ s/\n/\\n/gm;
		$output =~ s/\r/\\r/gm;
		my $printObject = $self->make_color('"' . $output . '"', 'maroon');
		$string .= "scalar $printObject\n";
	} elsif (ref($object)) {
		my $printObject = $self->make_color($object, 'olive');
		$string .= "$printObject\n";
	} elsif (!defined($object)) {
		my $printObject = $self->make_color('undef', 'line');
		$string .= "$printObject\n";
	} else {
		$object =~ s/\n/\\n/gm;
		$object =~ s/\r/\\r/gm;
		my $printObject = $self->make_color('"' . $object . '"', 'maroon');
		$string .= "$printObject\n";
	}
	return $string;
}



=head1 CHANGES

  2014-03-20 TJM - v1.0 Started development
  2017-11-09 TJM - v8.0 Moved to SitemasonPl open source project and merged with updates

=head1 AUTHOR

  Tim Moses <tim@moses.com>
  Sitemason Open Source <https://github.com/sitemason>

=cut

1;
