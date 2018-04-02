package SitemasonPl::CLI::Table 8.0;
@ISA = qw( SitemasonPl::CLI );

=head1 NAME

SitemasonPl::CLI::Table

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
use SitemasonPl::CLI;
use SitemasonPl::Common;

#=====================================================

=head2 B<new>

 SitemasonPl::CLI::Table->new(columns => [ {
 	name	=> $column_name,
 	width	=> $int_width,
 	format	=> $sprintf_format
 } ], label => $label);

 SitemasonPl::CLI::Table->new(columns => [ {
		name	=> 'v',
		width	=> 2
	}, {
		name	=> 'id',
		width	=> 7,
		format	=> '%7d'
	}, {
		name	=> 'title',
		width	=> 30
 } ], $label);

=cut
#=====================================================
sub new {
	my ($class, %arg) = @_;
	$class || return;
	is_array($arg{columns}) || return;
	
	my $self = {
		columns			=> $arg{columns},
		use_plain_text	=> $arg{use_plain_text},
		suppress_colors	=> $arg{suppress_colors},
		display_nulls	=> $arg{display_nulls},
		post_args		=> { header => FALSE, output => 'stdout' }
	};
	bless $self, $class;
	
	$self->{width} = 0;
	my $first = TRUE;
	foreach my $column (@{$self->{columns}}) {
		if (length($column->{name}) > $column->{width}) {
			$column->{width} = length($column->{name});
		}
		if ($first) { undef $first; }
		else { $self->{width}++; }
		$self->{width} += $column->{width} + 2;
	}
	
	if ($self->is_person && !$self->{use_plain_text}) { $arg{unicode} = TRUE; }
# 	if ($ENV{TERM} eq 'screen') { $arg{unicode} = FALSE; }
	
	if ($arg{unicode} && ($ENV{TERM} ne 'screen')) {
		$self->{char} = {
			ul		=> sprintf("%c", 0x250c),
			ut		=> sprintf("%c", 0x252c),
			ur		=> sprintf("%c", 0x2510),
			dul		=> sprintf("%c", 0x2552),
			dut		=> sprintf("%c", 0x2564),
			dur		=> sprintf("%c", 0x2555),
			lt		=> sprintf("%c", 0x251c),
			plus	=> sprintf("%c", 0x253c),
			rt		=> sprintf("%c", 0x2524),
			dlt		=> sprintf("%c", 0x255e),
			dplus	=> sprintf("%c", 0x256a),
			drt		=> sprintf("%c", 0x2561),
			bl		=> sprintf("%c", 0x2514),
			bt		=> sprintf("%c", 0x2534),
			br		=> sprintf("%c", 0x2518),
			
			hor		=> sprintf("%c", 0x2500),
			dhor	=> sprintf("%c", 0x2550),
			vert	=> sprintf("%c", 0x2502),
		};
	} else {
		$self->{char} = {
			ul		=> '+',
			ut		=> '+',
			ur		=> '+',
			lt		=> '+',
			plus	=> '+',
			rt		=> '+',
			dlt		=> '+',
			dplus	=> '+',
			drt		=> '+',
			bl		=> '+',
			bt		=> '+',
			br		=> '+',
			
			hor		=> '-',
			dhor	=> '=',
			vert	=> '|',
		};
	}
	
	if ($arg{label}) {
		$self->print_label($arg{label});
	}
	
# 	return $self->SUPER::new($data);
	return $self;
}

sub print_top {
	my $self = shift || return;
	$self->body($self->get_top(@_));
	return $self;
}

sub get_top {
	my $self = shift || return;
	my $type = shift || '';
	my $hor = $self->{char}->{hor};
	my $ut = $self->{char}->{ut};
	my $ul = $self->{char}->{ul};
	my $ur = $self->{char}->{ur};
	if ($type eq '=') {
		$hor = $self->{char}->{dhor};
		$ut = $self->{char}->{dut};
		$ul = $self->{char}->{dul};
		$ur = $self->{char}->{dur};
	}
	delete $self->{was_label};
	
	my $line;
	my $first = TRUE;
	foreach my $column (@{$self->{columns}}) {
		if ($first) { $line .= $ul; undef $first; }
		else { $line .= $ut; }
		$line .= $hor x ($column->{width} + 2);
	}
	$line .= $ur;
	$self->{was_top} = TRUE;
	return $line;
}

