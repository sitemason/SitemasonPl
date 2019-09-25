package SitemasonPl::AWS::S3 1.0;
@ISA = qw( SitemasonPl::AWS );

=head1 NAME

S3

=head1 DESCRIPTION

S3 functions

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

 use SitemasonPl::AWS::S3;
 my $s3 = SitemasonPl::AWS::S3->new(bucket_name => $bucket_name);

=cut
#=====================================================
	my ($class, %arg) = @_;
	$class || return;
	
	my $self = {
		io			=> $arg{io},
		bucket_name	=> $arg{bucket_name}
	};
	if (!$self->{io}) { $self->{io} = SitemasonPl::IO->new; }
	
	bless $self, $class;
	return $self;
}


sub get_file_list {
#=====================================================

=head2 B<get_file_list>

=cut
#=====================================================
	my $self = shift || return;
	my $path = shift || return;
	
	my $args = '';
	if ($path) {
		$path =~ s/(^\s*\/|\/\s*$)//g;
		$args = " s3://$self->{bucket_name}/$path/";
	}
	
	my $response = $self->_call_s3("ls $args", TRUE);
	my @file_lines = split("\n", $response);
	my $files = [];
	foreach my $line (@file_lines) {
		my ($date, $size, $file) = $line =~ /^([\d-]+ [\d:]+) +(\d+) +(.*)$/;
		push(@{$files}, {
			timestamp	=> $date,
			size		=> $size,
			filename	=> $file
		});
	}
	return $files;
}





sub _call_s3 {
#=====================================================

=head2 B<_call_s3>

=cut
#=====================================================
	my $self = shift || return;
	my $args = shift || return;
	my $debug = shift;
	
	return $self->SUPER::_call_aws("s3 $args", $debug);
}



=head1 CHANGES

  2018-04-03 TJM - v1.0 Started

=head1 AUTHOR

  Tim Moses <tim@moses.com>
  Sitemason Open Source <https://github.com/sitemason>

=cut

1;
