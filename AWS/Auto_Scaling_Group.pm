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
		io			=> $arg{io},
		dry_run		=> $arg{dry_run},
		name		=> $arg{name}
	};
	if (!$self->{io}) { $self->{io} = SitemasonPl::IO->new; }
	$self->{name} || $self->{io}->error("An auto scaling group name is required");
	
	bless $self, $class;
	
	$self->{asg} = $self->load($self->{name});
	$self->{asg} || return;
	
	return $self;
}


sub load {
#=====================================================

=head2 B<load>

	my $auto_scaling_group = $asg->loads;

=cut
#=====================================================
	my $self = shift || return;
	my $debug = shift;
	
	my $asg_name = $self->{name};
	my $asg_name_string = " --auto-scaling-group-names $asg_name";
	
	my $response = $self->_call_asg("describe-auto-scaling-groups$asg_name_string", $debug);
	if (!is_hash($response->{AutoScalingGroups}->[0])) {
		$self->{io}->error("Auto scaling group \"$asg_name\" not found");
		return;
	}
	return $response->{AutoScalingGroups}->[0];
}
sub reload { return load(@_); }


sub get_full_info {
	my $self = shift || return;
	return $self->{asg};
}

sub get_min_size {
	# $asg->get_min_size;
	my $self = shift || return;
	return $self->{asg}->{MinSize};
}

sub get_max_size {
	# $asg->get_max_size;
	my $self = shift || return;
	return $self->{asg}->{MaxSize};
}

sub get_desired_capacity {
	# $asg->get_desired_capacity;
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
	
	my $instance_ids = $self->get_healthy_instance_ids;
	return scalar(@{$instance_ids});
}





sub set_desired_capacity {
#=====================================================

=head2 B<set_desired_capacity>

	$asg->set_desired_capacity($desired_capacity);

=cut
#=====================================================
	my $self = shift || return;
	my $desired_capacity = shift;
	my $debug = shift;
	is_pos_int($desired_capacity) || return;
	
	my $auto_scaling_group = $self->{asg};
	is_hash($auto_scaling_group) || return;
	
	my $min_size = $self->get_min_size;
	my $max_size = $self->get_max_size;
	if ($desired_capacity < $min_size) {
		$self->{io}->error("Cannnot set desired capacity of $desired_capacity to less than the minimum size of $min_size");
		return;
	} elsif ($desired_capacity > $max_size) {
		$self->{io}->error("Cannnot set desired capacity of $desired_capacity to greater than the maximum size of $max_size");
	}
	
	my $response = $self->_call_asg("update-auto-scaling-group --auto-scaling-group-name $self->{name} --desired-capacity $desired_capacity", $debug, $self->{dry_run});
	$auto_scaling_group->{DesiredCapacity} = $desired_capacity;
	return TRUE;
}


sub set_min_size {
#=====================================================

=head2 B<set_min_size>

	$asg->set_min_size($min_size);

=cut
#=====================================================
	my $self = shift || return;
	my $min_size = shift;
	my $debug = shift;
	is_pos_int($min_size) || return;
	
	my $auto_scaling_group = $self->{asg};
	is_hash($auto_scaling_group) || return;
	
	my $desired_capacity = $self->get_desired_capacity;
	my $desired_capacity_string = '';
	if ($desired_capacity < $min_size) {
		$desired_capacity_string = " --desired-capacity $min_size";
	}
	
	my $response = $self->_call_asg("update-auto-scaling-group --auto-scaling-group-name $self->{name} --min-size $min_size$desired_capacity_string", $debug, $self->{dry_run});
	$auto_scaling_group->{MinSize} = $min_size;
	if ($desired_capacity_string) {
		$auto_scaling_group->{DesiredCapacity} = $min_size;
	}
}


sub cycle_instances {
	# $asg->cycle_instances;
	my $self = shift || return;
	my $debug = shift;
	
	my $auto_scaling_group = $self->{asg};
	is_hash($auto_scaling_group) || return;
	
	my $desired_capacity = $self->get_desired_capacity;
	if (value($auto_scaling_group, 'DesiredCapacity')) {
		my $new_cap = $desired_capacity * 2;
		if ($desired_capacity == 2) { $new_cap = 6; }
# 		$self->set_desired_capacity($auto_scaling_group, $new_cap, $debug);
		$self->set_min_size($auto_scaling_group, $new_cap, $debug);
		$debug && $self->{io}->success("Auto scaling group \"$self->{name}\" set to a min capacity of $new_cap");
		return $new_cap;
	} else {
		$self->{io}->error("Desired capacity for auto scaling group \"$self->{name}\" is currently zero.");
		exit;
	}
}


sub increment_group {
	# $asg->increment_group;
	my $self = shift || return;
	my $debug = shift;
	
	my $auto_scaling_group = $self->{asg};
	is_hash($auto_scaling_group) || return;
	
	my $desired_capacity = $self->get_desired_capacity;
	if (value($auto_scaling_group, 'DesiredCapacity')) {
		my $new_cap = $desired_capacity + 1;
# 		$self->set_desired_capacity($auto_scaling_group, $new_cap, $debug);
		$self->set_min_size($auto_scaling_group, $new_cap, $debug);
		$debug && $self->{io}->success("Auto scaling group \"$self->{name}\" set to a min capacity of $new_cap");
		return TRUE;
	} else {
		$self->{io}->error("Desired capacity for auto scaling group \"$self->{name}\" is currently zero.");
		exit;
	}
}

sub decrement_group {
	# $asg->decrement_group;
	my $self = shift || return;
	my $debug = shift;
	
	my $auto_scaling_group = $self->{asg};
	is_hash($auto_scaling_group) || return;
	
	my $min_size = $self->get_min_size;
	
	my $desired_capacity = $self->get_desired_capacity;
	if (value($auto_scaling_group, 'DesiredCapacity')) {
		my $new_cap = $desired_capacity - 1;
		if ($new_cap < $min_size) {
			$self->set_min_size($auto_scaling_group, $new_cap, $debug);
			$debug && $self->{io}->success("Auto scaling group \"$self->{name}\" set to a min capacity of $new_cap");
		}
		$self->set_desired_capacity($auto_scaling_group, $new_cap, $debug);
		$debug && $self->{io}->success("Auto scaling group \"$self->{name}\" set to a desired capacity of $new_cap");
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
