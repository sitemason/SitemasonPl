package SitemasonPl::AWS::Parameter_Store 1.0;
@ISA = qw( SitemasonPl::AWS );

=head1 NAME

Parameter_Store

=head1 DESCRIPTION

Parameter_Store functions

=cut

use v5.012;
use strict;
use warnings;
use utf8;
use constant TRUE => 1;
use constant FALSE => 0;

use YAML;

use lib qw( /opt/lib/site_perl );
use SitemasonPl::AWS;
use SitemasonPl::Common;
use SitemasonPl::IO qw(mark print_object);


sub new {
#=====================================================

=head2 B<new>

 use SitemasonPl::AWS::Parameter_Store;
 my $param_store = SitemasonPl::AWS::Parameter_Store->new;
 my $param_store = SitemasonPl::AWS::Parameter_Store->new(
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


sub get_parameter_value {
#=====================================================

=head2 B<get_parameter_value>

	my $value = $param_store->get_parameter_value($name);

=cut
#=====================================================
	my $self = shift || return;
	my $name = shift || return;
	my $debug = shift;
	
	my $cmd = "get-parameter --with-decryption --name $name";
	my $response = $self->_call_parameter_store($cmd, $debug, $self->{dry_run});
	my $value = value($response, ['Parameter', 'Value']);
	if (is_yaml($value)) {
		return Load($value) || {};
	}
	return $value;
}


sub put_parameter {
#=====================================================

=head2 B<put_parameter>

	my $response = $param_store->put_parameter($name, {
		description	=> $description,
		tags		=> $tags,
		update		=> TRUE || FALSE,
		value		=> $value
	});

=cut
#=====================================================
	my $self = shift || return;
	my $name = shift || return;
	my $payload = shift || return;
	my $debug = shift;
	
	my $cmd = "put-parameter --type SecureString --key-id a6cc738d-ec13-4b51-b064-4a185270a08c --name $name";
	if ($payload->{description}) {
		$payload->{description} =~ s/\\'/'"'"'/g;
		$cmd .= " --description '$payload->{description}'";
	}
	if ($payload->{update}) {
		$cmd .= " --overwrite";
	}
	elsif (is_array($payload->{tags})) {
		my $json = make_json($payload->{tags}, { compress => TRUE, escape_for_bash => TRUE } );
		$cmd .= " --tags '$json'";
	}
	if ($payload->{value}) {
		if (is_hash($payload->{value}) || is_array($payload->{value})) {
			my $value = Dump($payload->{value});
			$value =~ s/\\'/'"'"'/g;
			$cmd .= " --value '$value'";
		} elsif (is_text($payload->{value})) {
			$cmd .= " --value '$payload->{value}'";
		}
	}
	my $response = $self->_call_parameter_store($cmd, $debug, $self->{dry_run});
}


sub _call_parameter_store {
#=====================================================

=head2 B<_call_parameter_store>

=cut
#=====================================================
	my $self = shift || return;
	my $args = shift || return;
	my $debug = shift;
	my $dry_run = shift;
	
	return $self->SUPER::_call_aws("ssm $args", $debug, $dry_run);
}



=head1 CHANGES

  2020-10-26 TJM - v1.0 Started

=head1 AUTHOR

  Tim Moses <tim@moses.com>
  Sitemason Open Source <https://github.com/sitemason>

=cut

1;
