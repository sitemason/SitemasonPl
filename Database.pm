package SitemasonPl::Database 8.0;

=head1 NAME

SitemasonPl::Database

=head1 DESCRIPTION

A set of consistent interfaces for working with different types of databases.

=head1 METHODS

=cut

use v5.012;
use strict;
use utf8;
use constant TRUE => 1;
use constant FALSE => 0;

use SitemasonPl::Common;
use SitemasonPl::Database::DynamoDB;
use SitemasonPl::Database::SQL;

sub new {
#=====================================================

=head2 B<new>

=cut
#=====================================================
	my ($class, %arg) = @_;
	$class || return;
	
	my $self = {};
	
	return $self;
}




=head1 CHANGES

  2006-03-08 TJM - v0.01 started development
  2006-??-?? TJM - v1.00 added PostgreSQL support
  2007-??-?? TJM - v2.00 added MySQL support
  2008-04-15 TJM - v3.00 added SQLite3 support
  2008-07-16 TJM - v3.50 merged Sitemason::System::Database and Sitemason::Database
  2012-01-05 TJM - v6.0 moved from Sitemason::System to Sitemason6::Library
  2014-03-20 TJM - v7.0 merged 3.50 and 6.0
  2017-11-09 TJM - v8.0 Moved to SitemasonPL open source project and merged with updates

=head1 AUTHOR

  Tim Moses <tim@moses.com>
  Sitemason Open Source <https://github.com/sitemason>

=cut

1;
