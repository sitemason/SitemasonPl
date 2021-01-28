package SitemasonPl::AWS::ECS 1.0;
@ISA = qw( SitemasonPl::AWS );

=head1 NAME

ECS

=head1 DESCRIPTION

ECS functions

=cut

use v5.012;
use strict;
use warnings;
use utf8;
use constant TRUE => 1;
use constant FALSE => 0;

use lib qw( /opt/lib/site_perl );
use SitemasonPl::AWS;
use SitemasonPl::AWS::Launch_Template;
use SitemasonPl::Batch;
use SitemasonPl::Common;
use SitemasonPl::IO qw(mark print_object);


sub new {
#=====================================================

=head2 B<new>

 use SitemasonPl::AWS::ECS;
 my $ecs = SitemasonPl::AWS::ECS->new();
 my $ecs = SitemasonPl::AWS::ECS->new(
	io		=> $self->{io},
	dry_run	=> $self->{dry_run}
 );

=cut
#=====================================================
	my ($class, %arg) = @_;
	$class || return;
	
	my $self = {
		io			=> $arg{io},
		dry_run		=> $arg{dry_run}
	};
	if (!$self->{io}) { $self->{io} = SitemasonPl::IO->new; }
	
	bless $self, $class;
	return $self;
}


sub get_clusters {
#=====================================================

=head2 B<get_clusters>

 my $clusters = $ecs->get_clusters($array_of_cluster_names);
 my $clusters = $ecs->get_clusters($cluster_name);

=cut
#=====================================================
	my $self = shift || return;
	my $identifier = shift || '';
	my $debug = shift;
	
	my $arg = '';
	if (is_array($identifier)) { $arg = " --cluster " . join(' ', @{$identifier}); }
	elsif ($identifier) { $arg = " --cluster $identifier"; }
	
	my $response = $self->_call_ecs("describe-clusters$arg", $debug);
	if (is_array($response->{clusters})) {
		my $records = $response->{clusters};
		$debug && $self->{io}->print_object($records, '$records', { limit => 3 });
		return $records;
	}
}

sub get_service_arns {
#=====================================================

=head2 B<get_service_arns>

 my $service_arns = $ecs->get_service_arns($cluster_name);

=cut
#=====================================================
	my $self = shift || return;
	my $identifier = shift || '';
	my $debug = shift;
	
	my $arg = '';
	if (is_array($identifier)) { $arg = " --cluster " . join(' ', @{$identifier}); }
	elsif ($identifier) { $arg = " --cluster $identifier"; }
	
	my $response = $self->_call_ecs("list-services$arg", $debug);
	if (is_array($response->{serviceArns})) {
		my $records = $response->{serviceArns};
		$debug && $self->{io}->print_object($records, '$records', { limit => 3 });
		return $records;
	}
}

sub get_service {
#=====================================================

=head2 B<get_service>

 my $service = $ecs->get_service($cluster_name, $service_name);

=cut
#=====================================================
	my $self = shift || return;
	my $cluster_name = shift || return;
	my $service_name = shift || return;
	my $debug = shift;
	
	my $arg = " --cluster $cluster_name --services $service_name";
	
	my $response = $self->_call_ecs("describe-services$arg", $debug);
	if (is_array_with_content($response->{services})) {
		my $records = $response->{services}->[0];
		$debug && $self->{io}->print_object($records, '$records', { limit => 3 });
		return $records;
	}
}



sub _call_ecs {
#=====================================================

=head2 B<_call_ecs>

=cut
#=====================================================
	my $self = shift || return;
	my $args = shift || return;
	my $debug = shift;
	my $dry_run = shift;
	
	return $self->SUPER::_call_aws("ecs $args", $debug, $dry_run);
}



=head1 CHANGES

  2021-01-27 TJM - v1.0 Started

=head1 AUTHOR

  Tim Moses <tim@moses.com>
  Sitemason Open Source <https://github.com/sitemason>

=cut

1;
