package SitemasonPl::AWS::EC2 1.0;
@ISA = qw( SitemasonPl::AWS );

=head1 NAME

EC2

=head1 DESCRIPTION

EC2 functions

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

 use SitemasonPl::AWS::EC2;
 my $ec2 = SitemasonPl::AWS::EC2->new();
 my $ec2 = SitemasonPl::AWS::EC2->new(
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


sub get_instances {
#=====================================================

=head2 B<get_instances>

 my $instances = $ec2->get_instances;
 my $instances = $ec2->get_instances($array_of_instance_ids);
 my $instances = $ec2->get_instances($instance_id);
 my $instances = $ec2->get_instances($instance_name);

=cut
#=====================================================
	my $self = shift || return;
	my $identifier = shift || '';
	my $debug = shift;
	
	my $arg = '';
	if (is_array($identifier)) { $arg = " --instance-ids " . join(' ', @{$identifier}); }
	elsif ($identifier =~ /^i-/) { $arg = " --instance-ids $identifier"; }
	elsif ($identifier) { $arg = " --filters 'Name=tag:Name,Values=$identifier'"; }
	
	my $response = $self->_call_ec2("describe-instances$arg", $debug);
	my $records = [];
	foreach my $reservation (@{$response->{Reservations}}) {
		foreach my $instance (@{$reservation->{Instances}}) {
			foreach my $tag (@{$instance->{Tags}}) {
				if ($tag->{Key} eq 'Name') { $instance->{instance_name} = $tag->{Value}; last; }
			}
			push(@{$records}, $instance);
		}
	}
	$debug && $self->{io}->print_object($records, '$records', { limit => 3 });
	return $records;
}

sub run_instance_from_template {
#=====================================================

=head2 B<run_instance_from_template>

 my $ip_address = $ec2->run_instance_from_template($template_name, $subnet_id);
 my $ip_address = $ec2->run_instance_from_template($template_name, $subnet_id, $image_size);

=cut
#=====================================================
	my $self = shift || return;
	my $template_name = shift || return;
	my $subnet_id = shift || return;
	my $instance_type = shift;
	my $debug = shift;
	
	my $lt = SitemasonPl::AWS::Launch_Template->new(
		io		=> $self->{io},
		dry_run	=> $self->{dry_run},
		name	=> $template_name
	);
	my $version = $lt->get_latest_version_number;
	
	my $arg = '';
	if ($instance_type) { $arg = " --instance-type $instance_type"; }
	if ($self->{dry_run}) { 
		$self->_call_ec2("run-instances --launch-template LaunchTemplateName=$template_name,Version=$version --subnet-id $subnet_id$arg", $debug, TRUE);
		$arg = ' --dry-run';
	}
	
	my $response = $self->_call_ec2("run-instances --launch-template LaunchTemplateName=$template_name,Version=$version --subnet-id $subnet_id$arg", $debug);
	my $records = [];
	foreach my $instance (@{$response->{Instances}}) {
		push(@{$records}, $instance->{PrivateIpAddress});
	}
	$debug && $self->{io}->print_object($records, '$records', { limit => 3 });
	return $records->[0];
}

sub stop_instance {
#=====================================================

=head2 B<stop_instance>

 my $response = $ec2->stop_instance($instance_id);

=cut
#=====================================================
	my $self = shift || return;
	my $instance_id = shift || return;
	my $debug = shift;
	
	my $arg = '';
	if ($self->{dry_run}) { 
		$self->_call_ec2("stop-instances --instance-ids $instance_id$arg", $debug, TRUE);
		$arg = ' --dry-run';
	}
	
	my $response = $self->_call_ec2("stop-instances --instance-ids $instance_id$arg", $debug);
	$debug && $self->{io}->print_object($response, '$response');
	return $response;
}

sub terminate_instance {
#=====================================================

=head2 B<terminate_instance>

 my $response = $ec2->terminate_instance($instance_id);

=cut
#=====================================================
	my $self = shift || return;
	my $instance_id = shift || return;
	my $debug = shift;
	
	my $arg = '';
	if ($self->{dry_run}) { 
		$self->_call_ec2("terminate-instances --instance-ids $instance_id$arg", $debug, TRUE);
		$arg = ' --dry-run';
	}
	
	my $response = $self->_call_ec2("terminate-instances --instance-ids $instance_id$arg", $debug);
	$debug && $self->{io}->print_object($response, '$response');
	return $response;
}

sub get_instance_status {
#=====================================================

=head2 B<get_instance_status>

 my $status = $ec2->get_instance_status($ec2_instance_object);
 my $status = $ec2->get_instance_status($instance_id);

=cut
#=====================================================
	my $self = shift || return;
	my $instance = shift || return;
	my $debug = shift;
	
	if (is_text($instance)) {
		my $instances = $self->get_instances($instance);
		$instance = $instances->[0];
	}
	if (is_hash($instance) && $instance->{State}) {
		return $instance->{State}->{Name};
	}

}

sub get_load_balancers {
#=====================================================

=head2 B<get_load_balancers>

 my $elbs = $ec2->get_load_balancers;
 my $elbs = $ec2->get_load_balancers($elb_name);

=cut
#=====================================================
	my $self = shift || return;
	my $identifier = shift || '';
	my $debug = shift;
	
	my $arg = '';
	if ($identifier) { $arg = " --load-balancer-names '$identifier'"; }
	
	my $response = $self->_call_elb("describe-load-balancers$arg", $debug);
	my $records = [];
	foreach my $record (@{$response->{LoadBalancerDescriptions}}) {
		push(@{$records}, $record);
	}
	$debug && $self->{io}->print_object($records, '$records', { limit => 3 });
	return $records;
}


sub get_network_interfaces {
#=====================================================

=head2 B<get_network_interfaces>

 my $enis = $ec2->get_network_interfaces;
 my $enis = $ec2->get_network_interfaces($resource_id);

=cut
#=====================================================
	my $self = shift || return;
	my $identifier = shift || '';
	my $debug = shift;
	
	my $arg = '';
	if ($identifier =~ /^eni-/) { $arg = " --network-interface-ids '$identifier'"; }
	
	my $response = $self->_call_ec2("describe-network-interfaces$arg", $debug);
	my $records = [];
	foreach my $record (@{$response->{NetworkInterfaces}}) {
		push(@{$records}, $record);
	}
	$debug && $self->{io}->print_object($records, '$records', { limit => 3 });
	return $records;
}


sub get_snapshots {
#=====================================================

=head2 B<get_snapshots>

 my $volumes = $ec2->get_snapshots;
 my $volumes = $ec2->get_snapshots($snapshot_id);

=cut
#=====================================================
	my $self = shift || return;
	my $resource_id = shift || '';
	my $debug = shift;
	
	my $arg = '';
	if ($resource_id =~ /^snap-/) { $arg = " --snapshot-ids $resource_id"; }
	
	my $response = $self->_call_ec2("describe-snapshots$arg", $debug);
	my $records = $response->{Snapshots};
	$debug && $self->{io}->print_object($records, '$records', { limit => 3 });
	return $records;
}


sub get_volumes {
#=====================================================

=head2 B<get_volumes>

 my $volumes = $ec2->get_volumes;
 my $volumes = $ec2->get_volumes($volume_id);

=cut
#=====================================================
	my $self = shift || return;
	my $resource_id = shift || '';
	my $debug = shift;
	
	my $arg = '';
	if ($resource_id =~ /^vol-/) { $arg = " --volume-ids $resource_id"; }
	
	my $response = $self->_call_ec2("describe-volumes$arg", $debug);
	my $records = $response->{Volumes};
	$debug && $self->{io}->print_object($records, '$records', { limit => 3 });
	return $records;
}


sub get_tags {
#=====================================================

=head2 B<get_tags>

 my $tags = $ec2->get_tags($type);
 my $tags = $ec2->get_tags($type, $resource_id);

=cut
#=====================================================
	my $self = shift || return;
	my $type = shift || '';
	my $resource_id = shift || '';
	my $debug = shift;
	
	my $arg = '';
	if ($type) { $arg .= " \"Name=resource-type,Values=$type\""; }
	if ($resource_id =~ /^vol-/) { $arg .= " \"Name=resource-id,Values=$resource_id\""; }
	if ($arg) { $arg = " --filter$arg"; }
	
	my $response = $self->_call_ec2("describe-tags$arg", $debug);
	my $tags = $response->{Tags};
	$debug && $self->{io}->print_object($tags, '$tags', { limit => 3 });
	return $tags;
}


sub get_elb_tags_as_ids {
#=====================================================

=head2 B<get_elb_tags_as_ids>

 my $tags = $ec2->get_elb_tags_as_ids;
 my $tags = $ec2->get_elb_tags_as_ids($elb_name);
 my $tags = $ec2->get_elb_tags_as_ids([$elb_name]);

=cut
#=====================================================
	my $self = shift || return;
	my $elb_name = shift || '';
	my $debug = shift;
	
	if (is_array_with_content($elb_name)) {
		my $batch = SitemasonPl::Batch->new(
			batchSize => 20,
			process => sub {
				my $payload = shift;
				my $tags = shift;
				
				my $arg = " --load-balancer-name " . join(' ', @{$payload});
				my $response = $self->_call_elb("describe-tags$arg");
				if (is_hash($response) && is_array_with_content($response->{TagDescriptions})) {
					foreach my $description (@{$response->{TagDescriptions}}) {
						if (is_array_with_content($description->{Tags})) {
							foreach my $tag (@{$description->{Tags}}) {
								$tags->{$description->{LoadBalancerName}}->{$tag->{Key}} = $tag->{Value};
							}
						}
					}
				}
			},
			debug => $debug
		);
		
		my $tags = {};
		foreach my $elb (@{$elb_name}) {
			$batch->add($elb, $tags);
		}
		$batch->end($tags);
		$debug && $self->{io}->print_object($tags, '$tags', { limit => 3 });
		return $tags;
	} else {
		my $arg = '';
		if (is_text($elb_name)) { $arg .= " --load-balancer-name '$elb_name'"; }
	
		my $response = $self->_call_elb("describe-tags$arg", $debug);
		my $tags = $response->{Tags};
		$debug && $self->{io}->print_object($tags, '$tags', { limit => 3 });
		return $tags;
	}
}


sub get_tags_as_ids {
#=====================================================

=head2 B<get_tags_as_ids>

 my $tags = $ec2->get_tags_as_ids($type);
 my $tags = $ec2->get_tags_as_ids($type, $resource_id);

=cut
#=====================================================
	my $self = shift || return;
	my $type = shift;
	my $resource_id = shift || '';
	my $debug = shift;
	
	my $tags = $self->get_tags($type, $resource_id);
	my $tag_ref = {};
	foreach my $tag (@{$tags}) {
		$tag_ref->{$tag->{ResourceId}}->{$tag->{Key}} = $tag->{Value};
	}
	$debug && $self->{io}->print_object($tag_ref, '$tag_ref', { limit => 3 });
	return $tag_ref;
}


sub add_tags {
#=====================================================

=head2 B<add_tags>

 $ec2->add_tags($id_array, $tag_hash);

=cut
#=====================================================
	my $self = shift || return;
	my $ids = shift || return;
	my $tag_hash = shift || return;
	my $debug = shift;
	
	if (is_text($ids)) { $ids = [$ids]; }
	is_array_with_content($ids) || return;
	is_hash_with_content($tag_hash) || return;
	
	my $tags = [];
	while (my($key, $value) = each(%{$tag_hash})) {
		push(@{$tags}, {
			Key		=> $key,
			Value	=> $value
		});
	}
	my $args =  {
		Resources	=> $ids, 
		Tags		=> $tags
	};
	my $json = make_json($args, {
		include_nulls	=> TRUE,
		compress		=> TRUE,
		escape_for_bash	=> TRUE
	});
	
	my $response = $self->_call_ec2("create-tags --io-input-json '$json'", $debug);
	$debug && $self->{io}->print_object($response, '$response', { limit => 3 });
	return;
}



sub _call_ec2 {
#=====================================================

=head2 B<_call_ec2>

=cut
#=====================================================
	my $self = shift || return;
	my $args = shift || return;
	my $debug = shift;
	my $dry_run = shift;
	
	return $self->SUPER::_call_aws("ec2 $args", $debug, $dry_run);
}

sub _call_elb {
#=====================================================

=head2 B<_call_elb>

=cut
#=====================================================
	my $self = shift || return;
	my $args = shift || return;
	my $debug = shift;
	my $dry_run = shift;
	
	return $self->SUPER::_call_aws("elb $args", $debug, $dry_run);
}



=head1 CHANGES

  2018-05-17 TJM - v1.0 Started

=head1 AUTHOR

  Tim Moses <tim@moses.com>
  Sitemason Open Source <https://github.com/sitemason>

=cut

1;
