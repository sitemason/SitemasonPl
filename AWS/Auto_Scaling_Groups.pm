package SitemasonPl::AWS::Auto_Scaling_Groups 1.0;
@ISA = qw( SitemasonPl::AWS );

=head1 NAME

Auto_Scaling_Groups

=head1 DESCRIPTION

Auto Scaling Group functions

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
use SitemasonPl::CLI qw(mark print_object);


sub new {
#=====================================================

=head2 B<new>

 use SitemasonPl::AWS::Auto_Scaling_Groups;
 my $asg = SitemasonPl::AWS::Auto_Scaling_Groups->new;

=cut
#=====================================================
	my ($class, %arg) = @_;
	$class || return;
	
	my $self = {
		cli			=> $arg{cli},
		dry_run		=> $arg{dry_run},
	};
	if (!$self->{cli}) { $self->{cli} = SitemasonPl::CLI->new; }
	
	bless $self, $class;
	return $self;
}


sub get_auto_scaling_groups {
#=====================================================

=head2 B<get_auto_scaling_groups>

	my $auto_scaling_groups = $asg->get_auto_scaling_groups;

	my $auto_scaling_group = $asg->get_auto_scaling_groups($asg_name);

=cut
#=====================================================
	my $self = shift || return;
	my $asg_name = shift;
	my $debug = shift;
	
	my $asg_name_string = '';
	if ($asg_name) { $asg_name_string = " --auto-scaling-group-names $asg_name"; }
	
	my $response = $self->_call_asg("describe-auto-scaling-groups$asg_name_string", $debug);
	if ($asg_name) {
		return $response->{AutoScalingGroups}->[0];
	} else {
		return $response->{AutoScalingGroups};
	}
}


sub set_min_size {
#=====================================================

=head2 B<set_min_size>

	$asg->set_min_size($asg_name, $min_size);

=cut
#=====================================================
	my $self = shift || return;
	my $asg_name = shift || return;
	my $min_size = shift;
	my $debug = shift;
	is_pos_int($min_size) || return;
	
	my $auto_scaling_group = $self->get_auto_scaling_groups($asg_name);
	is_hash($auto_scaling_group) || return;
	my $desired_capacity = $auto_scaling_group->{DesiredCapacity};
	my $desired_capacity_string = '';
	if ($desired_capacity < $min_size) {
		$desired_capacity_string = " --desired-capacity $min_size";
	}
	
	my $response = $self->_call_asg("update-auto-scaling-group --auto-scaling-group-name $asg_name --min-size $min_size$desired_capacity_string", $debug, $self->{dry_run});
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
