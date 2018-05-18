package SitemasonPl::AWS::CloudWatch_LogStream 1.0;
@ISA = qw( SitemasonPl::AWS );

=head1 NAME

CloudWatch_LogStream

=head1 DESCRIPTION

Log to a Cloudwatch stream.

=cut

use v5.012;
use strict;
use warnings;
use utf8;
use constant TRUE => 1;
use constant FALSE => 0;

use Time::HiRes qw(gettimeofday);

use lib qw( /opt/lib/site_perl );
use SitemasonPl::Common;
use SitemasonPl::CLI qw(mark print_object);


sub new {
#=====================================================

=head2 B<new>

 my $logs = SitemasonPl::AWS::CloudWatch_LogStream->new;

=cut
#=====================================================
	my ($class, %arg) = @_;
	$class || return;
	
	my $self = {
		cli			=> $arg{cli},
		log_group_name	=> $arg{log_group_name},
		log_stream_name	=> $arg{log_stream_name}
	};
	if (!$self->{cli}) { $self->{cli} = SitemasonPl::CLI->new; }
	
	bless $self, $class;
	$self->{group} = $self->get_log_group || return;
	my $streams = $self->get_log_streams;
	if (is_array_with_content($streams)) {
		$self->{next_token} = $streams->[0]->{uploadSequenceToken};
	} else {
		$self->create_log_stream;
		my $streams = $self->get_log_streams;
		is_array_with_content($streams) || return;
	}
	
	return $self;
}


sub get_ts {
	return int(gettimeofday * 1000);
}


sub get_log_group {
#=====================================================

=head2 B<get_log_group>

=cut
#=====================================================
	my $self = shift || return;
	my $debug = shift;
	
	my $response = $self->_call_cloudwatch_logs("describe-log-groups --log-group-name-prefix $self->{log_group_name}", $debug);
	foreach my $group (@{$response->{logGroups}}) {
		if ($group->{logGroupName} eq $self->{log_group_name}) {
			$debug && $self->{cli}->print_object($group, 'get_log_group()');
			return $group;
		}
	}
	return;
}


sub get_log_streams {
#=====================================================

=head2 B<get_log_streams>

=cut
#=====================================================
	my $self = shift || return;
	my $debug = shift;
	
	my $response = $self->_call_cloudwatch_logs("describe-log-streams --log-group-name $self->{log_group_name} --log-stream-name-prefix $self->{log_stream_name}", $debug);
	my $streams = [];
	foreach my $stream (@{$response->{logStreams}}) {
		if ($stream->{logStreamName} eq $self->{log_stream_name}) {
			push(@{$streams}, $stream);
		}
	}
	is_array_with_content($streams) || return;
	$debug && $self->{cli}->print_object($streams, 'get_log_streams()');
	return $streams;
}


sub create_log_stream {
#=====================================================

=head2 B<create_log_stream>

=cut
#=====================================================
	my $self = shift || return;
	my $debug = shift;
	
	my $response = $self->_call_cloudwatch_logs("create-log-stream --log-group-name $self->{log_group_name} --log-stream-name $self->{log_stream_name}", $debug);
}


sub put_log_event {
#=====================================================

=head2 B<put_log_event>

=cut
#=====================================================
	my $self = shift || return;
	my $message = shift || return;
	my $debug = shift;
	
	my $cmd = "put-log-events --log-group-name $self->{log_group_name} --log-stream-name $self->{log_stream_name}";
	if ($self->{next_token}) { $cmd .= " --sequence-token $self->{next_token}"; }
	
	my $message_json = $message;
	if (is_hash($message) || is_array($message)) {
		$message_json = make_json($message, {
			include_nulls	=> TRUE,
			compress		=> TRUE
		});
	}
	
	my $payload = [ {
		message		=> $message_json
	} ];
	my $json = make_json($payload, {
		include_nulls	=> TRUE,
		compress		=> TRUE,
		escape_for_bash	=> TRUE
	});
	my $ts = get_ts();
	$json =~ s/^\[\{/[{"timestamp":$ts,/;
	$cmd .= " --log-events '$json'";
	
	my $response = $self->_call_cloudwatch_logs($cmd, $debug);
	$self->{next_token} = $response->{nextSequenceToken};
	$debug && $self->{cli}->print_object($response, 'put_log_event() response');
	return;
}





sub _call_cloudwatch_logs {
#=====================================================

=head2 B<_call_cloudwatch_logs>

=cut
#=====================================================
	my $self = shift || return;
	my $args = shift || return;
	my $debug = shift;
	
	return $self->_call_aws("logs $args", $debug);
}


sub _call_aws {
#=====================================================

=head2 B<_call_aws>

=cut
#=====================================================
	my $self = shift || return;
	my $args = shift || return;
	my $debug = shift;
	
	my $awscli = '/usr/bin/aws';
	if (!-e $awscli) {
		$awscli = '/usr/local/bin/aws';
		if (!-e $awscli) {
			$self->{cli}->error("AWS CLI not found.");
		}
	}
	
	my $command = "$awscli $args";
	$debug && say $command;
	my $json = `$command`;
	is_json($json) || return;
	return parse_json($json);
}



=head1 CHANGES

  2018-04-03 TJM - v1.0 Started

=head1 AUTHOR

  Tim Moses <tim@moses.com>
  Sitemason Open Source <https://github.com/sitemason>

=cut

1;
