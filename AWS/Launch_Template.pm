package SitemasonPl::AWS::Launch_Template 1.0;
@ISA = qw( SitemasonPl::AWS );

=head1 NAME

Launch_Template

=head1 DESCRIPTION

Launch Template functions

=cut

use v5.012;
use strict;
use warnings;
use utf8;
use constant TRUE => 1;
use constant FALSE => 0;

use MIME::Base64;
use YAML;

use lib qw( /opt/lib/site_perl );
use SitemasonPl::AWS;
use SitemasonPl::Batch;
use SitemasonPl::Common;
use SitemasonPl::CLI qw(mark print_object);


sub new {
#=====================================================

=head2 B<new>

 use SitemasonPl::AWS::Launch_Template;
 my $lt = SitemasonPl::AWS::Launch_Template->new($name);
 my $lt = SitemasonPl::AWS::Launch_Template->new(
	cli		=> $self->{cli},
	dry_run	=> $self->{dry_run},
	name	=> $name
 );

=cut
#=====================================================
	my ($class, %arg) = @_;
	$class || return;
	
	my $self = {
		cli			=> $arg{cli},
		dry_run		=> $arg{dry_run},
		name		=> $arg{name}
	};
	if (!$self->{cli}) { $self->{cli} = SitemasonPl::CLI->new; }
	if (!$self->{name}) { $self->{cli}->error("A launch template name is required"); return; }
	
	bless $self, $class;
	return $self;
}


sub get_latest_version_number {
#=====================================================

=head2 B<get_latest_version_number>

	my $version = $lt->get_latest_version_number;

=cut
#=====================================================
	my $self = shift || return;
	my $debug = shift;
	
	my $response = $self->_call_ec2("describe-launch-templates --launch-template-name $self->{name}", $debug);
	return value($response, [qw(LaunchTemplates 0 LatestVersionNumber)]);
}


sub get_default_version_number {
#=====================================================

=head2 B<get_default_version_number>

	my $version = $lt->get_default_version_number;

=cut
#=====================================================
	my $self = shift || return;
	my $debug = shift;
	
	my $response = $self->_call_ec2("describe-launch-templates --launch-template-name $self->{name}", $debug);
	return value($response, [qw(LaunchTemplates 0 DefaultVersionNumber)]);
}


sub set_default_version_number {
#=====================================================

=head2 B<set_default_version_number>

	$lt->set_default_version_number($version);

=cut
#=====================================================
	my $self = shift || return;
	my $version = shift;
	my $debug = shift;
	
	if (!is_pos_int($version)) { $self->{cli}->error("A positive integer for a version number is required"); return; }
		
	my $response = $self->_call_ec2("modify-launch-template --launch-template-name $self->{name} --default-version $version", $debug, $self->{dry_run});
	if (value($response, [qw(LaunchTemplates DefaultVersionNumber)]) == $version) { return TRUE; }
}


sub create_version {
#=====================================================

=head2 B<create_version>

	my $new_version = $lt->create_version($ami_id, $source_version);

=cut
#=====================================================
	my $self = shift || return;
	my $ami_id = shift;
	my $instance_size = shift;
	my $source_version = shift;
	my $user_data = shift;
	my $debug = shift;
	
	if (!$ami_id || ($ami_id !~ /^ami\-[0-9a-f]+/i)) { $self->{cli}->error("A valid AMI ID is required"); return; }
	if (!$instance_size || ($instance_size !~ /^[a-z][1-9][a-z]?\.(nano|micro|small|medium|x?large|[1-3]?[0-9]xlarge)$/i)) { $self->{cli}->error("A valid instance size is required"); return; }
	if (!is_pos_int($source_version)) { $source_version = $self->get_latest_version_number($debug); }
	if (!is_pos_int($source_version)) { $self->{cli}->error("A positive integer for a version number is required"); return; }
	
	my $data = {
		ImageId		=> lc($ami_id),
		InstanceType => $instance_size
	};
	if ($user_data) {
		my $user_data_yaml = Dump($user_data);
		$data->{UserData} = encode_base64($user_data_yaml);
	}
	
	my $json_data = make_json($data, { compress => TRUE, escape_for_bash => TRUE });
	my $response = $self->_call_ec2("create-launch-template-version --launch-template-name $self->{name} --source-version $source_version --launch-template-data '$json_data'", $debug, $self->{dry_run});
	return value($response, [qw(LaunchTemplateVersion VersionNumber)]);
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



=head1 CHANGES

  2018-11-20 TJM - v1.0 Started

=head1 AUTHOR

  Tim Moses <tim@moses.com>
  Sitemason Open Source <https://github.com/sitemason>

=cut

1;
