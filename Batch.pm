package SitemasonPl::Batch 8.0;

=head1 NAME

Batch

=head1 DESCRIPTION

Mainly a placeholder until I get the old code in here.

With $container:

 use SitemasonPl::Batch;
 
 my $batch = SitemasonPl::Batch->new(
  	batch_size => 3,
  	process => sub {
 		my $payload = shift;
 		my $container = shift;
 		print Dumper($payload, $container);
 	},
 	debug => TRUE
 );
 
 my $container = {};
 foreach my $item (@array) {
 	$batch->add($item, $container);
 }
 $batch->end($container);

Without $container:

 use SitemasonPl::Batch;
 
 my $batch = SitemasonPl::Batch->new(
  	batch_size => 3,
  	process => sub {
 		my $payload = shift;
 		print Dumper($payload);
 	},
 	debug => TRUE
 );
 
 foreach my $item (@array) {
 	$batch->add($item);
 }
 $batch->end;

=cut

use v5.012;
use strict;
use utf8;
use constant TRUE => 1;
use constant FALSE => 0;

use SitemasonPl::Common;


sub new {
#=====================================================

=head2 B<new>

 my $batch = SitemasonPl::Batch->new(
  	batch_size => 3,
  	process => sub {
 		my $payload = shift;
 		my $container = shift;	# optional
 		# Handle batch functions on items in @{$payload}.
 	},
 	debug => TRUE || FALSE
 );

=cut
#=====================================================
	my ($class, %arg) = @_;
	$class || return;
	
	my $self = {
		batch_size	=> $arg{batch_size},
		debug		=> $arg{debug},
		process		=> $arg{process},
		payload		=> [],
		item_count	=> 0,
		item_total	=> 0,
		batch_count	=> 1,
		batch_total	=> 0
	};
	if ($self->{debug}) { print "Batch: new\n"; }
	
	bless $self, $class;
	return $self;
}


sub add {
#=====================================================

=head2 B<add>

 $batch->add($item);
 $batch->add($item, $container);

	foreach my $item (@{$items}) {
		$batch->add($item, $container);
	}


=cut
#=====================================================
	my $self = shift || return;
	my $item = shift;
	my $container = shift;
	$self->{item_total}++;
	
	push(@{$self->{payload}}, $item);
	$self->{item_count} = @{$self->{payload}};
	
# 	if ($self->{debug}) { print "Batch $self->{batch_count}: add\n"; }
	
	
	if ($self->{item_count} >= $self->{batch_size}) {
		$self->{batch_total}++;
		if ($self->{debug}) { print "Batch $self->{batch_count}: process\n"; }
		
		&{$self->{process}}($self->{payload}, $container);
		$self->{payload} = [];
		$self->{item_count} = 0;
		$self->{batch_count}++;
	}
}


sub end {
#=====================================================

=head2 B<end>

 $batch->end;
 $batch->end($container);

=cut
#=====================================================
	my $self = shift || return;
	my $container = shift;
	$self->{item_count} = @{$self->{payload}};
	if ($self->{item_count}) {
		$self->{batch_total}++;
		if ($self->{debug}) { print "Batch: $self->{batch_count} process\n"; }
		
		&{$self->{process}}($self->{payload}, $container);
	}
	
	if ($self->{debug}) {
		print "Batch: total items: $self->{item_total}\n";
		print "Batch: total batches: $self->{batch_total}\n";
	}
}



=head1 CHANGES

  ???????? TJM - v1.0 copied from various places
  20171011 TJM - v2.0 Open sourced
  20171109 TJM - v8.0 Merged with SitemasonPl open source project

=head1 AUTHOR

  Tim Moses <tim@moses.com>
  Sitemason Open Source <https://github.com/sitemason>

=cut

1;
