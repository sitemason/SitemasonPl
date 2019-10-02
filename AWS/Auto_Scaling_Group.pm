package SitemasonPl::AWS::Auto_Scaling_Group 1.0;
@ISA = qw( SitemasonPl::AWS );

=head1 NAME

Auto_Scaling_Group

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
use SitemasonPl::AWS::ELB;
use SitemasonPl::Batch;
use SitemasonPl::Common;
use SitemasonPl::IO qw(mark print_object);


sub new {
#=====================================================

=head2 B<new>

 use SitemasonPl::AWS::Auto_Scaling_Group;
 my $asg = SitemasonPl::AWS::Auto_Scaling_Group->new(name => $name);
 my $asg = SitemasonPl::AWS::Auto_Scaling_Group->new(
	io		=> $self->{io},
	dry_run	=> $self->{dry_run},
	name	=> $name
 );

=cut
#=====================================================
	my ($class, %arg) = @_;
	$class || return;
	
	my $self = {
		io				=> $arg{io},
		dry_run			=> $arg{dry_run},
		name			=> $arg{name},
		cycle_initial	=> 30,
		cycle_interval	=> 10,
		cycle_count		=> 36
	};
	if (!$self->{io}) { $self->{io} = SitemasonPl::IO->new; }
	$self->{name} || $self->{io}->error("An auto scaling group name is required");
	
	bless $self, $class;
	
	$self->load || return;
	
	return $self;
}


sub load {
	# $asg->load || die;
	my $self = shift || return;
	my $debug = shift;
	
	my $asg_name = $self->{name};
	my $asg_name_string = " --auto-scaling-group-names $asg_name";
	
	my $response = $self->_call_asg("describe-auto-scaling-groups$asg_name_string", $debug);
	if (!is_hash($response->{AutoScalingGroups}->[0])) {
		$self->{io}->error("Auto scaling group \"$asg_name\" not found");
		return;
	}
	$self->{asg} = $response->{AutoScalingGroups}->[0];
	return TRUE;
}
sub reload { return load(@_); }

sub load_target_groups {
	# my $target_groups = $asg->load_target_groups;
	my $self = shift || return;
	my $debug = shift;
	
	my $asg_name = $self->{name};
	my $asg_name_string = " --auto-scaling-group-name $asg_name";
	
	my $response = $self->_call_asg("describe-load-balancer-target-groups$asg_name_string", $debug);
	if (!is_array($response->{LoadBalancerTargetGroups})) {
		$self->{io}->error("Target groups not found for auto scaling group \"$asg_name\"");
		return;
	}
	$self->{asg_target_groups} = $response->{LoadBalancerTargetGroups};
	return $self->{asg_target_groups};
}


sub get_full_info {
	# my $asg_info = $asg->get_full_info;
	my $self = shift || return;
	return $self->{asg};
}

sub get_min_size {
	# my $min_size = $asg->get_min_size;
	my $self = shift || return;
	return $self->{asg}->{MinSize};
}

sub get_max_size {
	# my $max_size = $asg->get_max_size;
	my $self = shift || return;
	return $self->{asg}->{MaxSize};
}

sub get_desired_capacity {
	# my $desired_capacity = $asg->get_desired_capacity;
	my $self = shift || return;
	return $self->{asg}->{DesiredCapacity};
}

sub get_instance_ids {
	# my $instance_ids = $asg->get_instance_ids;
	my $self = shift || return;
	if (is_array($self->{asg}->{Instances})) {
		my $instance_ids = [];
		foreach my $instance (@{$self->{asg}->{Instances}}) {
			if ($instance->{LifecycleState} =~ /^(?:InService|Pending)/i) { push(@{$instance_ids}, $instance->{InstanceId}); }
		}
		return $instance_ids;
	} else {
		return [];
	}
}

sub get_healthy_instance_ids {
	# my $instance_ids = $asg->get_healthy_instance_ids;
	my $self = shift || return;
	my $debug = shift;
	
	if (is_array($self->{asg}->{Instances})) {
		my $instance_ids = [];
		foreach my $instance (@{$self->{asg}->{Instances}}) {
			if (($instance->{HealthStatus} eq 'Healthy') && ($instance->{LifecycleState} eq 'InService')) {
				push(@{$instance_ids}, $instance->{InstanceId});
			}
		}
		return $instance_ids;
	} else {
		return [];
	}
}

sub get_healthy_instance_count {
	# my $count = $asg->get_healthy_instance_count;
	my $self = shift || return;
	my $debug = shift;
	
	my $instance_ids = $self->get_healthy_instance_ids($debug);
	return scalar(@{$instance_ids});
}





sub set_desired_capacity {
	# $asg->set_desired_capacity($desired_capacity);
	my $self = shift || return;
	my $desired_capacity = shift;
	my $force = shift;
	my $debug = shift;
	is_pos_int($desired_capacity) || return;
	
	my $min_size = $self->get_min_size;
	my $max_size = $self->get_max_size;
	if ($desired_capacity < $min_size) {
		if ($force) {
			my $response = $self->_call_asg("update-auto-scaling-group --auto-scaling-group-name $self->{name} --min-size $desired_capacity --desired-capacity $desired_capacity", $debug, $self->{dry_run});
			$self->{asg}->{MinSize} = $desired_capacity;
			$self->{asg}->{DesiredCapacity} = $desired_capacity;
			$self->{io}->success("Auto scaling group \"$self->{name}\" set to a desired capacity and min size of $desired_capacity");
			return TRUE;
		} else {
			$self->{io}->error("Cannnot set desired capacity of $desired_capacity to less than the minimum size of $min_size");
			return;
		}
	} elsif ($desired_capacity > $max_size) {
		if ($force) {
			my $response = $self->_call_asg("update-auto-scaling-group --auto-scaling-group-name $self->{name} --max-size $desired_capacity --desired-capacity $desired_capacity", $debug, $self->{dry_run});
			$self->{asg}->{MaxSize} = $desired_capacity;
			$self->{asg}->{DesiredCapacity} = $desired_capacity;
			return TRUE;
		} else {
			$self->{io}->error("Cannnot set desired capacity of $desired_capacity to greater than the maximum size of $max_size");
		}
	} else {
		my $response = $self->_call_asg("update-auto-scaling-group --auto-scaling-group-name $self->{name} --desired-capacity $desired_capacity", $debug, $self->{dry_run});
		$self->{asg}->{DesiredCapacity} = $desired_capacity;
		$self->{io}->success("Auto scaling group \"$self->{name}\" set to a desired capacity of $desired_capacity");
		return TRUE;
	}
}


