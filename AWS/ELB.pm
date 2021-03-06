package SitemasonPl::AWS::ELB 1.0;
@ISA = qw( SitemasonPl::AWS );

=head1 NAME

ELB

=head1 DESCRIPTION

ELB functions

=cut

use v5.012;
use strict;
use warnings;
use utf8;
use constant TRUE => 1;
use constant FALSE => 0;

use JSON;

use lib qw( /opt/lib/site_perl );
use SitemasonPl::AWS;
use SitemasonPl::Batch;
use SitemasonPl::Common;
use SitemasonPl::IO qw(mark print_object);


sub new {
#=====================================================

=head2 B<new>

 use SitemasonPl::AWS::ELB;
 my $elb = SitemasonPl::AWS::ELB->new(
	io			=> $self->{io},
	dry_run		=> $self->{dry_run}
 ) || die "Failed to instantiate ELB\n";

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


sub get_target_groups {
#=====================================================

=head2 B<get_target_groups>

	my $target_groups = $elb->get_target_groups;

=cut
#=====================================================
	my $self = shift || return;
	my $debug = shift;
	
	my $response = $self->_call_elbv2("describe-target-groups", $debug, $self->{dry_run});
	return $response->{TargetGroups};
}


sub get_target_group_healthy_host_count {
#=====================================================

=head2 B<get_target_group_healthy_host_count>

	my $healthy_host_count = $elb->get_target_group_healthy_host_count($target_group_arn);

=cut
#=====================================================
	my $self = shift || return;
	my $target_group_arn = shift || return;
	my $debug = shift;
	
	my $response = $self->_call_elbv2("describe-target-health --target-group-arn $target_group_arn", $debug, $self->{dry_run});
	if ($self->{dry_run}) { return 1; }
	is_array($response->{TargetHealthDescriptions}) || return;
	my $health_host_count = 0;
	foreach my $desc (@{$response->{TargetHealthDescriptions}}) {
		if (value($desc, ['TargetHealth', 'State']) eq 'healthy') { $health_host_count++; }
	}
	return $health_host_count;
}


sub _call_elbv2 {
#=====================================================

=head2 B<_call_elbv2>

=cut
#=====================================================
	my $self = shift || return;
	my $args = shift || return;
	my $debug = shift;
	my $dry_run = shift;
	
	return $self->SUPER::_call_aws("elbv2 $args", $debug, $dry_run);
}



=head1 CHANGES

  2018-07-25 TJM - v1.0 Started

=head1 AUTHOR

  Tim Moses <tim@moses.com>
  Sitemason Open Source <https://github.com/sitemason>

=cut

1;
