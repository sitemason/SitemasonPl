package SitemasonPl::AWS::Auto_Scaling_Groups 1.0;
@ISA = qw( SitemasonPl::AWS );

=head1 NAME

Auto_Scaling_Groups

=head1 DESCRIPTION

Auto Scaling Group functions

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
use SitemasonPl::CLI qw(mark print_object);


sub new {
#=====================================================

=head2 B<new>

 use SitemasonPl::AWS::Auto_Scaling_Groups;
 my $asg = SitemasonPl::AWS::Auto_Scaling_Groups->new;

=cut
#=====================================================
	my ($class, %arg) = @_;
	$class || return;
	
	my $self = {
		cli			=> $arg{cli}
	};
	if (!$self->{cli}) { $self->{cli} = SitemasonPl::CLI->new; }
	
	bless $self, $class;
	return $self;
}


sub get_auto_scaling_groups {
#=====================================================

=head2 B<get_auto_scaling_groups>

	my $auto_scaling_groups = $asg->get_auto_scaling_groups;

=cut
#=====================================================
	my $self = shift || return;
	my $debug = shift;
	
	my $response = $self->_call_asg("describe-auto-scaling-groups", $debug);
	return $response->{AutoScalingGroups};
}


sub _call_asg {
#=====================================================

=head2 B<_call_asg>

=cut
#=====================================================
	my $self = shift || return;
	my $args = shift || return;
	my $debug = shift;
	
	return $self->SUPER::_call_aws("autoscaling $args", $debug);
}



=head1 CHANGES

  2018-07-27 TJM - v1.0 Started

=head1 AUTHOR

  Tim Moses <tim@moses.com>
  Sitemason Open Source <https://github.com/sitemason>

=cut

1;
