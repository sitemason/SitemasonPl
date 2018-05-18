package SitemasonPl::CloudWatch_LogStream 1.0;
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

use lib qw( /opt/lib/site_perl );
use SitemasonPl::Common;
use SitemasonPl::CLI qw(mark print_object);


sub new {
#=====================================================

=head2 B<new>

 my $logs = SitemasonPl::CloudWatch_LogStream->new;

=cut
#=====================================================
	my ($class, %arg) = @_;
	$class || return;
	
	my $self = {
		cli			=> $arg{cli},
		group_name	=> $arg{group_name},
		stream_name	=> $arg{stream_name}
	};
	if (!$self->{cli}) { $self->{cli} = SitemasonPl::CLI->new; }
	
	bless $self, $class;
	return $self;
}


sub get_log_group {
#=====================================================

=head2 B<get_log_group>

=cut
#=====================================================
	my $self = shift || return;
	my $group_name = shift || return;
	
	my $response = $self->SUPER::_call_aws("logs describe-log-groups --log-group-name-prefix $group_name");
	$self->{cli}->print_object($response, '$response');
}


sub get_streams {
#=====================================================

=head2 B<get_streams>

=cut
#=====================================================
	my $self = shift || return;
	
}




sub _call_cloudwatch_logs {
#=====================================================

=head2 B<_call_cloudwatch_logs>

=cut
#=====================================================
	my $self = shift || return;
	my $args = shift || return;
	my $debug = shift;
	
	return $self->SUPER::_call_aws("logs $args", $debug);
}



=head1 CHANGES

  2018-04-03 TJM - v1.0 Started

=head1 AUTHOR

  Tim Moses <tim@moses.com>
  Sitemason Open Source <https://github.com/sitemason>

=cut

1;
