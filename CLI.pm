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
our @EXPORT_OK = qw(mark trace print_object is_already_running is_already_running_with_args);

sub new {
#=====================================================

=head2 B<new>

 my $cli = SitemasonPl::CLI->new(
	exit_if_running		=> FALSE,
	commandline_args	=> [],		# As defined in get_options; includes 'help' and 'version'
	use_markdown		=> FALSE
 );

=cut
#=====================================================
	my ($class, %arg) = @_;
	$class || return;
	
	my $self = {
		silent			=> $arg{silent},
		use_markdown	=> $arg{use_markdown}
	};
	bless $self, $class;
	$self->init_formats;
	($self->{script_name}) = $0 =~ /\/([^\/]+?)$/;
	my ($hostname) = `/bin/hostname`;
	if ($hostname =~ /dev/) { $self->{is_dev} = TRUE; }
	
	if ($arg{exit_if_running}) {
		if (is_already_running()) { $self->warning("Another instance of $self->{script_name} is already running"); exit; }
	} elsif ($arg{exit_if_running_with_args}) {
		if (is_already_running_with_args()) { $self->warning("Another instance of $self->{script_name} is already running"); exit; }
	}
	
	if ($arg{commandline_args}) {
		if (!is_array($arg{commandline_args})) { $arg{commandline_args} = []; }
		push(@{$arg{commandline_args}}, 'help|h');
		push(@{$arg{commandline_args}}, 'version|V');
		$self->{options} = $self->get_options(@{$arg{commandline_args}});
		if ($self->{options}->{help} || $self->{options}->{usage}) { $self->print_usage; exit; }
		if ($self->{options}->{version}) { $self->print_version; exit; }
	}
	if ($arg{print_intro}) { $self->print_intro; }
	
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


sub print_intro {
	my $self = shift || return;
	$self->say_bold("Running: " . scalar localtime());
	return TRUE;
}

sub print_usage {
	my $self = shift || return;
	my $message = shift;
	if ($message) { $self->error($message); }
	pod2usage({ -indent => 1, -width => 140, -verbose => 99, -sections => ['USAGE'] });
	return TRUE;
}

sub print_version {
	my $self = shift || return;
	print $self->{script_name};
	if ($main::VERSION) { printf(" %1.2f", $main::VERSION); }
	say "";
	return TRUE;
}




sub info {
	my $self = shift || return;
	my $text = shift;
	$text = $self->convert_markdown_to_ansi($text);
	my $header = get_debug_header();
	print "$header - $text\n";
}

sub body {
	my $self = shift || return;
	my $text = shift || return '';
	$self->{silent} && return;
	
	my $suppress_newline = shift;
	$text = $self->convert_markdown_to_ansi($text);
	print $text;
	$suppress_newline || print "\n";
}

sub title {
	my $self = shift || return;
	my $text = shift;
	my $suppress_newline = shift;
	$self->{silent} && return;
	
	$text = $self->convert_markdown_to_ansi($text);
	print $self->make_color(" $text ", ['blue', 'bold', 'inverse']);
	$suppress_newline || print "\n";
}

sub header {
	my $self = shift || return;
	my $text = shift;
	my $suppress_newline = shift;
	$self->{silent} && return;
	
	$text = $self->convert_markdown_to_ansi($text);
	$text =~ s/^(\s*)(.*)$/$1.$self->make_color(" $2 ", ['blue', 'bold', 'underline'])/egm;
	print $text;
	$suppress_newline || print "\n";
}

sub success {
	my $self = shift || return;
	my $text = shift;
	my $suppress_newline = shift;
	$self->{silent} && return;
	
	$text = $self->convert_markdown_to_ansi($text);
	print $self->make_color($text, ['green', 'bold']);
	$suppress_newline || print "\n";
}

sub dry_run {
	my $self = shift || return;
	my $text = shift;
	my $suppress_newline = shift;
	$self->{silent} && return;
	
	$text = $self->convert_markdown_to_ansi($text);
	$text =~ s/^(.*)$/$self->make_quote('silver_bg').$self->make_color($1,['gray'])/egm;
	print $text;
	$suppress_newline || print "\n";
}

sub warning {
	my $self = shift || return;
	my $text = shift;
	my $suppress_newline = shift;
	$self->{silent} && return;
	
	$text = $self->convert_markdown_to_ansi($text);
	$text =~ s/^(.*)$/$self->make_quote('olive_bg').$self->make_color($1,['bold','olive'])/egm;
	print $text;
	$suppress_newline || print "\n";
}

sub error {
	my $self = shift || return;
	my $text = shift;
	my $suppress_newline = shift;
	$text = $self->convert_markdown_to_ansi($text);
	$text = 'ERROR: ' . $text;
	$text =~ s/^(.*)$/$self->make_quote('maroon_bg').$self->make_color($1,['bold','maroon'])/egm;
	print STDERR $text;
	$suppress_newline || print "\n";
}


sub get_answer {
#=====================================================

=head2 B<get_answer>

 defined(my $answer = $self->{cli}->get_answer) || return;
 defined(my $answer = $self->{cli}->get_answer($array_of_inputs) || return;

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

sub prompt {
#=====================================================

=head2 B<prompt>

 defined(my $answer = $self->{cli}->prompt($label, $preinputs, $regex, $invalid_message)) || exit;

=cut
#=====================================================
	my $self = shift || return;
	my $label = shift || '?';
	my $preinputs = shift || [];
	my $regex = shift;
	my $invalid = shift || 'Invalid input';
	
	my $answer;
	while (42) {
		$self->body("$label: ", TRUE);
		defined($answer = $self->get_answer($preinputs)) || exit;
		if ($regex && ($answer !~ /$regex/)) {
			$self->warning($invalid);
			$preinputs = [];
		} else { last; }
	}
	return $answer || '';
}

sub make_index {
	my $self = shift || return;
	my $width = shift;
	my $i = shift;
	if (is_pos_int($i)) {
		return $self->make_color('[', ['gray', 'bold']) . $self->make_color(sprintf("%${width}d", $i), ['azure', 'bold']) . $self->make_color(']', ['gray', 'bold']);
	} else {
		return $self->make_color('[', ['gray', 'bold']) . $self->make_color($i, ['azure', 'bold']) . $self->make_color(']', ['gray', 'bold']);
	}
}

sub get_menu_answer {
#=====================================================

=head2 B<get_menu_answer>

Returns an answer from an array of choices:

 my $value = $self->{cli}->get_menu_answer($choices_as_array, $label) || exit;
 my $value = $self->{cli}->get_menu_answer($choices_as_array, $label, {
 	key_name	=> $key_name,	# optional, but requires value_name
 	value_name	=> $value_name,	# optional, but requires key_name
 	inputs		=> $inputs		# optional
 }) || exit;
 my $hash = $self->{cli}->get_menu_answer($choices_as_arrayhash, $label, {
 	key_name	=> $key_name,
 	inputs		=> $inputs		# optional
 }) || exit;

=cut
#=====================================================
	my $self = shift || return;
	my $choices = shift || return;
	my $label = shift;
	my $options = shift;
	
	is_array_with_content($choices) || return;
	if (!is_hash($options)) { $options = {}; }
	my $inputs = $options->{inputs};
	my $key_name = $options->{key_name};
	my $value_name = $options->{value_name};
	my $default = $options->{default};
	
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
		printf("  %s %s\n", $self->make_index($index_width, $i+1), $self->make_color($key, 'maroon'));
	}
	if (!$pre_input && is_pos_int($input, 1, ($array_length+1))) {
		$pre_input = $input;
	}
	
	my $answer;
	if ($pre_input && is_pos_int($pre_input)) { $pre_input = [$pre_input]; }
	while (42) {
		if ($default) { printf("  %s %s\n", $self->make_index(7,'default'), $self->make_color($default, 'maroon')); }
		print "$label [1 - " . $array_length . "]: ";
		defined($answer = $self->get_answer($pre_input)) || return;
		if (is_pos_int($answer, 1, $array_length)) { last; }
		if (is_text($answer)) { $self->warning("The answer must be a number from 1 to " . $array_length); @{$inputs} = (); }
		elsif ($default) { return $default; }
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
		{ name => 'gray_bg',		num => 100 },
		{ name => 'black_bg',		num => 40 },
		
		{ name => 'red_bg',			num => 101 },
		{ name => 'maroon_bg',		num => 41 },
		{ name => 'yellow_bg',		num => 103 },
		{ name => 'olive_bg',		num => 43 },
		{ name => 'lime_bg',		num => 102 },
		{ name => 'green_bg',		num => 42 },
		{ name => 'cyan_bg',		num => 106 },
		{ name => 'teal_bg',		num => 46 },
		{ name => 'blue_bg',		num => 104 },
		{ name => 'azure_bg',		num => 44 },
		{ name => 'pink_bg',		num => 105 },
		{ name => 'magenta_bg',		num => 45 },
		
		{ name => 'reset_bg',		num => 49 }
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
				printf("%14s: ${s}m%-14s$e ${s};1m%-14s$e ${s};2m%-14s$e ${s};7m%-14s$e\n", $name, $name, $name, $name, $name);
			}
		}
	}
	if ($debug) {
		print "\n";
		$self->info("This is info");
		$self->error("This is an error\n  Line 2");
		$self->warning("This is a warning\n  Line 2");
		$self->title("This is a title");
		$self->header("This is a header");
		$self->bold("This is bold");
		$self->body("This is a body");
		$self->body("> This is a quote");
		$self->success("This is success");
		$self->mark("This is a mark");
		print "\n";
	}
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

sub make_style {
	my $self = shift || return;
	my $text = shift || '';	
	my $class = shift || return;
	my $style = shift || return;
	my $attributes = $self->get_style($class, $style);
	return $self->make_color($text, $attributes);
}

sub make_color {
	my $self = shift || return;
	my $text = shift;
	my $color = shift || 'bold';
	my $bg = shift;
	if (!defined($text)) { $text = ''; }
	_term_supports_colors() || return $text;
	my $debug = shift;
	if (!defined($text)) { $text = ''; }
	
	if ($bg) {
		if (is_array($color)) { push(@{$color}, "${bg}_bg"); }
		else { $color = [$color, "${bg}_bg"]; }
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

sub make_quote {
	my $self = shift || return;
	my $color_name = shift || 'silver_bg';
	my $debug = shift;
	_term_supports_colors() || return '| ';
	if ($color_name !~ /_bg$/) { return '| '; }
	
	my $color_code = $self->get_term_color($color_name);
	my $reset_code = $self->get_term_color('reset_bg');
	return "${color_code} ${reset_code} ";
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
	my $text = shift;
	$self->{silent} && return;
	
	$text = $self->convert_markdown_to_ansi($text);
	print $self->make_color($text, 'bold');
}

sub say_bold {
	my $self = shift || return;
	$self->{silent} && return;
	
	$self->print_bold(shift);
	print "\n";
}

sub convert_markdown_to_ansi {
	my $self = shift || return;
	my $text = shift;
	if (!defined($text)) { $text = ''; }
	$self->{use_markdown} || return $text;
	_term_supports_colors() || return $text;
# 	$text =~ s/(?:^|(?<=\s))\*(\S.*?)\*/\e[1m$1\e[21m/g;
	$text =~ s/(?:^|(?<=\s))\*(\S.*?)\*/\e[1m$1\e[0m/g;
	$text =~ s/(?:^|(?<=\s))\_(\S.*?)\_/\e[4m$1\e[24m/g;
	$text =~ s/(?:^|(?<=\s))\~(\S.*?)\~/\e[7m$1\e[27m/g;
	$text =~ s/(?:^|(?<=\s))\`(\S.*?)\`/$self->make_color($1,'red','silver')/eg;
	$text =~ s/^>/$self->make_quote('silver_bg')/egm;
	return $text;
}

sub get_callers {
	my $start = shift || 1;
	my $trail = [];
	for (my $i = $start; $i < 100; $i++) {
		my @caller = caller($i);
		$caller[0] || last;
		
		my $subroutine = $caller[0];
		my $line = $caller[2];
		
		my @caller2 = caller($i + 1);
		if ($caller2[0]) {
			$subroutine = $caller2[3];
		}
		if ($subroutine =~ /^main\b/) {
			my ($script) = $caller[1] =~ m#.*/(.*?)$#;
			$subroutine =~ s/^main\b/$script/;
		}
		my $summary = "$subroutine - Line $line";
		push(@{$trail}, $summary);
	}
	return $trail;
}

sub get_debug_header {
	my $callers = get_callers(2);
	my $ts = get_timestamp;
	return "[$ts] $callers->[0]";
}

sub trace {
	my $self = shift;
	my $label;
	if (is_object($self)) {
		$label = shift;
	} else {
		$label = $self;
		$self = SitemasonPl::CLI->new();
	}
	$label ||= 'Trace';
	
	my $callers = get_callers(2);
	my $ts = get_timestamp;
	$self->print_object($callers, "[$ts] $label");
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
	
	my $header = get_debug_header;
	state $counter = 0;
	print $self->make_color(' ' . $counter++ . ' ', ['bold', 'inverse']) . 
		$self->bold(" ${label}===> $header") . "\n";
}

sub print_object {
#=====================================================

=head2 B<print_object>

	print_object($object, $label, {
		indent		=> 4,	# number of spaces to indent
		limit		=> 3,	# limit number of items to display from an array or hash at the top level
		inner_limit	=> 3	# limit number of items to display from an array or hash at lower depths
		depth		=> 2,	# limit the depth to recurse,
		output		=> 'perl' || 'json'
	});

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
	my $args = shift || {};
	if (!is_hash($args)) {
		$args = {
			indent	=> $args,
			limit	=> shift
		};
	}
	$self->{silent} && return;
	
	my $indent = $args->{indent} || 0;
	if ($args->{format}) { $self->change_format($args->{format}); }
	$args->{output} ||= 'default';
	
	my $string = $self->convert_object_to_string($object, undef, $args);
	my $indent_string = ' ' x $indent;
	my $quote_style = $self->get_style('print_object', 'quote');
	if ($quote_style) { $indent_string = $self->make_quote($quote_style) . $indent_string; }
	$string =~ s/\n/\n$indent_string/gs;
	if (($args->{output} eq 'perl') || ($args->{output} eq 'json')) {
		$string =~ s/\Q$indent_string\E$/;/;
	} else {
		$string =~ s/\Q$indent_string\E$//;
	}
	if ($label) {
		$label = $self->make_style($label, 'print_object', 'label');
		if (($args->{output} eq 'perl') || ($args->{output} eq 'json')) {
			print "$indent_string$label = $string";
		} else {
			print "$indent_string$label: $string";
		}
	} else {
		print "$indent_string$string";
	}
	if ($args->{format}) { $self->change_format; }
}

sub _convert_object_to_string_key {
	my $self = shift || return;
	my $key = shift;
	my $value = shift;
	my $args = shift;
	if ($args->{output} eq 'json') { $key = "'$key'"; }
	my $printKey = $key;
	if (is_hash($value)) { $printKey = $self->make_style($key, 'print_object', 'hash_key'); }
	elsif (is_array($value)) { $printKey = $self->make_style($key, 'print_object', 'array_key'); }
	else { $printKey = $self->make_style($key, 'print_object', 'key'); }
	return $printKey;
}
sub convert_object_to_string {
	my $self = shift || return;
	my $object = shift;
	my $level = shift || 0;
	my $args = shift;
	my $limit = $args->{limit};
	if ($level > 0) { $limit = $args->{inner_limit}; }
	my $depth = $args->{depth};
	my $key_size = 20;
	
	my $string = '';
	my $spacing = '.   ';
	my $quote = '"';
	if ($args->{output} eq 'json') { $quote = "'"; }
	my $pointer = $self->make_style('=>', 'print_object', 'pointer');
	if ($args->{output} eq 'json') { $pointer = $self->make_style(':', 'print_object', 'pointer'); }
	my $comma = $self->make_style(',', 'print_object', 'comma');
	if ($args->{output} eq 'perl' || $args->{output} eq 'json') { $spacing = $self->make_style('    ', 'print_object', 'indent'); }
	elsif (_term_supports_colors()) { $spacing = $self->make_style('+---', 'print_object', 'indent'); }
	my $indent = $spacing x $level;
	
	if (is_hash($object)) {
		if ($depth && ($level >= $depth)) {
			my $fullKey = sprintf("%s - %d %s", $object, scalar keys %{$object}, pluralize('key', scalar keys %{$object}) );
			$string = $self->_convert_object_to_string_key($fullKey, $object, $args);
			return "$string\n";
		}
		if (is_hash_with_content($object)) {
			my $opening = $self->make_style('{', 'print_object', 'braces');
			my $closing = $self->make_style('}', 'print_object', 'braces');
			
			if ($object =~ /^(.*?)=HASH/) {
				my $printObject = $self->make_style($1, 'print_object', 'hash');
				$string .= "$printObject $opening\n";
			} else {
				$string .= "$opening\n";
			}
			my $max = 0;
			foreach my $key (keys(%{$object})) {
				if ((length($key) > $max) && (length($key) <= $key_size)) { $max = length($key); }
			}
			
			# Sort keys according to number of keys
			my $key_total = scalar keys %{$object};
			my @sorted_keys;
			if ($key_total <= 100) { @sorted_keys = sort { by_any($a,$b) } keys %{$object}; }
			else { @sorted_keys = sort keys %{$object}; }
			
			my $cnt = 0;
			foreach my $key (@sorted_keys) {
				my $value = $object->{$key};
				my $printKey = $self->_convert_object_to_string_key($key, $value, $args);
				my $tempMax = $max + length($printKey) - length($key) ;
				$string .= sprintf("%s%s%-${tempMax}s $pointer ", $indent, $spacing, $printKey);
				$string .= $self->convert_object_to_string($value, $level + 1, $args);
				$cnt++;
				if ($limit && ($cnt >= $limit)) {
					my $fullKey = sprintf("... showing %d of %d hash keys", $limit, $key_total);
					my $printKey = $self->_convert_object_to_string_key($fullKey, {}, $args);
					$string .= sprintf("%s%s%s\n", $indent, $spacing, $printKey);
					last;
				}
			}
			$string =~ s/\Q$comma\E\n$/\n/;
			$string .= "$indent$closing$comma\n";
		} else {
			$string .= $self->make_style('{}', 'print_object', 'braces') . "$comma\n";
		}
	} elsif (is_array($object)) {
		if ($depth && ($level >= $depth)) {
			my $fullKey = sprintf("%s - %d %s", $object, scalar keys @{$object}, pluralize('element', scalar keys @{$object}) );
			$string = $self->_convert_object_to_string_key($fullKey, $object, $args);
			return "$string\n";
		}
		if (is_array_with_content($object)) {
			my $opening = $self->make_style('[', 'print_object', 'brackets');
			my $closing = $self->make_style(']', 'print_object', 'brackets');
			$string .= "$opening\n";
			my $arrayLength = @{$object};
			my $max = length($arrayLength);
			if ($max > $key_size) { $max = $key_size; }
			my $key = 0;
			foreach my $value (@{$object}) {
				my $fullKey = sprintf("[%${max}s]", $key);
				my $printKey = $self->_convert_object_to_string_key($fullKey, $value, $args);
				if ($args->{output} eq 'perl' || $args->{output} eq 'json') {
					$string .= sprintf("%s%s", $indent, $spacing);
				} else {
					$string .= sprintf("%s%s%s $pointer ", $indent, $spacing, $printKey);
				}
				$string .= $self->convert_object_to_string($value, $level + 1, $args);
				$key++;
				if ($limit && ($key >= $limit)) {
					my $fullKey = sprintf("... showing %d of %d array elements\n", $limit, scalar @{$object});
					$printKey = $self->_convert_object_to_string_key($fullKey, [], $args);
					$string .= sprintf("%s%s%s", $indent, $spacing, $printKey);
					last;
				}
			}
			$string =~ s/\Q$comma\E\n$/\n/;
			$string .= "$indent$closing$comma\n";
		} else {
			$string .= $self->make_style('[]', 'print_object', 'brackets') . "$comma\n";
		}
	} elsif (ref($object) eq 'CODE') {
		my $cv = svref_2object ( $object );
		my $gv = $cv->GV;
		my $printObject = $self->make_style("sub " . $gv->NAME, 'print_object', 'code');
		$string .= "$printObject$comma\n";
	} elsif (ref($object) eq 'SCALAR') {
		my $output = ${$object} || '';
		$output =~ s/\n/\\n/gm;
		$output =~ s/\r/\\r/gm;
		my $printObject = $self->make_style($quote . $output . $quote, 'print_object', 'scalar');
		$string .= "scalar $printObject$comma\n";
	} elsif (ref($object)) {
		my $printObject = $self->make_style($object, 'print_object', 'ref');
		$string .= "$printObject$comma\n";
	} elsif (!defined($object)) {
		my $printObject = $self->make_style('undef', 'print_object', 'undef');
		$string .= "$printObject$comma\n";
	} else {
		$object =~ s/\n/\\n/gm;
		$object =~ s/\r/\\r/gm;
		my $printObject = $self->make_style($quote . $object . $quote, 'print_object', 'other');
		$string .= "$printObject$comma\n";
	}
	if (!$level) { $string =~ s/\Q$comma\E\n$/\n/; }
	return $string;
}

sub debug_object {
	my $self = shift;
	my $object;
	if (!is_object($self)) {
		$self = SitemasonPl::CLI->new();
	}
	my $header = get_debug_header;
	$self->say_bold($header);
	$self->print_object(@_);
}

sub init_formats {
	my $self = shift || return;
	$self->{stored_formats} = {
		'default'		=> {
			print_object	=> {
				array_key		=> ['azure', 'bold'],
				braces			=> ['green', 'bold'],
				brackets		=> ['blue', 'bold'],
				code			=> 'blue',
				comma			=> 'default',
				hash			=> 'teal',
				hash_key		=> ['green', 'bold'],
				indent			=> 'silver',
				key				=> ['gray', 'bold'],
				label			=> 'bold',
				other			=> 'maroon',
				pointer			=> 'default',
				quote			=> undef,
				'ref'			=> 'olive',
				'scalar'		=> 'maroon',
				'undef'			=> 'line'
			}
		},
		dry_run			=> {
			print_object	=> {
				array_key		=> 'gray',
				braces			=> 'gray',
				brackets		=> 'gray',
				code			=> 'gray',
				comma			=> 'gray',
				hash			=> 'gray',
				hash_key		=> 'gray',
				indent			=> 'silver',
				key				=> 'gray',
				label			=> 'gray',
				other			=> 'gray',
				pointer			=> 'gray',
				quote			=> 'silver_bg',
				'ref'			=> 'gray',
				'scalar'		=> 'gray',
				'undef'			=> 'gray'
			}
		}
	};
	$self->change_format;
}

sub change_format {
	my $self = shift || return;
	my $format = shift || 'default';
	if (!value($self->{stored_formats}, $format)) { $format = 'default'; }
	
	$self->{format} = $self->{stored_formats}->{$format};
}

sub get_style {
	my $self = shift || return;
	my $class = shift || return;
	my $style = shift || return;
	if (value($self->{format}, [$class, $style])) {
		return $self->{format}->{$class}->{$style};
	}
}


=head1 CHANGES

  2014-03-20 TJM - v1.0 Started development
  2017-11-09 TJM - v8.0 Moved to SitemasonPl open source project and merged with updates

=head1 AUTHOR

  Tim Moses <tim@moses.com>
  Sitemason Open Source <https://github.com/sitemason>

=cut

1;