sub print_bottom {
	my $self = shift || return;
	$self->{was_top} || return;
	$self->body($self->get_bottom());
	return $self;
}

sub get_bottom {
	my $self = shift || return;
	
	$self->{was_top} || return;
	delete $self->{was_label};
	
	my $line;
	my $first = TRUE;
	foreach my $column (@{$self->{columns}}) {
		if ($first) { $line .= $self->{char}->{bl}; undef $first; }
		else { $line .= $self->{char}->{bt}; }
		$line .= $self->{char}->{hor} x ($column->{width} + 2);
	}
	$line .= $self->{char}->{br};
	delete $self->{was_top};
	return $line;
}

sub print_line {
	my $self = shift || return;
	my $type = shift || '';
	$self->{was_top} || return $self->print_top($type);
	$self->body($self->get_line($type));
	return $self;
}

sub get_line {
	my $self = shift || return;
	my $type = shift || '';
	
	my $hor = $self->{char}->{hor};
	my $plus = $self->{char}->{plus};
	my $lt = $self->{char}->{lt};
	my $rt = $self->{char}->{rt};
	if ($self->{was_label}) {
		$plus = $self->{char}->{ut};
	}
	if ($type eq '=') {
		$hor = $self->{char}->{dhor};
		$plus = $self->{char}->{dplus};
		$lt = $self->{char}->{dlt};
		$rt = $self->{char}->{drt};
		if ($self->{was_label}) {
			$plus = $self->{char}->{dut};
		}
	}
	delete $self->{was_label};
	
	my $line;
	my $first = TRUE;
	foreach my $column (@{$self->{columns}}) {
		if ($first) { $line .= $lt; undef $first; }
		else { $line .= $plus; }
		$line .= $hor x ($column->{width} + 2);
	}
	$line .= $rt;
	return $line;
}

sub print_label {
	my $self = shift || return;
	if (!$self->{was_top}) {
		$self->body($self->{char}->{ul} . $self->{char}->{hor} x $self->{width} . $self->{char}->{ur});
		$self->{was_top} = TRUE;
	}
	
	$self->body($self->get_label(@_));
	return $self;
}

sub get_label {
	my $self = shift || return;
	my $header = shift;
	
	my $line;
	if ($header) {
		my $width = $self->{width} - length($header) - 1;
		if (!$self->{suppress_colors}) { $header = $self->bold($header); }
		$line .= $self->{char}->{vert} . ' ' . $header . ' ' x $width . $self->{char}->{vert};
		$self->{was_label} = TRUE;
	}
	return $line;
}

sub print_header {
	my $self = shift || return;
	if (!$self->{was_top}) { $self->body($self->get_top); }
	$self->body($self->get_header(@_));
	return $self;
}

sub get_header {
	my $self = shift || return;
	
	my $line;
	delete $self->{was_label};
	
	my $row = {};
	my $args = {};
	foreach my $column (@{$self->{columns}}) {
		$row->{$column->{name}} = $column->{label} || $column->{name};
		$args->{$column->{name}}->{bold} = TRUE;
		$args->{$column->{name}}->{format} = FALSE;
	}
	$line .= $self->get_row($row, $args);
	return $line;
}

sub print_row {
	my $self = shift || return;
	if (!$self->{was_top}) { $self->body($self->get_top); }
	$self->body($self->get_row(@_));
	return $self;
}

