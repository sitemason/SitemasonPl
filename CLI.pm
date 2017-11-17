package SitemasonPl::CLI 8.0;

=head1 NAME

SitemasonPl::CLI

=head1 DESCRIPTION

[description]

=cut

use v5.012;
use strict;
use warnings;
use utf8;
use constant TRUE => 1;
use constant FALSE => 0;

use lib qw( /opt/lib/site_perl );
use SitemasonPl::Common;
use SitemasonPl::CLI::Table;


#=====================================================

=head2 B<new>

 my $cli = SitemasonPl::CLI->new();

=cut
#=====================================================
sub new {
	my ($class, %arg) = @_;
	$class || return;
	
	my $self = {};
	
	bless $self, $class;
	return $self;
}



sub info {
	my $self = shift || return;
	my $text = shift;
	print "$text\n";
}

sub body {
	my $self = shift || return;
	my $text = shift;
	say($text);
}

sub header {
	my $self = shift || return;
	my $text = shift;
	$self->say_bold($text);
}

sub error {
	my $self = shift || return;
	my $text = shift;
	$self->say_bold("ERROR: $text");
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
	if (ord($answer) == 0) { print "\n"; return; }
	if ($answer =~ /^exit/) { print "\n"; return; }
	chomp($answer);
	$answer =~ s/(?:^\s+|\s+$)//g;
	if (!length($answer)) { return ""; }
	if (!$answer) { return '0'; }
	return $answer;
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
	my $self = shift || return;
	my $label = shift;
	if ($label) { $label .= ' '; }
	
	my @returns = caller(1);
	my $location = "$returns[3] - Line $returns[2]";
	if (!@returns) { @returns = caller(0); $location = "$returns[1] - Line $returns[2]"; }
	
	state $counter = 0;
	print $self->make_color(' ' . $counter++ . ' ', ['bold', 'inverse']) . 
		$self->bold(" ${label}===> $location") . "\n";
}

sub print_object {
#=====================================================

=head2 B<print_object>

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
	my $self = shift || return;
	my $object = shift;
	my $label = shift || '';
	my $indent = shift || 0;
	
	if ($label) { $label = $self->make_color($label, 'bold'); }
	my $string = $self->convert_object_to_string($object);
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
			while (my($key, $value) = each(%{$object})) {
				if ((length($key) > $max) && (length($key) <= 20)) { $max = length($key); }
			}
			foreach my $key (sort { by_any($a,$b) } keys %{$object}) {
				my $value = $object->{$key};
				my $printKey = $self->_convert_object_to_string_key($key, $value);
				my $tempMax = $max + length($printKey) - length($key) ;
				$string .= sprintf("%s%s%-${tempMax}s => ", $indent, $spacing, $printKey);
				$string .= $self->convert_object_to_string($value, $level + 1);
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
			if ($max > 20) { $max = 20; }
			my $key = 0;
			foreach my $value (@{$object}) {
				my $fullKey = sprintf("[%${max}s]", $key);
				my $printKey = $self->_convert_object_to_string_key($fullKey, $value);
				$string .= sprintf("%s%s%s => ", $indent, $spacing, $printKey);
				$string .= $self->convert_object_to_string($value, $level + 1);
				$key++;
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
		${$object} =~ s/\n/\\n/gm;
		${$object} =~ s/\r/\\r/gm;
		my $printObject = $self->make_color('"' . ${$object} . '"', 'maroon');
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
