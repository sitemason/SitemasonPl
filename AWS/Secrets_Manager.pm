package SitemasonPl::AWS::Secrets_Manager 1.0;
@ISA = qw( SitemasonPl::AWS );

=head1 NAME

Secrets_Manager

=head1 DESCRIPTION

Secrets_Manager functions

=cut

use v5.012;
use strict;
use warnings;
use utf8;
use constant TRUE => 1;
use constant FALSE => 0;

use lib qw( /opt/lib/site_perl );
use SitemasonPl::AWS;
use SitemasonPl::Common;
use SitemasonPl::IO qw(mark print_object);


sub new {
#=====================================================

=head2 B<new>

 use SitemasonPl::AWS::Secrets_Manager;
 my $secrets_manager = SitemasonPl::AWS::Secrets_Manager->new;
 my $secrets_manager = SitemasonPl::AWS::Secrets_Manager->new(
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


sub get_secret_value {
#=====================================================

=head2 B<get_secret_value>

 my $value = $secrets_manager->get_secret_value($name);

=cut
#=====================================================
	my $self = shift || return;
	my $name = shift || return;
	my $debug = shift;
	
	my $cmd = "get-secret-value --secret-id $name";
	my $response = $self->_call_secrets_manager($cmd, $debug, $self->{dry_run});
	my $secret = value($response, ['SecretString']);
	if (is_json($secret)) { return parse_json($secret); }
	return $secret;
}


sub _call_secrets_manager {
#=====================================================

=head2 B<_call_secrets_manager>

=cut
#=====================================================
	my $self = shift || return;
	my $args = shift || return;
	my $debug = shift;
	my $dry_run = shift;
	
	return $self->SUPER::_call_aws("secretsmanager $args", $debug, $dry_run);
}



=head1 CHANGES

  2020-10-26 TJM - v1.0 Started

=head1 AUTHOR

  Tim Moses <tim@moses.com>
  Sitemason Open Source <https://github.com/sitemason>

=cut

1;
