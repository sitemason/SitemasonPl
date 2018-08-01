package SitemasonPl::AWS::CloudWatch_Metrics 1.0;
@ISA = qw( SitemasonPl::AWS );

=head1 NAME

CloudWatch_Metrics

=head1 DESCRIPTION

CloudWatch_Metrics functions

=cut

use v5.012;
use strict;
use warnings;
use utf8;
use constant TRUE => 1;
use constant FALSE => 0;

use DateTime;
use DateTime::Duration;
use DateTime::Format::ISO8601;
use JSON;

use lib qw( /opt/lib/site_perl );
use SitemasonPl::AWS;
use SitemasonPl::Batch;
use SitemasonPl::Common;
use SitemasonPl::CLI qw(mark print_object);


sub new {
#=====================================================

=head2 B<new>

 use SitemasonPl::AWS::CloudWatch_Metrics;
 my $metrics = SitemasonPl::AWS::CloudWatch_Metrics->new(namespace => $namespace);

=cut
#=====================================================
	my ($class, %arg) = @_;
	$class || return;
	
	my $self = {
		cli			=> $arg{cli},
		dry_run		=> $arg{dry_run},
		namespace	=> $arg{namespace},
		metric_data	=> []
	};
	if (!$self->{cli}) { $self->{cli} = SitemasonPl::CLI->new; }
	
	bless $self, $class;
	return $self;
}


sub add_metric {
#=====================================================

=head2 B<add_metric>

	$metrics->add_metric($metric_name, $value, $unit);
	
	$unit =
		"Seconds" | "Microseconds" | "Milliseconds"
		"Bytes" | "Kilobytes" | "Megabytes" | "Gigabytes" | "Terabytes"
		"Bits" | "Kilobits" | "Megabits" | "Gigabits" | "Terabits"
		"Percent"
		"Count"
		"Bytes/Second" | "Kilobytes/Second" | "Megabytes/Second" | "Gigabytes/Second" | "Terabytes/Second"
		"Bits/Second" | "Kilobits/Second" | "Megabits/Second" | "Gigabits/Second" | "Terabits/Second"
		"Count/Second"
		"None"

=cut
#=====================================================
	my $self = shift || return;
	my $metric_name = shift || return;
	my $value = shift || 0;
	my $unit = shift || 'None';
	my $dimensions = shift;
	my $timestamp = shift;
	
	my $metric = {
		MetricName	=> $metric_name,
		Value		=> $value +0,
		Unit		=> $unit
	};
	if ($timestamp) { $metric->{Timestamp} = $timestamp; }
	if (is_hash_with_content($dimensions)) {
		while (my($name, $value) = each(%{$dimensions})) {
			push(@{$metric->{Dimensions}}, {
				Name	=> $name,
				Value	=> $value
			});
		}
	}
	
	push(@{$self->{metric_data}}, $metric);
}


sub get_metric_data {
#=====================================================

=head2 B<get_metric_data>

 my $data = $metrics->get_metric_data;

=cut
#=====================================================
	my $self = shift || return;
	my $debug = shift;
	@{$self->{metric_data}} || return;
	return $self->{metric_data};
}


sub put_metrics {
#=====================================================

=head2 B<_call_elb>

 $metrics->put_metrics;

=cut
#=====================================================
	my $self = shift || return;
	my $debug = shift;
	@{$self->{metric_data}} || return;
	
	my $batch = SitemasonPl::Batch->new(
		batch_size => 20,
		process => sub {
			my $payload = shift;
			if ($self->{dry_run}) {
				my $payload_count = @{$payload};
				my $payload_string = "$payload_count " . pluralize('record', $payload_count);
				$self->{cli}->dry_run("CW put-metric-data --namespace $self->{namespace} --metric-data '[$payload_string]'");
			} else {
				my $metric_data_json = encode_json($payload);
				my $response = $self->_call_cw("put-metric-data --namespace $self->{namespace} --metric-data '$metric_data_json'", FALSE);
			}
		},
		debug => $debug
	);

	foreach my $data (@{$self->{metric_data}}) {
		$batch->add($data);
	}
	$batch->end;
	$self->{metric_data} = [];
	
# 	my @metric_data2;
# 	if (@{$self->{metric_data}} > 20) {
# 		@metric_data2 = splice(@{$self->{metric_data}}, 20, 10, ());
# 	}
# 	
# 	my $metric_data_json = make_json($self->{metric_data}, { include_nulls => TRUE, compress => TRUE, escape_for_bash => TRUE } );
# 	my $response = $self->_call_ec2("put-metric-data --namespace $self->{namespace} --metric-data '$metric_data_json'", $debug);
# 	
# 	if (@metric_data2) {
# 		my $metric_data_json2 = make_json(\@metric_data, { include_nulls => TRUE, compress => TRUE, escape_for_bash => TRUE } );
# 		my $response2 = $self->_call_ec2("put-metric-data --namespace $self->{namespace} --metric-data '$metric_data_json2'", $debug);
# 	}
}


sub get_metric_statistics {
#=====================================================

=head2 B<get_metric_statistics>

To grab the past minute as an Average:
 my $data = $metrics->get_metric_statistics($metric_name);

 my $data = $metrics->get_metric_statistics(
 	$metric_name,
	$duration,				# number of minutes in the past to grab; defaults to 1 minute
	{ $name => $value },	# dimensions as a hash; optional
	'SampleCount' || 'Average' || 'Sum' || 'Minimum' || 'Maximum'	# statistics; defaults to 'Average'
 );

=cut
#=====================================================
	my $self = shift || return;
	my $metric_name = shift || return;
	my $duration = shift || 1;
	my $dimensions = shift;
	my $statistics = shift || 'Average';
	my $debug = shift;
	
	my $dim_string = '';
	if (is_hash_with_content($dimensions)) {
		$dim_string = ' --dimensions';
		while (my($name, $value) = each(%{$dimensions})) {
			$dim_string .= " Name=$name,Value=$value";
		}
	}
	
	my $now = DateTime->now(time_zone => 'UTC');
	my $dur = DateTime::Duration->new(minutes => $duration);
	my $before = $now->clone;
	$before->subtract_duration($dur);
	my $before_string = $before->iso8601() . 'Z';
	my $now_string = $now->iso8601() . 'Z';
	
	my $response = $self->_call_cw("get-metric-statistics --namespace $self->{namespace} --metric-name '$metric_name'$dim_string " .
		"--start-time '$before_string' --end-time '$now_string' --period 60 --statistics $statistics", $debug);
	is_array($response->{Datapoints}) || return;
	
	foreach my $point (@{$response->{Datapoints}}) {
		my $iso8601 = DateTime::Format::ISO8601->new(base_datetime => $now);
		my $isodt = $iso8601->parse_datetime($point->{Timestamp});
		$point->{Epoch} = $isodt->epoch();
		$point->{Data} = $point->{$statistics};
	}
	my @output = sort { $a->{Epoch} <=> $b->{Epoch} } @{$response->{Datapoints}};
	return \@output;
}


sub _call_cw {
#=====================================================

=head2 B<_call_cw>

=cut
#=====================================================
	my $self = shift || return;
	my $args = shift || return;
	my $debug = shift;
	my $dry_run = shift;
	
	return $self->SUPER::_call_aws("cloudwatch $args", $debug, $dry_run);
}



=head1 CHANGES

  2018-05-23 TJM - v1.0 Started

=head1 AUTHOR

  Tim Moses <tim@moses.com>
  Sitemason Open Source <https://github.com/sitemason>

=cut

1;
