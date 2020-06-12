package SitemasonPl::AWS::ECR 1.0;
@ISA = qw( SitemasonPl::AWS );

=head1 NAME

ECR

=head1 DESCRIPTION

ECR functions

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

 use SitemasonPl::AWS::ECR;
 my $ecr = SitemasonPl::AWS::ECR->new(
	io			=> $self->{io},
	dry_run		=> $self->{dry_run}
 ) || die "Failed to instantiate ECR\n";

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


sub get_repositories {
#=====================================================

=head2 B<get_repositories>

	my $repositories = $ecr->get_repositories;

=cut
#=====================================================
	my $self = shift || return;
	my $debug = shift;
	
	my $response = $self->_call_ecr("describe-repositories", $debug, $self->{dry_run});
	if (value($response, [qw(repositories)])) {
		return $response->{repositories};
	}
	return undef;
}


sub check_repository {
#=====================================================

=head2 B<check_repository>

	if ($ecr->check_repository($name))

=cut
#=====================================================
	my $self = shift || return;
	my $name = shift || return;
	my $debug = shift;
	
	my $repositories = $self->get_repositories($debug);
	foreach my $repository (@{$repositories}) {
		if ($repository->{repositoryName} eq $name) { return TRUE; }
	}
	return FALSE;
}


sub get_repository {
#=====================================================

=head2 B<get_repository>

	my $repository = $ecr->get_repository($name);

=cut
#=====================================================
	my $self = shift || return;
	my $name = shift || return;
	my $debug = shift;
	
	my $response = $self->_call_ecr("describe-repositories --repository-names $name", $debug, $self->{dry_run});
	if (value($response, [qw(repositories 0)])) {
		return $response->{repositories}->[0];
	}
	return undef;
}


sub create_repository {
#=====================================================

=head2 B<create_repository>

	my $repository = $ecr->create_repository($name);

=cut
#=====================================================
	my $self = shift || return;
	my $name = shift || return;
	my $debug = shift;
	
	my $response = $self->_call_ecr("create-repository --repository-name $name", $debug, $self->{dry_run});
	if (value($response, ['repository'])) {
		return $response->{repository};
	}
	return undef;
}


sub _call_ecr {
#=====================================================

=head2 B<_call_ecr>

=cut
#=====================================================
	my $self = shift || return;
	my $args = shift || return;
	my $debug = shift;
	my $dry_run = shift;
	
	return $self->SUPER::_call_aws("ecr $args", $debug, $dry_run);
}



=head1 CHANGES

  2020-05-20 TJM - v1.0 Started

=head1 AUTHOR

  Tim Moses <tim@moses.com>
  Sitemason Open Source <https://github.com/sitemason>

=cut

1;