sub get_row {
	my $self = shift || return;
	my $row = shift;
	my $args = shift;
	
	my $line;
	delete $self->{was_label};
	
	is_hash($row) || return;
	my $length = 1;
	foreach my $column (@{$self->{columns}}) {
		if (is_array_with_content($row->{$column->{name}})) {
			if (@{$row->{$column->{name}}} > $length) { $length = @{$row->{$column->{name}}}; }
		}
		if (is_hash_with_content($row->{$column->{name}})) {
			my $size = keys(%{$row->{$column->{name}}});
			if ($size > $length) { $length = $size; }
		}
	}
	for (my $i = 0; $i < $length; $i++) {
		if ($i > 0) { $line .= "\n"; }
		if ($length > 1) { $line .= '  '; }
		$line .= $self->{char}->{vert};
		foreach my $column (@{$self->{columns}}) {
			my $width = $column->{width};
			my $text = '';
			if (is_array($row->{$column->{name}})) {
				if ($i < @{$row->{$column->{name}}}) {
					$text = "[$i]: " . $self->to_string($row->{$column->{name}}->[$i], TRUE);
				}
			} elsif (is_hash($row->{$column->{name}})) {
				my @keys = sort keys(%{$row->{$column->{name}}});
				if ($i < @keys) {
					$text = $keys[$i] . ": " . $self->to_string($row->{$column->{name}}->{$keys[$i]}, TRUE);
				}
			} elsif (($i < 1) && exists($row->{$column->{name}})) {
				$text = $self->to_string($row->{$column->{name}});
			}
			my ($style, $color, $format);
			if ($column->{format}) { $format = TRUE; }
			if (is_hash($args)) {
				if (!$self->{suppress_colors}) {
					if ($args->{style} && $self->get_term_color($args->{style})) { $style = $args->{style}; }
					if ($args->{color} && $self->get_term_color($args->{color})) { $color = $args->{color}; }
				}
				if ($args->{$column->{name}}) {
					if (exists($args->{$column->{name}}->{format})) { $format = $args->{$column->{name}}->{format}; }
					
					if (!$self->{suppress_colors}) {
						if ($args->{$column->{name}}->{style} && $self->get_term_color($args->{$column->{name}}->{style})) {
							$style = $args->{$column->{name}}->{style};
						}
						elsif (exists($args->{$column->{name}}->{bold})) { $style = 'bold'; }
					
						if ($args->{$column->{name}}->{color} && $self->get_term_color($args->{$column->{name}}->{color})) {
							$color = $args->{$column->{name}}->{color};
						}
					}
				}
			}
			if ($format) {
				$text = sprintf($column->{format}, $text);
			} elsif (length($text) > $width) {
				$text = substr($text, 0, $column->{width} - 1) . '…';
			}
			my $uses_style;
			if ($style) {
				my $code = $self->get_term_color($style);
				$width += length($code);
				$text = $code . $text;
				$uses_style = TRUE;
			}
			if ($color) {
				my $code = $self->get_term_color($color);
				$width += length($code);
# 				if (($color =~ /^on/i) && ($color =~ /high$/i)) { $width += 1; }
				$text = $code . $text;
				$uses_style = TRUE;
			}
			if ($color || $style) { $width++; }
			if ($uses_style) {
				$width += 3;
				$text .= $self->get_term_color('reset');
			}
			$line .= ' ' . $text . ' ' x ($width - length($text)) . ' ' . $self->{char}->{vert};
		}
	}
	return $line;
}

sub close {
	my $self = shift || return;
	$self->print_bottom;
}

sub to_string {
	my $self = shift || return;
	my $value = shift;
	my $should_quote = shift;
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
	elsif (!defined($value)) {
		if ($self->{display_nulls}) { $string = '<N>'; }
		else { $string = ''; }
	}
	elsif (is_pos_int($value) && ($value eq ($value+0))) { $string = $value + 0; }
	elsif ($value) {
		if ($should_quote) { $string = "'$value'"; }
		else { $string = "$value"; }
	}
	else {
		if ($self->{display_nulls}) { $string = '<blank>'; }
		else { $string = ''; }
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
