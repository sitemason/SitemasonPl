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


sub get_healthy_instance_count {
#=====================================================

=head2 B<get_healthy_instance_count>

	my $count = $asg->get_healthy_instance_count($asg_name);
	my $count = $asg->get_healthy_instance_count($auto_scaling_group);

=cut
#=====================================================
	my $self = shift || return;
	my $asg_input = shift || return;
	my $debug = shift;
	
	my ($auto_scaling_group, $asg_name) = $self->get_auto_scaling_groups($asg_input);
	is_hash($auto_scaling_group) || return;
	
	if (is_array($auto_scaling_group->{Instances})) {
		my $count = 0;
		foreach my $instance (@{$auto_scaling_group->{Instances}}) {
			if ($instance->{HealthStatus} eq 'Healthy') { $count++; }
		}
		return $count;
	} else {
		return 0;
	}
}


sub set_desired_capacity {
#=====================================================

=head2 B<set_desired_capacity>

	$asg->set_desired_capacity($asg_name, $desired_capacity);
	$asg->set_desired_capacity($auto_scaling_group, $desired_capacity);

=cut
#=====================================================
	my $self = shift || return;
	my $asg_input = shift || return;
	my $desired_capacity = shift;
	my $debug = shift;
	is_pos_int($desired_capacity) || return;
	
	my ($auto_scaling_group, $asg_name) = $self->get_auto_scaling_groups($asg_input);
	is_hash($auto_scaling_group) || return;
	
	my $min_size = $auto_scaling_group->{MinSize};
	my $max_size = $auto_scaling_group->{MaxSize};
	if ($desired_capacity < $min_size) {
		$self->{io}->error("Cannnot set desired capacity of $desired_capacity to less than the minimum size of $min_size");
		return;
	} elsif ($desired_capacity > $max_size) {
		$self->{io}->error("Cannnot set desired capacity of $desired_capacity to greater than the maximum size of $max_size");
	}
	
	my $response = $self->_call_asg("update-auto-scaling-group --auto-scaling-group-name $asg_name --desired-capacity $desired_capacity", $debug, $self->{dry_run});
	return TRUE;
}


sub set_min_size {
#=====================================================

=head2 B<set_min_size>

	$asg->set_min_size($asg_name, $min_size);

=cut
#=====================================================
	my $self = shift || return;
	my $asg_input = shift || return;
	my $min_size = shift;
	my $debug = shift;
	is_pos_int($min_size) || return;
	
	my ($auto_scaling_group, $asg_name) = $self->get_auto_scaling_groups($asg_input);
	is_hash($auto_scaling_group) || return;
	
	my $desired_capacity = $auto_scaling_group->{DesiredCapacity};
	my $desired_capacity_string = '';
	if ($desired_capacity < $min_size) {
		$desired_capacity_string = " --desired-capacity $min_size";
	}
	
	my $response = $self->_call_asg("update-auto-scaling-group --auto-scaling-group-name $asg_name --min-size $min_size$desired_capacity_string", $debug, $self->{dry_run});
}


sub cycle_instances {
	# $asg->cycle_instances($asg_name);
	my $self = shift || return;
	my $asg_input = shift || return;
	my $debug = shift;
	
	my ($auto_scaling_group, $asg_name) = $self->get_auto_scaling_groups($asg_input);
	is_hash($auto_scaling_group) || return;
	
	if (value($auto_scaling_group, 'DesiredCapacity')) {
		my $new_cap = $auto_scaling_group->{DesiredCapacity} * 2;
		if ($auto_scaling_group->{DesiredCapacity} == 2) { $new_cap = 6; }
# 		$self->set_desired_capacity($auto_scaling_group, $new_cap, $debug);
		$self->set_min_size($auto_scaling_group, $new_cap, $debug);
		$debug && $self->{io}->success("Auto scaling group \"$asg_name\" set to a min capacity of $new_cap");
		return TRUE;
	} else {
		$self->{io}->error("Desired capacity for auto scaling group \"$asg_name\" is currently zero.");
		exit;
	}
}


sub increment_group {
	# $asg->increment_group($asg_name);
	my $self = shift || return;
	my $asg_input = shift || return;
	my $debug = shift;
	
	my ($auto_scaling_group, $asg_name) = $self->get_auto_scaling_groups($asg_input);
	is_hash($auto_scaling_group) || return;
	
	if (value($auto_scaling_group, 'DesiredCapacity')) {
		my $new_cap = $auto_scaling_group->{DesiredCapacity} + 1;
# 		$self->set_desired_capacity($auto_scaling_group, $new_cap, $debug);
		$self->set_min_size($auto_scaling_group, $new_cap, $debug);
		$debug && $self->{io}->success("Auto scaling group \"$asg_name\" set to a min capacity of $new_cap");
		return TRUE;
	} else {
		$self->{io}->error("Desired capacity for auto scaling group \"$asg_name\" is currently zero.");
		exit;
	}
}

sub decrement_group {
	# $asg->decrement_group($asg_name);
	my $self = shift || return;
	my $asg_input = shift || return;
	my $debug = shift;
	
	my ($auto_scaling_group, $asg_name) = $self->get_auto_scaling_groups($asg_input);
	is_hash($auto_scaling_group) || return;
	
	if (value($auto_scaling_group, 'DesiredCapacity')) {
		my $new_cap = $auto_scaling_group->{DesiredCapacity} - 1;
		$self->set_min_size($auto_scaling_group, $new_cap, $debug);
		$self->set_desired_capacity($auto_scaling_group, $new_cap, $debug);
		$debug && $self->{io}->success("Auto scaling group \"$asg_name\" set to a min capacity of $new_cap");
		return TRUE;
	} else {
		$self->{io}->error("Desired capacity for auto scaling group \"$asg_name\" is currently zero.");
		exit;
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
