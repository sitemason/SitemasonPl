package SitemasonPl::AWS::StepFunctionTask 1.0;
@ISA = qw( SitemasonPl::AWS );

=head1 NAME

StepFunctionTask

=head1 DESCRIPTION

StepFunctionTask functions

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
use SitemasonPl::IO qw(mark print_object);


sub new {
#=====================================================

=head2 B<new>

 use SitemasonPl::AWS::StepFunctionTask;
 my $task = SitemasonPl::AWS::StepFunctionTask->new(token => $token);
 my $task = SitemasonPl::AWS::StepFunctionTask->new(
	io		=> $self->{io},
	dry_run	=> $self->{dry_run},
	token	=> $token
 );

=cut
#=====================================================
	my ($class, %arg) = @_;
	$class || return;
	
	my $self = {
		io			=> $arg{io},
		dry_run		=> $arg{dry_run},
		token		=> $arg{token}
	};
	if (!$self->{io}) { $self->{io} = SitemasonPl::IO->new; }
	if (!$self->{token}) { $self->{io}->error("A step function token is required"); return; }
	
	bless $self, $class;
	return $self;
}


sub send_success {
#=====================================================

=head2 B<send_success>

	my $response = $task->send_success($output);

=cut
#=====================================================
	my $self = shift || return;
	my $output = shift;
	my $debug = shift;
	
	my $json_data = make_json($output, { compress => TRUE, escape_for_bash => TRUE });
	$json_data =~ s/'/'"'"'/g;
	my $response = $self->_call_stepfunctions("send-task-success --task-token '$self->{token}' --task-output '$json_data'", $debug, $self->{dry_run});
}


sub send_failure {
#=====================================================

=head2 B<send_failure>

	my $response = $task->send_failure($error_code, $cause);

=cut
#=====================================================
	my $self = shift || return;
	my $error = shift;
	my $cause = shift;
	my $debug = shift;
	
	my $error_arg = "";
	my $cause_arg = "";
	if ($error) {
		$error =~ s/'/'"'"'/g;
		$error_arg = " --error '$error'";
	}
	if ($cause) {
		$cause =~ s/'/'"'"'/g;
		$cause_arg = " --cause '$cause'";
	}
	my $response = $self->_call_stepfunctions("send-task-failure --task-token '$self->{token}'$error_arg$cause_arg", $debug, $self->{dry_run});
}


sub _call_stepfunctions {
#=====================================================

=head2 B<_call_stepfunctions>

=cut
#=====================================================
	my $self = shift || return;
	my $args = shift || return;
	my $debug = shift;
	my $dry_run = shift;
	
	return $self->SUPER::_call_aws("stepfunctions $args", $debug, $dry_run);
}



=head1 CHANGES

  2020-01-14 TJM - v1.0 Started

=head1 AUTHOR

  Tim Moses <tim@moses.com>
  Sitemason Open Source <https://github.com/sitemason>

=cut

1;
