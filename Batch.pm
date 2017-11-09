package SitemasonPL::Batch;
$VERSION = '8.0';

=head1 NAME

Batch

=head1 DESCRIPTION

Mainly a placeholder until I get the old code in here.

With $container:

 use SitemasonPL::Batch;
 
 my $batch = SitemasonPL::Batch->new(
  	batchSize => 3,
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

 use SitemasonPL::Batch;
 
 my $batch = SitemasonPL::Batch->new(
  	batchSize => 3,
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

use strict;
use utf8;
use constant TRUE => 1;
use constant FALSE => 0;

use Data::Dumper;

use SitemasonPL::Common;


sub new {
#=====================================================

=head2 B<new>

 my $batch = SitemasonPL::Batch->new(
  	batchSize => 3,
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
		batchSize	=> $arg{batchSize},
		debug		=> $arg{debug},
		process		=> $arg{process},
		payload		=> [],
		itemCount	=> 0,
		itemTotal	=> 0,
		batchCount	=> 1,
		batchTotal	=> 0
	};
	if ($self->{debug}) { print "Batch: new\n"; }
	
	bless $self, $class;
	return $self;
}


sub add {
#=====================================================

=head2 B<add>

 $batch->add($item, [$container]);

=cut
#=====================================================
	my $self = shift || return;
	my $item = shift;
	my $container = shift;
	$self->{itemTotal}++;
	
	push(@{$self->{payload}}, $item);
	$self->{itemCount} = @{$self->{payload}};
	
# 	if ($self->{debug}) { print "Batch $self->{batchCount}: add\n"; }
	
	
	if ($self->{itemCount} >= $self->{batchSize}) {
		$self->{batchTotal}++;
		if ($self->{debug}) { print "Batch $self->{batchCount}: process\n"; }
		
		&{$self->{process}}($self->{payload}, $container);
		$self->{payload} = [];
		$self->{itemCount} = 0;
		$self->{batchCount}++;
	}
}


sub end {
#=====================================================

=head2 B<end>

 $batch->end([$container]);

=cut
#=====================================================
	my $self = shift || return;
	my $container = shift;
	$self->{itemCount} = @{$self->{payload}};
	if ($self->{itemCount}) {
		$self->{batchTotal}++;
		if ($self->{debug}) { print "Batch:     $self->{batchCount} process\n"; }
		
		&{$self->{process}}($self->{payload}, $container);
	}
	
	if ($self->{debug}) {
		print "Batch: total items: $self->{itemTotal}\n";
		print "Batch: total batches: $self->{batchTotal}\n";
	}
}



=head1 CHANGES

  ???????? TJM - v1.0 copied from various places
  20171011 TJM - v2.0 Open sourced
  20171109 TJM - v8.0 Merged with SitemasonPL open source project

=head1 AUTHOR

  Tim Moses <tim@moses.com>
  Sitemason Open Source <https://github.com/sitemason>

=cut

1;
