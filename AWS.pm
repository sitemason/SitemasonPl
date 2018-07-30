package SitemasonPl::AWS 8.0;

=head1 NAME

SitemasonPl::AWS

=head1 DESCRIPTION

A set of consistent interfaces for working with AWS.

=head1 METHODS

=cut

use v5.012;
use strict;
use utf8;
use constant TRUE => 1;
use constant FALSE => 0;

use SitemasonPl::Common;
# use SitemasonPl::AWS::CloudWatch_Logs;
# use SitemasonPl::AWS::CloudWatch_LogStream;
# use SitemasonPl::AWS::CloudWatch_Metrics;
# use SitemasonPl::AWS::EC2;
# use SitemasonPl::AWS::ELB;
# use SitemasonPl::AWS::S3;

sub new {
#=====================================================

=head2 B<new>

=cut
#=====================================================
	my ($class, %arg) = @_;
	$class || return;
	
	my $self = {};
	
	return $self;
}


sub _call_aws {
#=====================================================

=head2 B<_call_aws>

=cut
#=====================================================
	my $self = shift || return;
	my $args = shift || return;
	my $debug = shift;
	my $dry_run = shift;
	
	my $awscli = '/usr/bin/aws';
	if (!-e $awscli) {
		$awscli = '/usr/local/bin/aws';
		if (!-e $awscli) {
			$self->{cli}->error("AWS CLI not found.");
		}
	}
	
	my $command = "$awscli $args";
	$debug && say $command;
	if ($dry_run) {
		$self->{cli}->dry_run($command);
		return {};
	}
	my $json = `$command`;
	is_json($json) || return $json;
	return parse_json($json);
}



=head1 CHANGES

  2018-04-03 TJM - v1.0 Started

=head1 AUTHOR

  Tim Moses <tim@moses.com>
  Sitemason Open Source <https://github.com/sitemason>

=cut

1;