sub set_min_size {
	# $asg->set_min_size($min_size);
	my $self = shift || return;
	my $min_size = shift;
	my $debug = shift;
	is_pos_int($min_size) || return;
	
	my $desired_capacity = $self->get_desired_capacity;
	my $desired_capacity_string = '';
	if ($desired_capacity < $min_size) {
		$desired_capacity_string = " --desired-capacity $min_size";
	}
	
	my $response = $self->_call_asg("update-auto-scaling-group --auto-scaling-group-name $self->{name} --min-size $min_size$desired_capacity_string", $debug, $self->{dry_run});
	$self->{asg}->{MinSize} = $min_size;
	if ($desired_capacity_string) {
		$self->{asg}->{DesiredCapacity} = $min_size;
	}
}


sub cycle_instances {
	# $asg->cycle_instances;
	my $self = shift || return;
	my $debug = shift;
	
	my $original_size = $self->get_min_size;
	my $new_cap = 0;
	
	# Add servers
	my $desired_capacity = $self->get_desired_capacity;
	if (!$desired_capacity) {
		$self->{io}->error("Desired capacity for auto scaling group \"$self->{name}\" is currently zero.");
		return;
	}
	$new_cap = $desired_capacity * 2;
	if ($desired_capacity == 2) { $new_cap = 6; }
	$self->set_min_size($new_cap, $debug);
	$self->{io}->success("Auto scaling group \"$self->{name}\" set to a min capacity of $new_cap");
	
	
	# Wait until all added
	my $elb = SitemasonPl::AWS::ELB->new(
		io			=> $self->{io},
		dry_run		=> $self->{dry_run}
	) || die "Failed to instantiate ELB\n";
	
	my $ts = get_timestamp;
	$debug && $self->{io}->body("[$ts] Waiting for scale out");
	$debug && $self->{io}->pause($self->{cycle_initial}, 'Scale out: initial');
	my $countdown = $self->{cycle_count};
	while ($countdown--) {
		$self->load;
		my $target_groups = $self->load_target_groups;
		my $count = $elb->get_target_group_healthy_host_count($target_groups->[0]->{LoadBalancerTargetGroupARN});
	# 	my $count = $self->get_healthy_instance_count;
		if ($count >= $new_cap) {
			my $ts = get_timestamp;
			$debug && $self->{io}->body("[$ts] Reached scale out");
			last;
		} else {
			my $ts = get_timestamp;
			$debug && $self->{io}->body("[$ts] $count healthy < $new_cap desired");
		}
		$self->{io}->pause($self->{cycle_interval}, 'Scale out');
	}

	# Remove servers
	$self->set_desired_capacity($original_size, TRUE);

	# Wait until all removed
	$ts = get_timestamp;
	$debug && $self->{io}->body("[$ts] Waiting for scale in");
	$debug && $self->{io}->pause($self->{cycle_initial}, 'Scale in: initial');
	$countdown = $self->{cycle_count};
	while ($countdown--) {
		$self->load;
		my $target_groups = $self->load_target_groups;
		my $count = $elb->get_target_group_healthy_host_count($target_groups->[0]->{LoadBalancerTargetGroupARN});
	# 	my $count = $self->get_healthy_instance_count;
		if ($count <= $original_size) {
			my $ts = get_timestamp;
			$debug && $self->{io}->body("[$ts] Reached scale in");
			last;
		} else {
			my $ts = get_timestamp;
			$debug && $self->{io}->body("[$ts] $count healthy > $original_size original");
		}
		$self->{io}->pause($self->{cycle_interval}, 'Scale in');
	}
}


sub increment_group {
	# $asg->increment_group;
	my $self = shift || return;
	my $debug = shift;
	
	my $desired_capacity = $self->get_desired_capacity;
	my $max_size = $self->get_max_size;
	if ($desired_capacity <= $max_size) {
		my $new_cap = $desired_capacity + 1;
# 		$self->set_desired_capacity($new_cap, undef, $debug);
		$self->set_min_size($new_cap, $debug);
		$self->{io}->success("Auto scaling group \"$self->{name}\" set to a min capacity of $new_cap");
		return TRUE;
	} else {
		$self->{io}->error("Desired capacity for auto scaling group \"$self->{name}\" is already at the max of $max_size.");
		exit;
	}
}

sub decrement_group {
	# $asg->decrement_group;
	my $self = shift || return;
	my $debug = shift;
	
	my $min_size = $self->get_min_size;
	
	my $desired_capacity = $self->get_desired_capacity;
	if ($desired_capacity) {
		my $new_cap = $desired_capacity - 1;
		$self->set_desired_capacity($new_cap, TRUE, $debug);
		$self->{io}->success("Auto scaling group \"$self->{name}\" set to a desired capacity of $new_cap");
		return TRUE;
	} else {
		$self->{io}->error("Desired capacity for auto scaling group \"$self->{name}\" is currently zero.");
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
