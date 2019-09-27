package SitemasonPl::AWS::Auto_Scaling_Groups 1.0;
@ISA = qw( SitemasonPl::AWS );

=head1 NAME

Auto_Scaling_Groups

=head1 DESCRIPTION

Functions for managing Auto Scaling Groups

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

 use SitemasonPl::AWS::Auto_Scaling_Groups;
 my $asg = SitemasonPl::AWS::Auto_Scaling_Groups->new;
 my $asg = SitemasonPl::AWS::Auto_Scaling_Groups->new(
	io		=> $self->{io},
	dry_run	=> $self->{dry_run}
 );

=cut
#=====================================================
	my ($class, %arg) = @_;
	$class || return;
	
	my $self = {
		io			=> $arg{io},
		dry_run		=> $arg{dry_run},
	};
	if (!$self->{io}) { $self->{io} = SitemasonPl::IO->new; }
	
	bless $self, $class;
	return $self;
}


sub get_auto_scaling_groups {
#=====================================================

=head2 B<get_auto_scaling_groups>

	my $auto_scaling_groups = $asg->get_auto_scaling_groups;

	my ($auto_scaling_group, $asg_name) = $asg->get_auto_scaling_groups($auto_scaling_group || $asg_name);

=cut
#=====================================================
	my $self = shift || return;
	my $asg_name = shift;
	my $debug = shift;
	
	if (is_hash($asg_name)) { return ($asg_name, $asg_name->{AutoScalingGroupName}); }
	
	my $asg_name_string = '';
	if ($asg_name) { $asg_name_string = " --auto-scaling-group-names $asg_name"; }
	
	my $response = $self->_call_asg("describe-auto-scaling-groups$asg_name_string", $debug);
	if ($asg_name) {
		if (!is_hash($response->{AutoScalingGroups}->[0])) {
			$self->{io}->error("Auto scaling group \"$asg_name\" not found");
			return;
		}
		return ($response->{AutoScalingGroups}->[0], $asg_name);
	} else {
		return ($response->{AutoScalingGroups}, $asg_name);
	}
}



sub _call_asg {
#=====================================================

=head2 B<_call_asg>

=cut
#=====================================================
	my $self = shift || return;
	my $args = shift || return;
	my $debug = shift;
	my $dry_run = shift;
	
	return $self->SUPER::_call_aws("autoscaling $args", $debug, $dry_run);
}



=head1 CHANGES

  2018-07-27 TJM - v1.0 Started

=head1 AUTHOR

  Tim Moses <tim@moses.com>
  Sitemason Open Source <https://github.com/sitemason>

=cut

1;
