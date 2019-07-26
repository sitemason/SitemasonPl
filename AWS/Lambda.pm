package SitemasonPl::AWS::Lambda 1.0;
@ISA = qw( SitemasonPl::AWS );

=head1 NAME

Lambda

=head1 DESCRIPTION

Lambda functions

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

 use SitemasonPl::AWS::Lambda;
 my $lambda = SitemasonPl::AWS::Lambda->new(name => $name);
 my $lambda = SitemasonPl::AWS::Lambda->new(
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
	if (!$self->{name}) { $self->{cli}->error("A lambda function name is required"); return; }
	
	bless $self, $class;
	return $self;
}


sub invoke {
#=====================================================

=head2 B<invoke>

	my $response = $lambda->invoke($payload);

=cut
#=====================================================
	my $self = shift || return;
	my $payload = shift;
	my $debug = shift;
	
	my $key = unique_key;
	my $outfile = "/tmp/lambda_invoke_$key";
	my $json_data = make_json($payload, { compress => TRUE, escape_for_bash => TRUE });
	my $response = $self->_call_lambda("invoke --function-name $self->{name} --payload '$json_data' $outfile", $debug, $self->{dry_run});
	if (is_hash_with_content($response) && ($response->{StatusCode} eq '200')) {
		my $output = '';
		if (-e $outfile) {
			open(OUTPUT, "<$outfile");
			while (<OUTPUT>) { $output .= $_; }
			close(OUTPUT);
			unlink($outfile);
		}
	
		return $output;
	}
}


sub _call_lambda {
#=====================================================

=head2 B<_call_lambda>

=cut
#=====================================================
	my $self = shift || return;
	my $args = shift || return;
	my $debug = shift;
	my $dry_run = shift;
	
	return $self->SUPER::_call_aws("lambda $args", $debug, $dry_run);
}



=head1 CHANGES

  2019-07-26 TJM - v1.0 Started

=head1 AUTHOR

  Tim Moses <tim@moses.com>
  Sitemason Open Source <https://github.com/sitemason>

=cut

1;
