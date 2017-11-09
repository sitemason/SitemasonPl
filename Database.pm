package SitemasonPl::Database;
$VERSION = '8.0';

=head1 NAME

SitemasonPl::Library::Database

=head1 DESCRIPTION

An enhancement to DBI.

=head1 METHODS

=cut

use strict;
use utf8;
use constant TRUE => 1;
use constant FALSE => 0;

use DBI;
use DateTime;
use Text::Iconv;

use SitemasonPl::Common;
use SitemasonPl::Debug;
use SitemasonPl::SearchParse;

#=====================================================

=head2 B<new>

Creates and returns a database handle.

Errors:
	db:			all
	sql:		sql statements
	command:	summary of every sql call
	{sql cmd}:	each sql command has a tag, like 'select', 'insert', 'update', 'delete'

 my $dbh = SitemasonPl::Database->new(
	dbType		=> 'pg' || 'mysql' || 'sqlite',
	dbHost		=> $dbHost,
	dbPort		=> $dbPort,
	dbSock		=> $dbSock,
	dbName		=> $dbName,
	dbUsername	=> $dbUsername,
	dbPassword	=> $dbPassword,
	
	# pass original script's debug to share timing and logging
	debug		=> $debug
 );

=cut
#=====================================================
sub new {
	my ($class, %arg) = @_;
	$class || return;
	
	my $self = {
		dbType		=> $arg{dbType}		|| 'pg',
		dbHost		=> $arg{dbHost}		|| $SitemasonPl::serverInfo->{dbInfo}->{dbHost}		|| $ENV{SMDB_HOST},
		dbPort		=> $arg{dbPort}		|| $SitemasonPl::serverInfo->{dbInfo}->{dbPort}		|| $ENV{SMDB_PORT},
		dbUsername	=> $arg{dbUsername}	|| $SitemasonPl::serverInfo->{dbInfo}->{dbUsername}	|| $ENV{SMDB_USERNAME},
		dbPassword	=> $arg{dbPassword}	|| $SitemasonPl::serverInfo->{dbInfo}->{dbPassword}	|| $ENV{SMDB_PASSWORD},
		dbSock		=> $arg{dbSock},
		dbName		=> $arg{dbName}		|| $ENV{SMDB_NAME},
		timeZone	=> $arg{timeZone}	|| $ENV{SM_TIMEZONE}	 || 'UTC'
	};
	
	if ($self->{dbType} eq 'pg') {
		$self->{dbHost}		||= $ENV{PGHOST};
		$self->{dbPort}		||= $ENV{PGPORT};
		$self->{dbUsername}	||= $ENV{PGUSER};
		$self->{dbPassword}	||= $ENV{PGPASS} || $ENV{PGPASSWORD};
	}
	
	if ($arg{debug}) {
		$self->{debug} = $arg{debug};
	} else {
		$self->{debug} = SitemasonPl::Debug->new(
			logLevel	=> 'debug',
			logLevelAll	=> 'info',
			logTags		=> []
		);
	}
	$self->{debug}->call;
	
	my $host;
	my $name;
	if ($self->{dbName}) { $name = "dbname=$self->{dbName}"; }
	my $host;
	if ($self->{dbHost}) { $host = "host=$self->{dbHost};"; }
	my $port;
	if ($self->{dbPort}) { $port = "port=$self->{dbPort};"; }
	my $sock;
	if ($self->{dbSock}) { $sock = "mysql_socket=$self->{dbSock};"; }
	my $user;
	if ($self->{dbUsername}) { $user = $self->{dbUsername}; }
	my $pass;
	if ($self->{dbPassword}) { $pass = $self->{dbPassword}; }
	
	my $type;
	if ($self->{dbType} eq 'sqlite') { $type = 'SQLite'; }
	elsif ($self->{dbType} eq 'mysql') { $type = 'mysql'; }
	elsif ($self->{dbType} eq 'pg') { $type = 'Pg'; }
	my $connectInfo = "DBI:${type}:${host}${port}${sock}${name}";
	
	bless $self, $class;
	if ($type) {
		my $connectMessage = 'Connecting';
# 		if (!$arg{forceNew}) {
# 			my $oldConnectInfo = $self->getServerInfo('connectInfo');
# 			my $oldDBH = $self->getServerInfo('dbh');
# 			if (($oldConnectInfo eq $connectInfo) && $oldDBH && $oldDBH->{dbh}) {
# 	#			my $version = $oldDBH->{dbh}->get_info(18);
# 	#			$self->{debug}->debug("Checked version ($version): " . $oldDBH->{dbh}->errstr . ', ' . $oldDBH->{dbh}->state . ', ' . $oldDBH->{dbh}->err);
# 	#			if ($oldDBH->{dbh}->state && ($oldDBH->{dbh}->state ne '25P01')) {
# 	#				$connectMessage = 'DB connection down (' . $oldDBH->{dbh}->state . '). Reconnecting';
# 	#			} else {
# 					my $sth = $oldDBH->{dbh}->column_info(undef, '%', 'locale', 'name');
# 					my $state = $oldDBH->{dbh}->state;
# #					$self->{debug}->debug('Got statement handle: ' . $oldDBH->{dbh}->errstr . ', ' . $state . ', ' . $oldDBH->{dbh}->err);
# 					if ($state) {
# 						$connectMessage = 'DB idle limit reached (' . $state . '). Reconnecting';
# 					} else {
# 						return $oldDBH;
# 					}
# 	#			}
# 			}
# 		}
# 		$self->{debug}->debug(">>>>>> $connectMessage to db '" . $self->{dbName} . "' <<<<<<");
		$self->{dbh} = DBI->connect($connectInfo, $user, $pass, { PrintError => 1, AutoCommit => 1 });
	}
	
	unless (defined($self->{dbh})) {
		$self->{debug}->emergency("Failed to reach database");
		return;
	}
	
	# Set PostgreSQL default time zone to UTC
	if ($self->{dbType} eq 'pg') {
		$self->{dbh}->{'pg_enable_utf8'} = 1;
		$self->{dbh}->do("SET NAMES 'utf8'");
		$self->{dbh}->do("SET SESSION TIME ZONE 'UTC'");
	}
	# Enable UTF8 for MySQL
	elsif ($self->{dbType} eq 'mysql') {
		$self->{dbh}->{'mysql_enable_utf8'} = 1;
		$self->{dbh}->do("SET NAMES 'utf8'");
	}
	
	$self->{dbInfoType} = lc($self->{dbh}->get_info(17)); # 'postgresql'
	$self->{dbVersion} = $self->{dbh}->get_info(18);
	$self->{dbFieldQuoteChar} = $self->{dbh}->get_info(29) || '`';
#	my $rv = $self->{dbh}->do("SET client_encoding TO 'UTF8';");
	
	$self->{log} = {
		select	=> 0,
		insert	=> 0,
		update	=> 0,
		delete	=> 0,
		nextval	=> 0
	};
	
	$self->{connectInfo} = $connectInfo;
	$self->setServerInfo('connectInfo', $connectInfo);
	$self->setServerInfo('dbh', $self);
	return $self;
}


#=====================================================

=head2 B<reconnect>

After a statement is executed, check state. 57000 08000

 my $state = $self->{dbh}->state;
 if ($self->reconnect($state)) { <<redo command>> }

=cut
#=====================================================
sub reconnect {
	my $self = shift || return; $self->{debug}->call;
	my $state = shift || return;
	if ($state eq '22021') { return; }
	if ($state) { $self->{debug}->error("Potential DB idle timeout ($state) $self->{dbName}"); }
	
	unless (($state eq '57000') || ($state eq '08000')) { $self->{debug}->info('Failing based on state number'); return; }
	
	my $connectInfo = $self->{connectInfo} || $self->getServerInfo('connectInfo');
	if (!$connectInfo) { $self->{debug}->warning('Could not get connection info'); return; }
	
	$self->{debug}->info(">>>>>> Reconnecting to db '" . $self->{dbName} . "' <<<<<<");
	$self->{dbh} = DBI->connect($connectInfo, $self->{dbUsername}, $self->{dbPassword}, { PrintError => 1, AutoCommit => 1 });
	
	unless (defined($self->{dbh})) {
		$self->{debug}->emergency("Failed to reach database");
		return;
	}
	
	# Set PostgreSQL default time zone to UTC
	if ($self->{dbType} eq 'pg') {
		$self->{dbh}->{'pg_enable_utf8'} = 1;
		$self->{dbh}->do("SET NAMES 'utf8'");
		$self->{dbh}->do("SET SESSION TIME ZONE 'UTC'");
	}
	# Enable UTF8 for MySQL
	elsif ($self->{dbType} eq 'mysql') {
		$self->{dbh}->{'mysql_enable_utf8'} = 1;
		$self->{dbh}->do("SET NAMES 'utf8'");
	}
	
	return TRUE;
}


#=====================================================
# DBI-like Methods
#=====================================================

#=====================================================

=head2 B<quote>

$type can be 'begins', 'ends', 'like', 'qlike', 'word', or default

 my $quoted = $self->{dbh}->quote($stringOrArrayOrHash, $type, $limit);

=cut
#=====================================================
sub quote {
	my $self = shift || return; $self->{debug}->call;
	my $input = shift;
	my $type = shift;
	my $limit = shift || 10;
	
	if (ref($input) eq 'SCALAR') { $input = ${$input}; }
	
	my $quoted;
	if (ref($input)) {
		if ($limit <= 1) {
			return $input;
		} elsif (ref($input) eq 'HASH') {
			while (my($name, $value) = each(%{$input})) {
				my $output = $self->quote($value, $type, $limit - 1);
				$quoted->{$name} = $output;
			}
		} elsif (ref($input) eq 'ARRAY') {
			foreach my $value (@{$input}) {
				my $output = $self->quote($value, $type, $limit - 1);
				push(@{$quoted}, $output);
			}
		} else {
			my $message = 'Trying to quote a reference ' . ref($input) . ' ' . $input . "\n";
			$self->{debug}->info($message);
			$quoted = 'NULL';
		}
	} elsif (defined($input)) {
# 		$input =~ s/\\(\\u[0-9a-fA-F]{4})/$1/g;
		$input =~ s/\x{a0}/\\u00a0/g;
		
		# Clear invalid characters for UTF8
		if (($input !~ /^\d+$/) && ($input =~ /[\x80-\xff]/)) {
			print STDERR "quote: Stripping bad characters for UTF8\n";
			my $converter = Text::Iconv->new("UTF8", "UTF8");
			$input = $converter->convert($input);
		}
		
		$quoted = $self->{dbh}->quote($input);
		$quoted = _modifyQuote($quoted, $type);
	} else {
		$quoted = 'NULL';
	}
	return $quoted;
}

sub _modifyQuote {
	my $quoted = shift || '';
	my $type = shift;
	if (($type eq 'begins') || ($type eq 'like')) {
		$quoted =~ s/'$/%'/;
	}
	if (($type eq 'ends') || ($type eq 'like')) {
		$quoted =~ s/^'/'%/;
	}
	if ($type eq 'qlike') {
		$quoted =~ s/^'/'%"/;
		$quoted =~ s/'$/"%'/;
	}
	if ($type eq 'word') {
		$quoted =~ s/^'([a-zA-Z0-9])/'\\\\m$1/;
		$quoted =~ s/([a-zA-Z0-9])'$/$1\\\\M'/;
		$quoted = 'E' . $quoted;
	}
	return $quoted;
}

#=====================================================

=head2 B<uncommit>

 $dbh->uncommit;

=cut
#=====================================================
sub uncommit {
	my $self = shift || return; $self->{debug}->call;
	$self->{dbh}->{'AutoCommit'} = 0;
}


#=====================================================

=head2 B<commit>

 $dbh->commit;

=cut
#=====================================================
sub commit {
	my $self = shift || return; $self->{debug}->call;
	$self->{dbh}->{'AutoCommit'} = 1;
}


#=====================================================

=head2 B<currentDate>

=cut
#=====================================================
sub currentDate {
	my $self = shift || return; $self->{debug}->call;
	my $timeZone = shift || 'UTC';
	
	my $qzone = $self->{dbh}->quote($timeZone);
	$self->uncommit;
	$self->{dbh}->do("SET LOCAL TIME ZONE $qzone");
	my ($currentDate) = $self->{dbh}->selectrow_array("SELECT CURRENT_DATE");
	$self->commit;
	return $currentDate;
}

#=====================================================

=head2 B<quotedCurrentDate>

=cut
#=====================================================
sub quotedCurrentDate {
	my $self = shift || return; $self->{debug}->call;
	my $timeZone = shift;
	my $currentDate = $self->currentDate($timeZone);
	return $self->{dbh}->quote($currentDate);
}

#=====================================================

=head2 B<nextval>

 $id = $self->{dbh}->nextval($table);
 $id = $self->{dbh}->nextval($table, $idFieldName);

=cut
#=====================================================
sub nextval {
	my $self = shift || return; $self->{debug}->call;
	my $table = shift || return;
	my $idFieldName = shift;
	my $log = shift;
	
	if (!$idFieldName || isPosInt($idFieldName) || ($idFieldName eq 'debug')) { $log = $idFieldName; $idFieldName = 'id'; }
	
	my $statement = "SELECT nextval('${table}_${idFieldName}_seq')";
	$self->_logSQL($statement, [caller(0)], $log);
	
	my $id;
	if ($log eq 'debug') {
		($id) = $self->selectRowArray("SELECT max($idFieldName) as id FROM $table", 'noLog');
	} else {
		my $timerKey = $self->timerStart($statement, $log);
		($id) = $self->selectRowArray($statement, 'noLog');
		my $duration = $self->timerStop($timerKey, $log);
		$self->_logTransaction($statement, $duration, [caller(0)], $log);
	}
	return $id;
}


#=====================================================

=head2 B<do>

 $rv = $dbh->do($statement);
 $rv = $dbh->do($statement, 'sql' || 'results' || 'both' || 'debug');

=cut
#=====================================================
sub do {
	my $self = shift || return; $self->{debug}->call;
	my $statement = shift;
	my $log = shift;
	$self->_logSQL($statement, [caller(0)], $log);
	unless ($statement) { return; }
	
	my $rv;
	$statement = $self->_cleanSQL($statement);
	if ($log eq 'debug') {
		$rv = '1';
		my ($command, $table) = $self->_getCommandFromStatement($statement);
		if (($command eq 'update') || ($command eq 'delete')) {
			my $columns = $self->getColumnInfo($table);
			my $idName;
			foreach my $column (@{$columns}) {
				if (($column->{name} eq 'id') || ($column->{COLUMN_DEF} =~ /nextval/)) { $idName = $column->{name}; }
			}
			if ($idName) {
				my ($whereSQL) = $statement =~ /\b(WHERE .*)/is;
				($rv) = $self->{dbh}->selectrow_array("
					SELECT COUNT($idName) FROM $table " . $whereSQL
				);
			}
		}
	} else {
		my $timerKey = $self->timerStart($statement, $log);
		$rv = $self->{dbh}->do($statement);
		if ($self->reconnect($self->{dbh}->state)) {
			$rv = $self->{dbh}->do($statement);
		}
		my $duration = $self->timerStop($timerKey, $log);
		$self->_logTransaction($statement, $duration, [caller(0)], $log);
	}
	my ($command, $table) = $self->_getCommandFromStatement($statement);
	if ($rv eq '0E0') {
		my $message;
		if ($command eq 'delete') { $message = 'Nothing to delete.'; }
		elsif ($command eq 'update') { $message = 'Nothing to update.'; }
		elsif ($command eq 'alter') { return $rv; }
		if ($message) {
#			$self->{debug}->debug($message, newHash({ tags => 'results' }, $log));
		} else {
			$self->{debug}->critical("Failed $command", $log);
		}
	} else {
		my $message = '1 row';
		if ($rv > 1) { $message = $rv . ' rows'; }
		if ($command eq 'delete') { $message = 'Deleted ' . $message; }
		elsif ($command eq 'update') { $message = 'Updated ' . $message; }
		elsif ($command eq 'insert') { $message = 'Inserted ' . $message; }
		if ($message) {
#			$self->{debug}->debug($message, newHash({ tags => 'results' }, $log));
		} else {
			$self->{debug}->critical("Unrecognized command, $command on " . $message, $log);
		}
	}
	return $rv;
}


#=====================================================

=head2 B<selectRowArray>

 @rowAry  = $dbh->selectRowArray($statement);

=cut
#=====================================================
sub selectrow_array { return selectRowArray(@_); }
sub selectRowArray {
	my $self = shift || return; $self->{debug}->call;
	my $statement = shift;
	my $log = shift;
	$self->_logSQL($statement, [caller(0)], $log);
	$statement = $self->_cleanSQL($statement);
	unless ($statement) { return; }
	
	my $timerKey = $self->timerStart($statement, $log);
	my @rowAry = $self->{dbh}->selectrow_array($statement);
	if ($self->reconnect($self->{dbh}->state)) {
		@rowAry = $self->{dbh}->selectrow_array($statement);
	}
	my $duration = $self->timerStop($timerKey, $log);
	$self->_logTransaction($statement, $duration, [caller(0)], $log);
	return @rowAry;
}


#=====================================================

=head2 B<selectRowArrayref>

 $aryRef  = $dbh->selectRowArrayref($statement);

=cut
#=====================================================
sub selectrow_arrayref { return selectRowArrayref(@_); }
sub selectRowArrayref {
	my $self = shift || return; $self->{debug}->call;
	my $statement = shift;
	my $log = shift;
	$self->_logSQL($statement, [caller(0)], $log);
	$statement = $self->_cleanSQL($statement);
	unless ($statement) { return; }
	
	my $timerKey = $self->timerStart($statement, $log);
	my $aryRef = $self->{dbh}->selectrow_arrayref($statement);
	if ($self->reconnect($self->{dbh}->state)) {
		$aryRef = $self->{dbh}->selectrow_arrayref($statement);
	}
	my $duration = $self->timerStop($timerKey, $log);
	$self->_logTransaction($statement, $duration, [caller(0)], $log);
	return $aryRef;
}


#=====================================================

=head2 B<selectRowHashref>

 $hashRef = $dbh->selectRowHashref($statement);

=cut
#=====================================================
sub selectrow_hashref { return selectRowHashref(@_); }
sub selectRowHashref {
	my $self = shift || return; $self->{debug}->call;
	my $statement = shift;
	my $log = shift;
	$self->_logSQL($statement, [caller(0)], $log);
	$statement = $self->_cleanSQL($statement);
	unless ($statement) { return; }
	
	my $timerKey = $self->timerStart($statement, $log);
	my $hashRef = $self->{dbh}->selectrow_hashref($statement);
	if ($self->reconnect($self->{dbh}->state)) {
		$hashRef = $self->{dbh}->selectrow_hashref($statement);
	}
	my $duration = $self->timerStop($timerKey, $log);
	$self->_logTransaction($statement, $duration, [caller(0)], $log);
	return $hashRef;
}


#=====================================================

=head2 B<selectColArrayref>

 $aryRef  = $dbh->selectColArrayref($statement);

=cut
#=====================================================
sub selectcol_arrayref { return selectColArrayref(@_); }
sub selectColArrayref {
	my $self = shift || return; $self->{debug}->call;
	my $statement = shift;
	my $log = shift;
	$self->_logSQL($statement, [caller(0)], $log);
	$statement = $self->_cleanSQL($statement);
	unless ($statement) { return; }
	
	my $timerKey = $self->timerStart($statement, $log);
	my $aryRef = $self->{dbh}->selectcol_arrayref($statement);
	if ($self->reconnect($self->{dbh}->state)) {
		$aryRef = $self->{dbh}->selectcol_arrayref($statement);
	}
	my $duration = $self->timerStop($timerKey, $log);
	$self->_logTransaction($statement, $duration, [caller(0)], $log);
	return $aryRef;
}


#=====================================================

=head2 B<selectAllArrayref>

$aryRef  = $dbh->selectAllArrayref($statement);

=cut
#=====================================================
sub selectall_arrayref { return selectAllArrayref(@_); }
sub selectAllArrayref {
	my $self = shift || return; $self->{debug}->call;
	my $statement = shift;
	my $log = shift;
	$self->_logSQL($statement, [caller(0)], $log);
	$statement = $self->_cleanSQL($statement);
	unless ($statement) { return; }
	
	my $timerKey = $self->timerStart($statement, $log);
	my $aryRef = $self->{dbh}->selectall_arrayref($statement);
	if ($self->reconnect($self->{dbh}->state)) {
		$aryRef = $self->{dbh}->selectall_arrayref($statement);
	}
	my $duration = $self->timerStop($timerKey, $log);
	$self->_logTransaction($statement, $duration, [caller(0)], $log);
	return $aryRef;
}


#=====================================================

=head2 B<selectAllHashref>

 $hashRef = $dbh->selectAllHashref($statement, $keyField);

=cut
#=====================================================
sub selectall_hashref { return selectAllHashref(@_); }
sub selectAllHashref {
	my $self = shift || return; $self->{debug}->call;
	my $statement = shift;
	my $keyField = shift;
	my $log = shift;
	$self->_logSQL($statement, [caller(0)], $log);
	$statement = $self->_cleanSQL($statement);
	unless ($statement) { return; }
	unless ($keyField) {
		$self->{debug}->critical('No key field', $log);
		return;
	}
	
	my $timerKey = $self->timerStart($statement, $log);
	my $hashRef = $self->{dbh}->selectall_hashref($statement, $keyField);
	if ($self->reconnect($self->{dbh}->state)) {
		$hashRef = $self->{dbh}->selectall_hashref($statement, $keyField);
	}
	my $duration = $self->timerStop($timerKey, $log);
	$self->_logTransaction($statement, $duration, [caller(0)], $log);
	return $hashRef;
}


#=====================================================

=head2 B<selectAllArrayhash>

$aryRef  = $dbh->selectAllArrayhash($statement);

=cut
#=====================================================
sub selectall_arrayhash { return selectAllArrayhash(@_); }
sub selectAllArrayhash {
	my $self = shift || return; $self->{debug}->call;
	my $statement = shift;
	my $log = shift;
	$self->_logSQL($statement, [caller(0)], $log);
	$statement = $self->_cleanSQL($statement);
	unless ($statement) { return; }
	
	my $timerKey = $self->timerStart($statement, $log);
	my $sth = $self->{dbh}->prepare($statement);
	if ($self->reconnect($self->{dbh}->state)) {
		$sth = $self->{dbh}->prepare($statement);
	}
	$sth->execute;
	my $aryRef = $sth->fetchall_arrayref({});
	my $duration = $self->timerStop($timerKey, $log);
	$self->_logTransaction($statement, $duration, [caller(0)], $log);
	return $aryRef;
}




#=====================================================
# Aggregated Execute Methods
#=====================================================

#=====================================================

=head2 B<reorderRecords>

	$self->{dbh}->reorderRecords( {
		table		=> 'instance',
		idName		=> 'id',
		checkName	=> 'is_navigable',
		orderName	=> 'order_no',
		groupName	=> 'instance_group_id',
		whereSQL	=> '',
		commands	=> $commands
	} );

In commands, a position of 'a' stands for above and 'b' is below. Do not confuse with before and after, which would be the opposite.

=cut
#=====================================================
sub reorder_records { return reorderRecords(@_); }
sub reorderRecords {
	my $self = shift || return; $self->{debug}->call;
	my $params = shift || return;
	my $log = shift;
	
	my $table = $params->{table} || return;
	my $idName = $params->{idName} || $params->{id_name} || 'id';
	my $checkName = $params->{checkName} || $params->{check_name};
	my $orderName = $params->{orderName} || $params->{order_name} || 'order_no';
	my $groupName = $params->{groupName} || $params->{group_name};
	my $sortName = $params->{sortName} || $params->{sort_name};
	my $timestampName = $params->{timestampName} || $params->{timestamp_name};
	my $where = $params->{whereSQL} || $params->{where_sql};
	my $commands = $params->{commands} || return;
	@{$commands} || return;
	my $changeLog = [];
	my $affectedGroups = {};
	
	# Process commands
	my $moves = [];
	my $checkHash;
	my $uncheckHash;
	foreach my $cmd (@{$commands}) {
		if ($cmd->{action} eq 'move') {
			push(@{$moves}, $cmd);
		} elsif ($cmd->{action} eq 'check') {
			delete($uncheckHash->{$cmd->{id}});
			$checkHash->{$cmd->{id}} = 1;
		} elsif ($cmd->{action} eq 'uncheck') {
			delete($checkHash->{$cmd->{id}});
			$uncheckHash->{$cmd->{id}} = 1;
		}
	}
	my @checkIds = keys(%{$checkHash});
	my @uncheckIds = keys(%{$uncheckHash});
	
	# Move records
	if ($groupName && @{$moves}) {
		# Load source and target records
		my $idList = toArray($moves, 'sourceId');
		my $targetIdList = toArray($moves, 'targetId');
		push(@{$idList}, @{$targetIdList});
		my $idSQL = $self->makeListSQL($idName, $idList, 'int');
		my $records = $self->selectAllHashref("
			SELECT $idName as x_id, $groupName as x_group_id
			FROM $table
			WHERE $idSQL
		", 'x_id', $log);
		
		# Load all relevant groups
		my $targetGroupIdList = to_array($moves, 'target_group_id');
		my $groupIds = toArray($records, 'x_group_id');
		push(@{$groupIds}, @{$targetGroupIdList});
		my $groupIdSQL = $self->makeListSQL($groupName, $groupIds, 'int');
		my $sortNameSQL;
		if ($sortName) { $sortNameSQL = ", $sortName"; }
		my $whereSQL;
		if ($where) { $whereSQL = " and $where"; }
		my $complete = $self->selectAllArrayhash("
			SELECT $idName as x_id, $groupName as x_group_id, $orderName as x_order_no
			FROM $table
			WHERE $groupIdSQL$whereSQL
			ORDER BY $groupName, $orderName$sortNameSQL
		", $log);
		
		# Divide full list into separate groups
		my $groups = {};
		foreach my $item (@{$complete}) {
			if ($records->{$item->{x_id}}) {
				$records->{$item->{x_id}} = $item;
				$item->{new_group_id} = $item->{x_group_id};
			}
			if ($groups->{$item->{x_group_id}}) { $item->{order_no} = @{$groups->{$item->{x_group_id}}}; }
			else { $item->{order_no} = 0; }
			$item->{new_order_no} = $item->{order_no};
			push(@{$groups->{$item->{x_group_id}}}, $item);
		}
		
		# Rearrange in memory
		foreach my $move (@{$moves}) {
			my $source = $records->{$move->{source_id}};
			my $target = $records->{$move->{target_id}};
			
			if (($move->{position} eq 'i') && $move->{target_group_id}) {
				unless ($groups->{$move->{target_group_id}}) { $groups->{$move->{target_group_id}} = []; }
				$target = {
					x_id			=> 0,
					new_group_id	=> $move->{target_group_id}
				};
			}
			
			# Reorder target group
			my $cnt;
			my $newTargetGroup = [];
			my $oldTargetGroup = $groups->{$target->{new_group_id}};
			
			my $isAdded;
			foreach my $item (@{$oldTargetGroup}) {
				if ($item->{x_id} == $source->{x_id}) {
				} elsif ($item->{x_id} == $target->{x_id}) {
					if ($move->{position} eq 'a') {
# 						print STDERR "source $source->{x_id}: $cnt -> ";
						$source->{new_order_no} = $cnt++;
# 						print STDERR "$cnt\n";
						push(@{$newTargetGroup}, $source);
						$isAdded = 1;
					}
# 					print STDERR "target $item->{x_id}: $cnt -> ";
					$item->{new_order_no} = $cnt++;
# 					print STDERR "$cnt\n";
					push(@{$newTargetGroup}, $item);
					if ($move->{position} eq 'b') {
# 						print STDERR "source $source->{x_id}: $cnt -> ";
						$source->{new_order_no} = $cnt++;
# 						print STDERR "$cnt\n";
						push(@{$newTargetGroup}, $source);
						$isAdded = 1;
					}
				} else {
# 					print STDERR "$item->{x_id}: $cnt -> ";
					$item->{new_order_no} = $cnt++;
# 					print STDERR "$cnt\n";
					push(@{$newTargetGroup}, $item);
				}
			}
			unless ($isAdded) {
				$source->{new_order_no} = $cnt++;
				push(@{$newTargetGroup}, $source);
			}
			$groups->{$target->{new_group_id}} = $newTargetGroup;
			
			# Reorder source group if needed
			my $oldGroupId = $source->{new_group_id};
			if ($source->{new_group_id} != $target->{new_group_id}) {
#				print STDERR "reordering source group\n";
				$source->{new_group_id} = $target->{new_group_id};
				my $cnt;
				my $sourceGroup = [];
				foreach my $item (@{$groups->{$oldGroupId}}) {
					if ($item->{x_id} != $source->{x_id}) {
						$item->{new_order_no} = $cnt++;
						push(@{$sourceGroup}, $item);
					}
				}
				$groups->{$oldGroupId} = $sourceGroup;
			}
		}
		
		while (my($groupId, $group) = each(%{$groups})) {
			my $timestampSQL = '';
			if ($timestampName) { $timestampSQL = ", $timestampName = CURRENT_TIMESTAMP"; }
			foreach my $item (@{$group}) {
				if ($item->{x_group_id} && $item->{new_group_id} && ($item->{x_group_id} != $item->{new_group_id})) {
					if ($log) { print STDERR "  $item->{x_id} -> group: $item->{new_group_id}\n"; }
					my $rv = $self->do("
						UPDATE $table
						SET $groupName = $item->{new_group_id}$timestampSQL
						WHERE id = $item->{x_id}
					", $log);
					push(@{$changeLog}, {
						action	=> 'move',
						id		=> $item->{x_id}
					} );
					$affectedGroups->{$item->{x_group_id}} = 1;
					$affectedGroups->{$item->{new_group_id}} = 1;
				}
				if (!defined($item->{x_order_no}) || ($item->{x_order_no} != $item->{new_order_no})) {
					my $orderNo = $item->{new_order_no} || '0';
					if ($log) { print STDERR "  $item->{x_id} -> order_no: $orderNo\n"; }
					my $rv = $self->do("
						UPDATE $table
						SET order_no = $orderNo$timestampSQL
						WHERE id = $item->{x_id}
					", $log);
					push(@{$changeLog}, {
						action	=> 'reorder',
						id		=> $item->{x_id}
					} );
					$affectedGroups->{$item->{x_group_id}} = 1;
				}
			}
		}
	}
	
	# Check records
	if ($checkName && @checkIds) {
		my $idSQL = $self->makeListSQL($idName, \@checkIds, 'int');
		my $rv = $self->do("
			UPDATE $table
			SET $checkName = true
			WHERE $idSQL
		", $log);
		push(@{$changeLog}, {
			action	=> 'check',
			idList	=> \@checkIds
		} );
	}
	
	# Uncheck records
	if ($checkName && @uncheckIds) {
		my $idSQL = $self->makeListSQL($idName, \@uncheckIds, 'int');
		my $rv = $self->do("
			UPDATE $table
			SET $checkName = false
			WHERE $idSQL
		", $log);
		push(@{$changeLog}, {
			action	=> 'uncheck',
			idList	=> \@uncheckIds
		} );
	}
	
	my @affectedGroupIds = keys(%{$affectedGroups});
	return ($changeLog, \@affectedGroupIds);
}


#=====================================================

=head2 B<doUpdateInsert>

 $id = $dbh->doUpdateInsert( {
 	id		=> $id,
 	table	=> $table,
 	input	=> $input,
 	where	=> $where,
 	idName		=> $idName,
 	noNextval	=> 1 || 0,
 	force		=> 1
 } );
 
 Most inserts...
 $id = $dbh->doUpdateInsert( {
 	table	=> $table,
 	input	=> $input
 } );
 
 Most updates...
 $id = $dbh->doUpdateInsert( {
 	id		=> $id,
 	table	=> $table,
 	input	=> $input
 } );

=cut
#=====================================================
sub do_update_insert { return doUpdateInsert(@_); }
sub doUpdateInsert {
	my $self = shift || return; $self->{debug}->call;
	my $args = shift;
	my $log = shift || $args->{log};
	my $id = $args->{id};
	my $table = $args->{table};
	my $input = $args->{input};
	my $modifiers = $args->{modifiers};
	my $idName = $args->{idName} || $args->{id_name} || 'id';
	my $noNextval = $args->{noNextval} || $args->{no_nextval};
	my $force = $args->{force};
	delete($self->{lastAction}); delete($self->{last_action});
	
	my $sth;
	my $whereSQL;
	my $old;
	my $action;
	my $attempt;
	
	# If an id was given, look it up
	if ($id || $args->{where}) {
		if ($args->{where}) { $whereSQL = $args->{where}; }
		else { $whereSQL = $idName . ' = ' . $id; }
		
		$sth = $self->{dbh}->prepare("
			SELECT *
			FROM $table
			WHERE $whereSQL
			LIMIT 1
		");
		$sth->execute;
		$old = $sth->fetchrow_hashref();
	}
	
	if ($old->{$idName}) {
		# An id was given and it was good
	} else {
		# Either didn't get an id or it wasn't found
		undef($old);
		
		# Get an id
		$id ||= $input->{$idName};
		if (!$id && !$noNextval && ($self->{dbType} eq 'pg')) {
			if ($idName eq 'id') { $id = $self->nextval($table, $log); }
			else {
				($id) = $self->selectRowArray("SELECT nextval('${table}_${idName}_seq')");
			}
			$input->{$idName} = $id;
		}
	}
	
	my ($quoted, $modified) = $self->checkFieldInput($table, $input, $old);
	if ($modified || $force) {
		$self->_modifyFields($input, $modifiers, $old);
		($quoted, $modified) = $self->checkFieldInput($table, $input, $old);
	} else { return $old->{$idName}; }
	
	my $changes;
	# Update
	if ($old->{$idName}) {
		$attempt = 'update';
		my @set;
		while (my($field, $value) = each(%{$quoted})) {
			$changes->{$field} = $value;
			if ($field eq $idName) { next; }
			push(@set, "$self->{dbFieldQuoteChar}$field$self->{dbFieldQuoteChar}=$value");
		}
		if (@set) {
			my $setSQL = join(', ', @set);
			my $rv = $self->do("
				UPDATE $table
				SET $setSQL
				WHERE $whereSQL
			", $log);
			if ($rv ne '0E0') { $action = 'update'; }
		} else {
			$self->{debug}->info("No content to update for item($id).", $table);
		}
	}
	
	# Insert
	else {
		$attempt = 'insert';
		my @names;
		my @values;
		while (my($field, $value) = each(%{$quoted})) {
			$changes->{$field} = $value;
			if ($field eq $idName) { next; }
			push(@names, "$self->{dbFieldQuoteChar}$field$self->{dbFieldQuoteChar}");
			push(@values, $value);
		}
		if (@names && @values) {
			my $nameSQL = join(', ', @names);
			my $valueSQL = join(', ', @values);
			my $rv;
			if ($id) {
				my $qid = $self->{dbh}->quote($id);
				$rv = $self->do("
					INSERT INTO $table
						($idName, $nameSQL)
					VALUES
						($qid, $valueSQL)
				", $log);
				if ($rv < 1) {
					undef($id);
					$self->{debug}->critical("Insert failed in $table (prefetched id)", $table);
				} else { $action = 'insert'; }
			} else {
				$rv = $self->do("
					INSERT INTO $table
						($nameSQL)
					VALUES
						($valueSQL)
				", $log);
				if ($rv < 1) { $self->{debug}->critical("Insert failed in $table", $table); }
				else {
					if ($self->{dbType} eq 'mysql') {
						($id) = $self->{dbh}->selectrow_array("
							SELECT last_insert_id()
						");
					} elsif ($self->{dbType} eq 'sqlite') {
						$id = $self->{dbh}->func('last_insert_rowid');
					}
					$action = 'insert';
				}
			}
# 		} else {
# 			$self->{debug}->post( {
# 				caller	=> [caller(0)],
# 				level	=> 'info',
# 				message	=> "No content to insert."
# 			} );
		}
	}
	
#	print STDERR "$table: Tried $attempt. Did '$action'\n";
	$self->{lastAction} = $self->{last_action} = $action;
# 	if (!$action) {
# 		$self->{debug}->post( {
# 			caller	=> [caller(0)],
# 			level	=> 'info',
# 			message	=> "Attempted $attempt, but no action was taken."
# 		} );
# 	}
	if (wantarray) { return ($id, $changes); }
	return $id;
}


#=====================================================

=head2 B<copy>

 my $recordCount = $self->{dbh}->copy($table, $recordsArrayHash);

=cut
#=====================================================
sub copy {
	my $self = shift || return; $self->{debug}->call;
	my $table = shift || return;
	my $records = shift || return;
	my $log = shift;
	
	if (!isArrayHash($records)) { return; }
	
	my $columns = $self->getColumnInfo($table);
	
	my @fields;
	my @quotedRecords;
	my $columnMap = {};
	foreach my $record (@{$records}) {
		foreach my $key (keys(%{$record})) {
			my $valid;
			foreach my $column (@{$columns}) {
				if ($key eq $column->{name}) { $valid = 1; $columnMap->{$key} = $column; last; }
			}
			if (!$valid) { next; }
			
			my $found;
			foreach my $field (@fields) {
				if ($key eq $field) { $found = 1; last; }
			}
			if (!$found) { push(@fields, $key); }
		}
#		my ($quoted) = $self->check_field_input($table, $record);
#		push(@quotedRecords, $quoted);
	}
	
	my ($currentTimestamp) = $self->{dbh}->selectrow_array("SELECT CURRENT_TIMESTAMP AT TIME ZONE 'UTC'");
	$currentTimestamp =~ s/\..*$//;
	
	my $fieldList = join(', ', @fields);
	my $copySQL = "COPY $table ($fieldList) FROM STDIN";
	$self->_logSQL($copySQL, [caller(0)], $log);
	unless ($copySQL) { return; }
	
	my $timerKey = $self->timerStart($copySQL, $log);
	
	my $rv;
	if ($log eq 'debug') { $rv = '1'; }
	else { $rv = $self->{dbh}->do($copySQL); }
	
	my $cnt = 0;
	my $null = '\N';
	my @finalRecords;
	foreach my $record (@{$records}) {
		my @data;
		foreach my $field (@fields) {
			my $type = $columnMap->{$field}->{TYPE_NAME};
			my $default = $columnMap->{$field}->{COLUMN_DEF};
			my $quoted = $record->{$field};
			if ($type eq 'boolean') {
				if (defined($quoted)) {
					if ($quoted) { $quoted = 't'; }
					else { $quoted = 'f'; }
				}
				elsif ($default eq 'true') { $quoted = 't'; }
				elsif ($default eq 'false') { $quoted = 'f'; }
				else { $quoted = $null; }
			} elsif ($type =~ /^(?:integer|smallint|bigint)/) {
				if (defined($quoted)) { $quoted += 0; }
				elsif ($default =~ /^(\d+)/) { $quoted = $1; }
				else { $quoted = $null; }
			} elsif ($type eq 'json') {
				if ($quoted) { $quoted = $self->quoteForCopy($quoted); }
				else { $quoted = $null; }
			} elsif ($type eq 'point') {
				if (!$quoted) { $quoted = $null; }
			} elsif ($type =~ /^timestamp/) {
				if ($quoted =~ /^(?:CURRENT_TIMESTAMP|now)/) { $quoted = $currentTimestamp; }
				elsif (!$quoted) { $quoted = $null; }
			} elsif (defined($quoted)) {
				$quoted =~ s/\\/\\\\/g;
				$quoted =~ s/\t/\\t/g;
				$quoted =~ s/\n/\\n/g;
				$quoted =~ s/\r/\\r/g;
				$quoted =~ s/\f/\\f/g;
			} elsif ($default =~ /'(.*?)'/) {
				$quoted = $1;
			} else {
				$quoted = $null;
			}
			push(@data, $quoted);
		}
		
		if (@data) {
			my $line = join("\t", @data) . "\n";
			if ($log) { $self->{debug}->debug($line, $log); }
			if ($log ne 'debug') {
				my $ret = $self->{dbh}->pg_putcopydata($line);
				unless ($ret) { $self->{debug}->printObject($ret, 'PUT line failed'); }
			}
			push(@finalRecords, $line);
			$cnt++;
		}
	}
	my $rv;
	if ($log eq 'debug') { $rv = '1'; }
	else { $rv = $self->{dbh}->pg_putcopyend(); }
	my $duration = $self->timerStop($timerKey, $log);
	$self->_logTransaction($copySQL, $duration, [caller(0)], $log);
	if ($rv) { return $cnt; }
	else {
		$self->{debug}->error('COPY failed - attempting individual line copies', $log);
		my $cnt;
		foreach my $line (@finalRecords) {
			if ($log) { $self->{debug}->debug($line, $log); }
			my $rv = $self->{dbh}->do($copySQL);
			my $ret = $self->{dbh}->pg_putcopydata($line);
			unless ($ret) { $self->{debug}->printObject($ret, 'PUT line failed'); }
			my $rv = $self->{dbh}->pg_putcopyend();
			if ($rv) { $cnt += $rv; }
			else { chomp($line); $self->{debug}->warning("COPY line failed ($copySQL\n$line)", $log); }
		}
		return $cnt;
	}
}


#=====================================================

=head2 B<quoteForCopy>

=cut
#=====================================================
sub quoteForCopy {
	my $self = shift || return;
	my $value = shift;
	$value =~ s/\\/\\\\/g;
	$value =~ s/\t/\\t/g;
	$value =~ s/\n/\\n/g;
	$value =~ s/\r/\\r/g;
	$value =~ s/\f/\\f/g;
	return $value;
}


#=====================================================

=head2 B<doDelete>

 $success = $dbh->doDelete( {
 	table	=> $table,
 	idName	=> 'id', # defaults to 'id'
 	where	=> {
 		field1	=> $scalar || $arrayRef,
 		field2	=> $scalar || $arrayRef
 	}
 } );

=cut
#=====================================================
sub do_delete { return doDelete(@_); }
sub doDelete {
	my $self = shift || return; $self->{debug}->call;
	my $args = shift;
	my $table = $args->{table} || return;
	my $where = $args->{where} || return;
	my $idName = $args->{idName} || $args->{id_name} || 'id';
	my $log = $args->{log} || shift;
	delete($self->{lastDelete}); delete($self->{last_delete});
	
	my $sth = $self->{dbh}->prepare("
		SELECT *
		FROM $table
		LIMIT 1
	");
	$sth->execute;
	my $sample = $sth->fetchrow_arrayref();
	my ($quoted) = $self->checkFieldInput($table, $where, {}, 1);
	
	# Delete
	if ($quoted->{$idName}) {
		my $whereSQL = $self->makeWhereSQL($quoted);
		my $rv = $self->do("
			delete FROM $table
			WHERE $whereSQL
		", $log);
		if ($rv eq '0E0') { return; }
		else {
			$self->{lastDelete} = $self->{last_delete} = $rv;
			return $where->{$idName};
		}
	} else {
		$self->{debug}->info("No '$idName' for delete on table $table.", $table);
	}
	
	return;
}




#=====================================================
# Internal Logging Methods
#=====================================================

=head2 B<_logSQL>

=cut
#=====================================================
sub _logSQL {
	my $self = shift || return; $self->{debug}->call;
	my $statement = shift;
	my $caller = shift;
	my $log = shift;
	if ($log eq 'noLog') { return; }
	
	if ($statement) {
		if ($log eq 'results') { return; }
		if (!$log) { return; }
		my ($cmd, $table) = $self->_getCommandFromStatement($statement);
		my $level = 'debug';
		if ($log) { $level = 'info'; }
		$statement =~ s/^[ \t]*(\r\n|\n|\r)//;
		my ($tabs) = $statement =~ /^(\s+)/;
		$statement =~ s/^$tabs/  /mg;
		$statement =~ s/\t/  /g;
		$self->{debug}->post( newHash({
			caller	=> $caller,
			level	=> $level,
			message	=> $statement,
			tags	=> ['sql', $cmd, $table]
		}, $log) );
	} else {
		$self->{debug}->post( {
			caller	=> $caller,
			level	=> 'critical',
			message	=> 'Blank SQL statement',
			tags	=> ['sql']
		} );
	}
}


#=====================================================

=head2 B<_logTransaction>

=cut
#=====================================================
sub _logTransaction {
	my $self = shift || return; $self->{debug}->call;
	my $statement = shift || return;
	my $duration = shift;
	my $caller = shift;
	my $log = shift;
	return;
	if ($log eq 'noLog') { return; }
	
	if ($statement) {
		if ($log eq 'results') { return; }
		if (!$log) { return; }
		my ($cmd, $table) = $self->_getCommandFromStatement($statement);
		my $message = "$cmd on $table";
		if ($duration) {
			$message .= " ($duration ms)";
		}
		$self->{debug}->post( newHash({
			caller		=> $caller,
			level		=> 'debug',
			message		=> $message,
			tags		=> ['transaction', $cmd, $table],
			duration	=> $duration
		}, $log) );
	}
}


#=====================================================

=head2 B<_getCommandFromStatement>

 my ($cmd, $table) = $self->_getCommandFromStatement($statement);

=cut
#=====================================================
sub _getCommandFromStatement {
	my $self = shift || return; $self->{debug}->call;
	my $statement = lc(shift) || return;
	
	my ($cmd) = $statement =~ /^\s*(\w+)/;
	my ($table) = $statement =~ /^\s*(?:select\s+.*?\s+from\s+|insert\s+into\s+|update\s+|delete\s+from\s+)(\w+)/s;
	if ($statement =~ /^\s*select\s+nextval\('(\w+)_id_seq/) { $cmd = 'nextval'; $table = $1; }
	
	return ($cmd, $table);
}


#=====================================================

=head2 B<_cleanSQL>

 my $statement = $self->_cleanSQL($statement);

=cut
#=====================================================
sub _cleanSQL {
	my $self = shift || return; $self->{debug}->call;
	my $statement = shift || return;
	
	my ($tabs) = $statement =~ /^(\t+)/;
	$statement =~ s/^$tabs//mg;
	$statement =~ s/(^\s+|\s+$)//g;
	utf8::downgrade($statement, 1);
	return $statement;
}


#=====================================================

=head2 B<_modifyFields>

 my $modified = $self->_modifyFields($input, {
 	fieldName	=> {
 		type		=> 'increment',  # increments the field by the given interval
 		interval	=> 1             # defaults to 1
 	},
 	fieldName2	=> {
 		type		=> 'append',     # appends the value of the field argument to this field's value separated by the delimiter
 		delimiter	=> 1             # defaults to nothing
 		field		=> 1             # required, specifies where to get the value to append
 	},
 	fieldName3	=> {
 		type		=> 'prepend',    # prepends the value of the field argument to this field's value separated by the delimiter
 		delimiter	=> 1             # defaults to nothing
 		field		=> 1             # required, specifies where to get the value to prepend
 	}
 } );

=cut
#=====================================================
sub _modifyFields {
	my $self = shift || return; $self->{debug}->call;
	my $input = shift || return;
	my $modifiers = shift || return;
	my $old = shift;
	
	while (my($name, $ruleSet) = each(%{$modifiers})) {
		foreach my $rule (@{$ruleSet}) {
			if ($rule->{type} eq 'increment') {
				my $interval = $rule->{interval} || 1;
				if ($old->{$name}) { $input->{$name} = $old->{$name} + $interval; }
			} elsif ($rule->{type} eq 'copy') {
				if ($rule->{field} && $input->{$rule->{field}}) {
					if ($rule->{lowercase}) { $input->{$name} = lc($input->{$rule->{field}}); }
					else { $input->{$name} = $input->{$rule->{field}}; }
				} else {
					last;
				}
			} elsif ($rule->{type} eq 'substitute') {
				if ($rule->{match}) {
					if ($rule->{multiple}) {
						$input->{$name} =~ s/$rule->{match}/$rule->{replace}/g;
					} else {
						$input->{$name} =~ s/$rule->{match}/$rule->{replace}/;
					}
				}
			} elsif ($rule->{type} eq 'append') {
				if ($rule->{field} && $input->{$rule->{field}}) {
					$input->{$name} = $input->{$name} . $rule->{delimiter} . $input->{$rule->{field}};
				}
			} elsif ($rule->{type} eq 'prepend') {
				if ($rule->{field} && $input->{$rule->{field}}) {
					$input->{$name} =  $input->{$rule->{field}} . $rule->{delimiter} . $input->{$name};
				}
			}
		}
	}
	
	return $input;
}


#=====================================================

=head2 B<timerStart>

=cut
#=====================================================
sub timerStart {
	my $self = shift || return;
	my $statement = shift;
	my $log = shift || return;
	if ($log eq 'noLog') { return; }
	
	my ($cmd, $table) = $self->_getCommandFromStatement($statement);
#	my ($parent) = (caller(0))[3];
	my $unique = uniqueKey;
	my $key = 'db_' . $cmd . '_on_' . $table . '_' . $unique;
	$self->{debug}->timerStart($key);
	return $key;
}

#=====================================================

=head2 B<timerStop>

=cut
#=====================================================
sub timerStop {
	my $self = shift || return;
	my $key = shift;
	my $log = shift || return;
	if ($log eq 'noLog') { return; }
	
	my $duration = $self->{debug}->timerStop($key);
	return $duration;
}



#=====================================================
# SQL Generation Methods
#=====================================================

#=====================================================

=head2 B<makeListSQL>

Returns sql for a single field of a where clause. Give it the field name and a list of values. It will quote, filter out blank values, and remove duplicates. If you also specify a type, it will test the input and generate the appropriate sql for the type.

 $sql = $self->{dbh}->makeListSQL($fieldName, $listOfValues, $type);

 Type can be:
   default - generates a quoted 'name = value' or 'name in (values)' clause with ORs
   prefix of '!' - makes the query a NOT
   prefix of 'x' - use ANDs instead of ORs
   prefix of '!x' - NOT and AND
 
   'i' - like the default, but case-insensitive
   'int' - like the default, but exits if it encounters a non-integer
   'word', 'like', 'ilike' - a case-insensitive word search with ORs
   'begins', 'ends', 'contains' - a case-insensitive search with ORs

=cut
#=====================================================
sub make_list_sql { return makeListSQL(@_); }
sub makeListSQL {
	my $self = shift || return; $self->{debug}->call;
	my $field = shift || return;
	my $prelist = shift || return;
	my $comp = shift;
	my $key = shift || 'id';
	
	my $list = toArray($prelist, $key);
	$list = uniqueArray($list);
	unless ($list && @{$list}) { return; }
	
	my ($nott, $notb);
	if ($comp =~ /^\!/) { $nott = ' not'; $notb = '!'; $comp =~ s/^\!//; }
	
	my $ex;
	if ($comp =~ /^x/) { $ex = 1; $comp =~ s/^x//; }
	
	my $sql;
	if ($comp eq 'like' || $comp eq 'ilike' || $comp eq 'word') {
		my @sql;
		foreach my $item (@{$list}) {
			my $quote = $self->quote($item);
			$quote =~ s/^'([a-zA-Z0-9])/'\\\\m$1/;
			$quote =~ s/([a-zA-Z0-9])'$/$1\\\\M'/;
			push(@sql, $field . ' ' . $notb . '~* E' . $quote);
		}
		if (@sql == 1) { $sql = @sql[0]; }
		elsif ($ex) { $sql = '(' . join(' and ', @sql) . ')'; }
		else { $sql = '(' . join(' or ', @sql) . ')'; }
	} elsif ($comp eq 'begins' || $comp eq 'ends' || $comp eq 'contains') {
		my @sql;
		foreach my $item (@{$list}) {
			my $quote = $self->quote($item);
			if ($comp eq 'begins' || $comp eq 'contains') {
				$quote =~ s/'$/%'/;
			}
			if ($comp eq 'ends' || $comp eq 'contains') {
				$quote =~ s/^'/'%/;
			}
			push(@sql, $field . $nott . ' ilike ' . $quote);
		}
		if (@sql == 1) { $sql = @sql[0]; }
		elsif ($ex) { $sql = '(' . join(' and ', @sql) . ')'; }
		else { $sql = '(' . join(' or ', @sql) . ')'; }
	} elsif ($comp eq 'int') {
		my $cleanList = [];
		foreach my $item (@{$list}) {
			$item = strip($item);
			if (isPosInt($item)) {
				push(@{$cleanList}, $item);
			} else {
				return;
			}
		}
		
		if (@{$cleanList} == 1) {
			$sql = $field . ' ' . $notb . '= ' . $self->quote($cleanList->[0]);
		} else {
			my @sql;
			foreach my $item (@{$cleanList}) {
				push(@sql, $self->quote($item));
			}
			$sql = $field . $nott . ' in (' . join(', ', @sql) . ')';
		}
	} elsif ($comp eq 'i') {
		if (@{$list} == 1) {
			my $quote = $self->quote(lc($list->[0]));
			$sql = 'lower(' . $field . ') ' . $notb . '= ' . $quote;
		} else {
			my @sql;
			foreach my $item (@{$list}) {
				push(@sql, $self->quote(lc($item)));
			}
			$sql = 'lower(' . $field . ')' . $nott . ' in (' . join(', ', @sql) . ')';
		}
	} else {
		if (@{$list} == 1) {
			$sql = $field . ' ' . $notb . '= ' . $self->quote($list->[0]);
		} else {
			my @sql;
			foreach my $item (@{$list}) {
				push(@sql, $self->quote($item));
			}
			$sql = $field . $nott . ' in (' . join(', ', @sql) . ')';
		}
	}
	
	return $sql;
}


#=====================================================

=head2 B<makeWhereSQL>

Converts a hash of name and values into a where clause. Values are used as is, unless a table name is given as a second argument. In that case, it will quote according to the field types in the table.

Name/value pairs are pieced together with 'and'. In a future version, a hierarchy of name/values could be passed with args specifying 'and' or 'or'.

 $whereSQL = $self->{dbh}->makeWhereSQL( {
 	$fieldName1	=> $listOfQuotedValues,
 	$fieldName2	=> $quotedValue
 }, $table);

=cut
#=====================================================
sub make_where_sql { return makeWhereSQL(@_); }
sub makeWhereSQL {
	my $self = shift || return; $self->{debug}->call;
	my $where = shift || return;
	my $table = shift;
	my $tableAbbr = shift;
	my $whereList = [];
	
	if ($table) {
		my ($quoted) = $self->checkFieldInput($table, $where, {}, 1);
		$where = $quoted;
	}
	
	my $prefix;
	if ($tableAbbr) { $prefix = "$tableAbbr."; }
	
	while (my($field, $value) = each(%{$where})) {
		# lists
		if (ref($value) eq 'ARRAY') {
			my $list = uniqueArray($value);
			unless ($list && @{$list}) { next; }
			
			if (@{$list} == 1) {
				push(@{$whereList}, $prefix . $field . ' = ' . $list->[0]);
			} else {
				my @sql;
				foreach my $item (@{$list}) {
					push(@sql, $item);
				}
				push(@{$whereList}, $prefix . $field . ' in (' . join(', ', @sql) . ')');
			}
		} else {
			# scalars
			push(@{$whereList}, $prefix . $field . ' = ' . $value);
		}
	}
	my $whereSQL = join("\n  and ", @{$whereList});
	
	return $whereSQL;
}


#=====================================================

=head2 B<makeSQL>

An easier way to parse searches and call makeSearchSQL and makeOrderSQL.

	my ($whereSQL, $suffixSQL, $search) = $self->{dbh}->makeSQL($searchSchema, $searchArguments);
	my ($whereSQL, $suffixSQL, $search) = $self->{dbh}->makeSQL( {
		prefix		=> 'sr',
		field_map	=> {
			'sr.id'				=> 'id',
			instance_id			=> 'id',
			order_status_id		=> ['id', 'order'],
			create_timestamp	=> ['when', 'order', 'q'],
			summary				=> ['what', 'q', 'order'],
			total				=> ['what', 'order', 'num'],
			xml_receipt			=> 'what'
		},
		defaultOrderBy	=> 'sr.create_timestamp'
	}, $searchArguments);
	my $schema = {
		default_table	=> 'item_custom_record_draft',
		default_order_by	=> 'order_no,asc',
		field_map		=> {
			instance_id			=> { type => 'int',		size => 4,		readOnly => 1,		table => 'instance_item' },
			instance_custom_settings_id	=> { type => 'int',		size => 4,		readOnly => 1 },
			id					=> { type => 'int',		size => 4,		readOnly => 1 },
			item_id				=> { type => 'int',		size => 4,		readOnly => 1 },
			key					=> { type => 'char',	size => 8,		readOnly => 1 },
			field_1				=> { type => 'text',	size => 0,		defaultQuery => 1 },
			create_timestamp	=> { type => 'ts',		size => 0,		readOnly => 1 },
			modify_timestamp	=> { type => 'ts',		size => 0,		readOnly => 1 },
			order_no			=> { type => 'int',		size => 2,		},
		}
	}

=cut
#=====================================================
sub make_sql { return makeSQL(@_); }
sub makeSQL {
	my $self = shift || return; $self->{debug}->call;
	my $args = shift || return;
	
	my $input = $self->processMakeSQLInput($args);
	my ($whereSQL, $suffixSQL);
	my $whereSQL = $self->makeSearchSQL( {
		search				=> $input->{search},
		valid_search		=> $input->{valid_search}
	} );
	my $suffixSQL = $self->makeSuffixSQL( {
		search				=> $input->{search},
		valid_order_by		=> $input->{valid_order_by},
		default_order_by	=> $args->{default_order_by}
	} );
	
	return ($whereSQL, $suffixSQL, $input->{search}, $input->{commands});
}


#=====================================================

=head2 B<processMakeSQLInput>

Convert easy field descriptions into map of field specs. easy for human -> easy for code

	my $schema = {
		defaultTable	=> 'item_custom_record_draft',
		defaultOrderBy	=> 'order_no,asc',
		fieldMap		=> {
			instance_id			=> { type => 'int',		size => 4,		readOnly => 1,		table => 'instance_item' },
			instance_custom_settings_id	=> { type => 'int',		size => 4,		readOnly => 1 },
			id					=> { type => 'int',		size => 4,		readOnly => 1 },
			item_id				=> { type => 'int',		size => 4,		readOnly => 1 },
			key					=> { type => 'char',	size => 8,		readOnly => 1 },
			field_1				=> { type => 'text',	size => 0,		defaultQuery => 1 },
			create_timestamp	=> { type => 'ts',		size => 0,		readOnly => 1 },
			modify_timestamp	=> { type => 'ts',		size => 0,		readOnly => 1 },
			order_no			=> { type => 'int',		size => 2,		},
		}
	}

=cut
#=====================================================
sub process_make_sql_input { return processMakeSQLInput(@_); }
sub processMakeSQLInput {
	my $self = shift || return; $self->{debug}->call;
	my $args = shift || return;
	my $settings = $args->{settings};
	my $fields = $args->{field_map} || return;
	my $default_prefix = $args->{prefix};
	my $params = $args->{params};
	
	my $valid_search = { default => [] };
	my $valid_order_by;
	
	while (my($name, $value) = each(%{$fields})) {
		if (!ref($value)) { $value = [$value]; }
		if (ref($value) ne 'ARRAY') { next; }
		my ($prefix, $fieldname) = $name =~ /^(\w+)\.(\w+)$/;
		$fieldname ||= $name;
		$prefix ||= $default_prefix;
		
		my $cat;
		my $what;
		my $type;
		foreach my $arg (@{$value}) {
			if ($arg =~ /^(?:id|id_list)$/) {
				$cat = 'id_list';
				$valid_search->{$cat}->{$name} = $prefix;
			}
			elsif ($arg =~ /^(?:flags?|bool|boolean)$/) {
				$cat = 'flags';
				$valid_search->{$cat}->{$name} = $prefix;
			}
			elsif ($arg =~ /^(?:when|time|timestamp|date|datetime)$/) {
				$cat = 'when';
				$valid_search->{$cat}->{$name} = $prefix;
			}
			elsif ($arg =~ /^(?:what|xwhat|begins|xbegins|ends|xends|contains|xcontains)$/) {
				$cat = 'what';
				$what = $arg;
				$valid_search->{$cat}->{$name} = $prefix;
			}
			elsif ($arg eq 'num') { $type = 'num'; }
		}
		foreach my $arg (@{$value}) {
			if ($arg eq 'order') {
				if ($cat =~ /^(?:id_list|flags|when)$/) { $valid_order_by->{$fieldname} = $prefix; }
				elsif ($type eq 'num') { $valid_order_by->{$fieldname} = "$prefix,n"; }
				else { $valid_order_by->{$fieldname} = "$prefix,l"; }
			} elsif ($arg eq 'q') {
				if ($what) {
					push(@{$valid_search->{default}}, {
						fieldname	=> $name,
						category	=> $what
					});
				}
				else { push(@{$valid_search->{default}}, $name); }
			}
		}
	}
	
	my $search;
	my $commands = [];
	if ($params) {
		if (isArrayWithContent($params->{'m'})) {
			my @cmds = @{$params->{'m'}};
			foreach my $cmd (@cmds) {
				my ($source, $position, $target) = $cmd =~ /^(\d+)([abi])(\d+)$/;
				if ($target) {
					push(@{$commands}, {
						action		=> 'move',
						source_id	=> $source,
						position	=> $position,
						target_id	=> $target
					});
				} else {
					$self->{debug}->info("Invalid move command: $cmd");
				}
			}
			delete($params->{'m'});
		}
		if (isArrayWithContent($params->{'c'})) {
			my @checkIds = @{$params->{'c'}};
			foreach my $id (@checkIds) {
				if ($id =~ /^(\d+)$/) {
					push(@{$commands}, {
						action	=> 'check',
						id		=> $id
					});
				} else {
					$self->{debug}->info("Invalid id for check command: $id");
				}
			}
			delete($params->{'c'});
		}
		if (isArrayWithContent($params->{'u'})) {
			my @uncheckIds = @{$params->{'u'}};
			foreach my $id (@uncheckIds) {
				if ($id =~ /^(\d+)$/) {
					push(@{$commands}, {
						action	=> 'uncheck',
						id		=> $id
					});
				} else {
					$self->{debug}->info("Invalid id for uncheck command: $id");
				}
			}
			delete($params->{'u'});
		}
		
		if ($valid_search->{when}) { $settings->{time} = 1; }
		
		my $options = {
			quotes	=> 1,
			zip		=> 0,
			times	=> 0,
			cities	=> 0,
			msas	=> 0,
			tags	=> 0,
			dates	=> 0,
			time	=> 0,
			no_default_date	=> 1
		};
		if ($settings->{time}) {
			$options->{times} = 1;
			$options->{dates} = 1;
			$options->{time} = 1;
		}
		
		my $search_limit = first($params->{num});
		$search_limit += 0;
		my $search_offset = first($params->{start});
		$search_offset += 0;
		if ($search_offset < 1) { undef($search_offset); }
		$search->{order_by} = $settings->{order_by};
		my @sort = first($params->{sort});
		foreach my $value (@sort) {
			my ($sort_field, $sort_order) = split(',', $value);
			if ($sort_order ne 'desc') { $sort_order = 'asc'; }
			push(@{$search->{order_by}}, { field => $sort_field, sort_order => $sort_order } );
		}
		
		# Remap order_by fields
		if ($search->{order_by}) {
			my $map;
			foreach my $fieldname (keys(%{$valid_search->{when}})) {
				if ($fieldname =~ /^create.*_timestamp$/) { $map->{create} = $fieldname; }
				elsif ($fieldname =~ /modif.*_timestamp$/) { $map->{modify} = $fieldname; }
			}
			foreach my $order (@{$search->{order_by}}) {
				if ($order->{field} =~ /^create.*_timestamp_display$/) { $order->{field} = $map->{create}; }
				elsif ($order->{field} =~ /^modif.*_timestamp_display$/) { $order->{field} = $map->{modify}; }
			}
		}
		
		# Parse searches out of search string
		my $search_string = first($params->{'q'}) || first($params->{search}) || first($params->{search_string});
		if ($search_string) {
			my $searchparse = Sitemason::System::SearchParse->new( options => $options );
			$search->{parsed} = $searchparse->parse($search_string);
		}
		
		# Read specific field searches
		while (my($cat, $field_list) = each(%{$valid_search})) {
			if (ref($field_list) eq 'HASH') {
				while (my($fieldname, $prefix) = each(%{$field_list})) {
					if ($cat eq 'when') {
						$search->{when}->{$fieldname}->{start} = first($params->{"$fieldname.start"});
						$search->{when}->{$fieldname}->{start} = first($params->{$fieldname});
						$search->{when}->{$fieldname}->{end} = first($params->{"$fieldname.end"});
					} elsif (isArrayWithContent($params->{$fieldname})) {
						$search->{$cat}->{$fieldname} = $params->{$fieldname};
					} elsif (defined($params->{$fieldname}) && !ref($params->{$fieldname})) {
						$search->{$cat}->{$fieldname} = [$params->{$fieldname}];
					}
				}
			}
		}
		
		$search->{'q'} = $search_string;
		$search->{limit} = $search_limit || $settings->{limit};
		$search->{offset} = $search_offset || $settings->{offset};
		$search->{export} = $settings->{export};
	}
	
	return {
		valid_search	=> $valid_search,
		valid_order_by	=> $valid_order_by,
		search			=> $search,
		commands		=> $commands
	};
}


#=====================================================

=head2 B<makeSearchSQL>

=cut
#=====================================================
sub make_search_sql { return makeSearchSQL(@_); }
sub makeSearchSQL {
	my $self = shift || return; $self->{debug}->call;
	my $options = shift || return;
	my $valid_search = $options->{valid_search} || return;
	my $search = $options->{search} || {};
	
	# Set search criteria based on 
	foreach my $default (@{$valid_search->{default}}) {
		my $default_field = $default;
		my $default_cat;
		if (ref($default) eq 'HASH') {
			$default_field = $default->{fieldname};
			$default_cat = $default->{category};
		}
		if ($search->{parsed}->{start_date}) {
			foreach my $field (keys(%{$valid_search->{when}})) {
				if ($field eq $default_field) { $search->{when}->{$field}->{start} = $search->{parsed}->{start_date}; }
			}
		}
		if ($search->{parsed}->{end_date}) {
			foreach my $field (keys(%{$valid_search->{when}})) {
				if ($field eq $default_field) { $search->{when}->{$field}->{end} = $search->{parsed}->{end_date}; }
			}
		}
		foreach my $comp (qw(what xwhat begins xbegins ends xends contains xcontains)) {
			if ($search->{parsed}->{$comp} && @{$search->{parsed}->{$comp}}) {
				foreach my $field (keys(%{$valid_search->{what}})) {
					if ($field eq $default_field) {
						if ($default_cat) { $search->{$default_cat}->{$field} = $search->{parsed}->{$comp}; }
						else { $search->{$comp}->{$field} = $search->{parsed}->{$comp}; }
					}
				}
			}
		}
	}
	
	# Build where clause
	my @where;
	my $fail_search;
	
	# id_lists
	if ($search->{id_list}) {
		foreach my $key (keys(%{$search->{id_list}})) {
			unless ($valid_search->{id_list}->{$key} && $search->{id_list}->{$key} && @{$search->{id_list}->{$key}}) { next; }
			my $whereSQL = $self->make_list_sql("$valid_search->{id_list}->{$key}.$key", $search->{id_list}->{$key}, 'int');
			if ($whereSQL) { push(@where, $whereSQL); }
			else { $fail_search = 1; }
		}
	}
	# flags
	if ($search->{flags}) {
		foreach my $key (keys(%{$search->{flags}})) {
			unless ($valid_search->{flags}->{$key} && defined($search->{flags}->{$key})) { next; }
			if ($search->{flags}->{$key}) { push(@where, "$valid_search->{flags}->{$key}.$key = true"); }
			else { push(@where, "$valid_search->{flags}->{$key}.$key = false"); }
		}
	}
	# when
	if ($search->{when}) {
		foreach my $key (keys(%{$search->{when}})) {
			unless ($valid_search->{when}->{$key} && $search->{when}->{$key} && ($search->{when}->{$key}->{start} || $search->{when}->{$key}->{end})) { next; }
			my $start = $self->check_input('timestamp', $search->{when}->{$key}->{start});
			my $end = $self->check_input('timestamp', $search->{when}->{$key}->{end});
			# For a date range if no time is specified
			if ($end && ($end !~ / /)) {
				my ($end_date) = $self->selectrow_array("SELECT to_char(to_timestamp($end, 'YYYY-MM-DD') + '1 day', 'YYYY-MM-DD') as end");
				$end = $self->quote($end_date);
			}
			
			unless ($start || $end) { next; }
			my @where_sql;
			if ($start) {
				push(@where_sql, "$valid_search->{when}->{$key}.$key >= $start");
			}
			if ($end) {
				push(@where_sql, "$valid_search->{when}->{$key}.$key < $end");
			}
			if (@where_sql) { push(@where, @where_sql); }
			else { $fail_search = 1; }
		}
	}
	# xwhat
	if ($search->{xwhat}) {
		foreach my $key (keys(%{$search->{xwhat}})) {
			unless ($valid_search->{what}->{$key} && $search->{xwhat}->{$key} && @{$search->{xwhat}->{$key}}) { next; }
			my $whereSQL = $self->make_list_sql("$valid_search->{what}->{$key}.$key", $search->{xwhat}->{$key}, 'ilike');
			if ($whereSQL) { push(@where, $whereSQL); }
			else { $fail_search = 1; }
		}
	}
	# xbegins
	if ($search->{xbegins}) {
		foreach my $key (keys(%{$search->{xbegins}})) {
			unless ($valid_search->{what}->{$key} && $search->{xbegins}->{$key} && @{$search->{xbegins}->{$key}}) { next; }
			my $whereSQL = $self->make_list_sql("$valid_search->{what}->{$key}.$key", $search->{xbegins}->{$key}, 'begins');
			if ($whereSQL) { push(@where, $whereSQL); }
			else { $fail_search = 1; }
		}
	}
	# xends
	if ($search->{xends}) {
		foreach my $key (keys(%{$search->{xends}})) {
			unless ($valid_search->{what}->{$key} && $search->{xends}->{$key} && @{$search->{xends}->{$key}}) { next; }
			my $whereSQL = $self->make_list_sql("$valid_search->{what}->{$key}.$key", $search->{xends}->{$key}, 'ends');
			if ($whereSQL) { push(@where, $whereSQL); }
			else { $fail_search = 1; }
		}
	}
	# xcontains
	if ($search->{xcontains}) {
		foreach my $key (keys(%{$search->{xcontains}})) {
			unless ($valid_search->{what}->{$key} && $search->{xcontains}->{$key} && @{$search->{xcontains}->{$key}}) { next; }
			my $whereSQL = $self->make_list_sql("$valid_search->{what}->{$key}.$key", $search->{xcontains}->{$key}, 'contains');
			if ($whereSQL) { push(@where, $whereSQL); }
			else { $fail_search = 1; }
		}
	}
	## Non-exclusive searching
	my @or_where;
	# what
	if ($search->{what}) {
		foreach my $key (keys(%{$search->{what}})) {
			unless ($valid_search->{what}->{$key} && $search->{what}->{$key} && @{$search->{what}->{$key}}) { next; }
			my $whereSQL = $self->make_list_sql("$valid_search->{what}->{$key}.$key", $search->{what}->{$key}, 'ilike');
			if ($whereSQL) { push(@or_where, $whereSQL); }
		}
	}
	# begins
	if ($search->{begins}) {
		foreach my $key (keys(%{$search->{begins}})) {
			unless ($valid_search->{what}->{$key} && $search->{begins}->{$key} && @{$search->{begins}->{$key}}) { next; }
			my $whereSQL = $self->make_list_sql("$valid_search->{what}->{$key}.$key", $search->{begins}->{$key}, 'begins');
			if ($whereSQL) { push(@or_where, $whereSQL); }
		}
	}
	# ends
	if ($search->{ends}) {
		foreach my $key (keys(%{$search->{ends}})) {
			unless ($valid_search->{what}->{$key} && $search->{ends}->{$key} && @{$search->{ends}->{$key}}) { next; }
			my $whereSQL = $self->make_list_sql("$valid_search->{what}->{$key}.$key", $search->{ends}->{$key}, 'ends');
			if ($whereSQL) { push(@or_where, $whereSQL); }
		}
	}
	# contains
	if ($search->{contains}) {
		foreach my $key (keys(%{$search->{contains}})) {
			unless ($valid_search->{what}->{$key} && $search->{contains}->{$key} && @{$search->{contains}->{$key}}) { next; }
			my $whereSQL = $self->make_list_sql("$valid_search->{what}->{$key}.$key", $search->{contains}->{$key}, 'contains');
			if ($whereSQL) { push(@or_where, $whereSQL); }
		}
	}
	if (@or_where) { push(@where, '(' . join("\n    or ", @or_where) . "\n  )"); }
	elsif ($search->{what}) { $fail_search = 1; }
	
	if ($fail_search) { return; }
	
	# Finish assembling where clause
	my $whereSQL;
	if (@where) {
		$whereSQL = "\n  and " . join("\n  and ", @where);
	}
	
#	$self->{debug}->debug("\$whereSQL: $whereSQL");
	return $whereSQL;
}


#=====================================================

=head2 B<makeSuffixSQL>

=cut
#=====================================================
sub make_suffix_sql { return makeSuffixSQL(@_); }
sub makeSuffixSQL {
	my $self = shift || return; $self->{debug}->call;
	my $options = shift || return;
	my $search = $options->{search} || return;
	my $valid_order_by = $options->{valid_order_by} || {};
	my $default_order_by = $options->{default_order_by};
	my $hard_limit = 2048;
	my $default_limit = 50;
	if ($search->{export}) { $hard_limit = $default_limit = 100000; }
	
	# Calculate pages
	$search->{limit} += 0;
	if ($search->{limit} < 1) { $search->{limit} = $default_limit; }
	elsif ($search->{limit} > $hard_limit) { $search->{limit} = $hard_limit; }
	my $limit_sql = "\n		LIMIT $search->{limit}";
	
	$search->{offset} += 0;
	if (($search->{offset} < 0) || ($search->{offset} > $hard_limit)) { $search->{offset} = 0; }
	my $offset_sql;
	if ($search->{offset}) { $offset_sql = "\n		OFFSET $search->{offset}"; }
	
	# Make order by
	my @order_by;
	if ($search->{order_by} && @{$search->{order_by}}) {
		foreach my $order (@{$search->{order_by}}) {
			$order->{field} || next;
			$valid_order_by->{$order->{field}} || next;
			my ($key, $function) = split(',', $valid_order_by->{$order->{field}});
			my $order_by = $key . '.' . $order->{field};
			if ($order->{modifier}) {
				$order_by = $order->{modifier} . '(' . $key . '.' . $order->{field} . ')';
			} elsif ($function eq 'l') {
				$order_by = 'lower(' . $key . '.' . $order->{field} . ')';
			}
			if ($order->{sort_order} eq 'desc') { $order_by .= ' DESC'; }
			else { $order_by .= ' ASC'; }
			if ($function eq 'n') {
				if ($order->{sort_order} eq 'desc') { $order_by .= ' NULLS LAST'; }
				else { $order_by .= ' NULLS FIRST'; }
			}
			push(@order_by, $order_by);
		}
	}
	my $order_by = join(', ', @order_by) || $default_order_by;
	my $order_by_sql;
	if ($order_by) { $order_by_sql = "\n		ORDER BY $order_by"; }
	
	my $suffixSQL = "$order_by_sql$limit_sql$offset_sql";
#	$self->{debug}->debug("\$suffixSQL: $suffixSQL");
	
	return $suffixSQL;
}




#=====================================================
# Field Testing Methods
#=====================================================


#=====================================================

=head2 B<getTableInfo>

=cut
#=====================================================
sub getTableInfo {
	my $self = shift || return; $self->{debug}->call;
	my $table = shift || return;
	
	my $tableInfo = $self->getServerInfo('tableInfo');
	if (isArrayHash($tableInfo->{$table})) {
		return $tableInfo->{$table};
	} else {
		my $sth = $self->{dbh}->table_info(undef, '%', $table, 'TABLE');
		my $tableResults = $sth->fetchall_arrayref({});
		$tableInfo->{$table} = $tableResults->[0];
		$self->setServerInfo('tableInfo', $tableInfo);
		return $tableInfo->{$table};
	}
}


#=====================================================

=head2 B<getColumnInfo>

=cut
#=====================================================
sub getColumnInfo {
	my $self = shift || return; $self->{debug}->call;
	my $table = shift || return;
	
	my $columnInfo = $self->getServerInfo('columnInfo');
	if (isArrayHash($columnInfo->{$table})) {
		return $columnInfo->{$table};
	} else {
		my $sth = $self->{dbh}->column_info(undef, '%', $table, '%');
		my $columns = $sth->fetchall_arrayref({});
		foreach my $column (@{$columns}) {
			$column->{name} = $column->{COLUMN_NAME};
			$column->{name} =~ s/["`$self->{dbFieldQuoteChar}]//g;
			$column->{quoted} = "$self->{dbFieldQuoteChar}$column->{name}$self->{dbFieldQuoteChar}";
		}
		
		$columnInfo->{$table} = $columns;
		$self->setServerInfo('columnInfo', $columnInfo);
		return $columns;
	}
}


#=====================================================

=head2 B<checkInput>

 $success = $dbh->checkInput($fieldType, $fieldValue);

=cut
#=====================================================
sub check_input { return checkInput(@_); }
sub checkInput {
	my $self = shift || return; $self->{debug}->call;
	my $type = shift || return;
	my $value = shift || return;
	
	my ($quoted) = $self->checkFieldInput('noTable', { field => $value }, $type);
	return $quoted->{field};
}


#=====================================================

=head2 B<checkFieldInput>

You probably won't need to call this method directly. It is used by other methods in this module.

 my $quoted = $self->checkFieldInput($table, $input, $old);
 
 $table - name of the table
 $input - hash of field name/value pairs of new data
 $old - optional hash of existing field name/value pairs for comparison

=cut
#=====================================================
sub check_field_input { return checkFieldInput(@_); }
sub checkFieldInput {
	my $self = shift || return; $self->{debug}->call;
	my $table = shift || return;
	my $input = shift;
	my $old = shift;
	my $where = shift;
	
	# Get field info
	my $columns;
	if ($table eq 'noTable') {
		push(@{$columns}, {
			COLUMN_NAME	=> 'field',
			TYPE_NAME	=> $old
		});
		undef($old);
	} elsif ($self->{dbType} eq 'sqlite') {
#		my @answer = `sqlite3 $self->{db_name} ".schema $table"`;
# 		my @answer = load_schema($table);
# 		foreach my $line (@answer) {
# 			chomp($line);
# 			my ($info, $type);
# 			($info->{COLUMN_NAME}, $type, $info->{COLUMN_SIZE}) = $line =~ /^\s*"(\w+)"\s+(\w+)(?:\((\d+)\))?/;
# 			$info->{COLUMN_NAME} || next;
# 			if ($type eq 'INTEGER') {
# 				$info->{TYPE_NAME} = 'int';
# 			} else {
# 				$info->{TYPE_NAME} = lc($type);
# 			}
# 			push(@{$columns}, $info);
# 		}
	} else {
		$columns = $self->getColumnInfo($table);
	}
# 	if ($table eq 'item_time_draft') {
# 		$self->{debug}->print_object($input, 'check_field_input $input');
# 	}
	
	my $modified;
	# Check input and quote
	my $quoted;
	foreach my $column (@{$columns}) {
		my $field = $column->{COLUMN_NAME};
		$field =~ s/["`$self->{dbFieldQuoteChar}]//g;
		my $type = lc($column->{TYPE_NAME});
		my $prec = $column->{COLUMN_SIZE};
		
		my $inputArray = [];
		if (!defined($input->{$field}) && ($field ne 'modified_timestamp') && ($field ne 'modify_timestamp')) {
			next;
		} elsif (ref($input->{$field}) eq 'ARRAY') {
			$inputArray = $input->{$field};
		} else {
			$inputArray = [$input->{$field}];
		}
		
		my $quotedList = [];
		my $inputList;
		foreach my $value (@{$inputArray}) {
			my $quote;
			my $newInput = $value;
			if (($type =~ /^timestamp/) && (($field eq 'modified_timestamp') || ($field eq 'modify_timestamp'))) {
				unless ($where) { $quote = 'CURRENT_TIMESTAMP'; }
			}
			elsif (($type =~ /^timestamp/) || ($type eq 'datetime')) {
				if ($old && ($value eq $old->{$field})) { next; }
				my $part = [];
				if ($value =~ /^(now|today|tomorrow|yesterday)(?:\(\))?$/i) {
					$quote = lc($1) . '()';
				} elsif ($value =~ /^(?:current_date|current_time|current_timestamp|localtime|localtimestamp)$/i) {
					$quote = uc($value);
				} elsif (@{$part} = $value =~ m#^\s*(\d{4}-?\d{2}-?\d{2}(?:T\d{2}:?\d{2}(?::?\d{2}(?:[\.,]\d*)?)?(?:[+-]?\d+|Z)?)?)\s*$#i) {
					if ($value =~ /^0000/) { $quote = 'NULL'; }
					else { $quote = $self->quote(uc($1)); }
				} elsif (@{$part} = $value =~ m#^\s*(\d{1,2})/(\d{1,2})/(\d{4})(?: (\d{1,2}):(\d{2})(?::(\d{2}(?:\.\d*)?))?(?:\s*([ap]m))?(?:\s+([+-]?\d+|[\w\/]+))?)?\s*$#i) {
					# 1/01/2008 12:01 am
					my $year = sprintf("%04d", $part->[2]);
					my $month = sprintf("%02d", $part->[0]);
					my $day = sprintf("%02d", $part->[1]);
					my $hour = sprintf("%02d", $part->[3]);
					my $minute = sprintf("%02d", $part->[4]);
					my $second = sprintf("%02d", $part->[5]);
					if ($part->[6] =~ /^pm$/i) {
						if ($hour < 12) { $hour += 12; }
					} else {
						if ($hour == 12) { $hour = 0; }
					}
					my $tz = $part->[7] || $self->{timeZone};
					if ($part->[3] || $part->[4] || $part->[5]) {
						if ($type =~ /without/) { undef($tz); }
						elsif ($tz =~ /^([+-])(\d+)$/) { $tz = $1 . sprintf("%02d", $2); }
						else { $tz = " $tz"; }
						$value = "$year-$month-$day $hour:$minute:$second$tz";
					} else {
						$value = "$year-$month-$day";
					}
					$newInput = $value;
					$quote = $self->quote($value);
				} elsif (@{$part} = $value =~ /^\s*(\d{4})-(\d{1,2})-(\d{1,2})(?: (\d{1,2}):(\d{2})(?::(\d{2}(?:\.\d*)?))?(?:\s*([ap]m))?(?:\s*([+-]?\d+|[\w\/]+))?)?\s*$/i) {
					# 2008-01-01 12:01 am
					my $year = sprintf("%04d", $part->[0]);
					my $month = sprintf("%02d", $part->[1]);
					my $day = sprintf("%02d", $part->[2]);
					my $hour = sprintf("%02d", $part->[3]);
					my $minute = sprintf("%02d", $part->[4]);
					my $second = sprintf("%02d", $part->[5]);
					if ($part->[6] =~ /^pm$/i) {
						if ($hour < 12) { $hour += 12; }
					} else {
						if ($hour == 12) { $hour == 0; }
					}
					my $tz = $part->[7] || $self->{timeZone};
					if ($part->[3] || $part->[4] || $part->[5]) {
						if ($type =~ /without/) { undef($tz); }
						elsif ($tz =~ /^([+-])(\d+)$/) { $tz = $1 . sprintf("%02d", $2); }
						else { $tz = " $tz"; }
						$value = "$year-$month-$day $hour:$minute:$second$tz";
					} else {
						$value = "$year-$month-$day";
					}
					$newInput = $value;
					if ($value =~ /^0000/) { $quote = 'NULL'; }
					else { $quote = $self->quote($value); }
				} elsif (@{$part} = $value =~ m#^\s*(?:\w{3}, )?(\d{1,2}) (Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|June?|July?|Aug(?:ust)?|Sept?(?:ember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?) (\d{4})(?: (\d{1,2}):(\d{2})(?::(\d{2}))?(?:\s*([+-]?\d+|[\w\/]+))?)?\s*$#i) {
					my @months = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
					my $cnt = 1;
					my $month;
					foreach my $mon (@months) {
						if ($part->[1] =~ /^$mon/i) { $month = $cnt; last; }
						$cnt++;
					}
					my $year = sprintf("%04d", $part->[2]);
#					my $month = sprintf("%02d", $part->[1]);
					my $day = sprintf("%02d", $part->[0]);
					my $hour = sprintf("%02d", $part->[3]);
					my $minute = sprintf("%02d", $part->[4]);
					my $second = sprintf("%02d", $part->[5]);
					my $tz = $part->[6] || $self->{timeZone};
					if ($part->[3] || $part->[4] || $part->[5]) {
						if ($type =~ /without/) { undef($tz); }
						elsif ($tz =~ /^([+-])(\d+)$/) { $tz = $1 . sprintf("%02d", $2); }
						else { $tz = " $tz"; }
						$value = "$year-$month-$day $hour:$minute:$second$tz";
					} else {
						$value = "$year-$month-$day";
					}
					$newInput = $value;
					$quote = $self->quote($value);
				} elsif (!$value || ($value eq 'NULL')) {
					unless ($where) { $quote = 'NULL'; }
				} else {
					$self->{debug}->post( {
						caller	=> [caller(0)],
						level	=> 'warning',
						field	=> $field,
						message	=> "This field ($field) must be a date. ($value)"
					} );
				}
			}
			elsif ($type eq 'interval') {
				if ($old && ($value eq $old->{$field})) { next; }
				if ($value =~ /^-?(\d+|(?:\d+ )?\d+:\d+(?::\d+)?)$/) {
					$quote = $self->quote($value);
				} elsif ($value =~ /^(\d+ (?:millennium|millennia|century|centuries|decade|year|month|week|day|hour|min|sec)s? ?)+$/) {
					$quote = $self->quote($value);
				} elsif (!$value || ($value eq 'NULL')) {
					unless ($where) { $quote = 'NULL'; }
				} else {
					$self->{debug}->post( {
						caller	=> [caller(0)],
						level	=> 'warning',
						field	=> $field,
						message	=> "This field ($field) must be an interval. ($value)"
					} );
				}
			}
			elsif ($type eq 'boolean') {
				if ($old && (($value && $old->{$field}) || (!$value && !$old->{$field}))) { next; }
				if (isBoolean($value) && $value) { $quote = 'TRUE'; }
				elsif (isBoolean($value)) { $quote = 'FALSE'; }
				elsif ($value eq 'NULL') {
					$quote = 'NULL';
				} elsif ($value) {
					$quote = 'TRUE';
				} else {
					$quote = 'FALSE';
				}
			}
			elsif ($type eq 'float') {
				$value =~ s/(?:^\s+|\s+$)//g;
				if ($old && ($value == $old->{$field})) { next; }
				if ($value =~ /^\-?\d+(?:\.\d*)?$/) {
					$quote = $self->quote($value);
				} elsif (!$value || ($value eq 'NULL')) {
					unless ($where) { $quote = 'NULL'; }
				} else {
					$self->{debug}->post( {
						caller	=> [caller(0)],
						level	=> 'warning',
						field	=> $field,
						message	=> "This field ($field) must be a number."
					} );
				}
			}
			elsif ($type =~ /^(numeric|real)$/) {
				$value =~ s/(?:^\s+|\s+$)//g;
				if ($old && ($value == $old->{$field})) { next; }
				if ($value =~ /^\-?(?:\d+|\d*\.\d+|\d+\.\d*)$/) {
					$quote = $self->quote($value);
				} elsif (!$value || ($value eq 'NULL')) {
					unless ($where) { $quote = 'NULL'; }
				} else {
					$self->{debug}->post( {
						caller	=> [caller(0)],
						level	=> 'warning',
						field	=> $field,
						message	=> "This field ($field) must be a number."
					} );
				}
			}
			elsif ($type =~ /^(int|smallint)/) {
				$value =~ s/(?:^\s+|\s+$)//g;
				if ($old && ($value == $old->{$field})) { next; }
				if ($value =~ /^\-?\d+$/) {
					$quote = $self->quote($value);
				} elsif (!$value || ($value eq 'NULL')) {
					unless ($where) { $quote = 'NULL'; }
				} else {
					$self->{debug}->post( {
						caller	=> [caller(0)],
						level	=> 'warning',
						field	=> $field,
						message	=> "This field ($field) must be an integer."
					} );
				}
			}
			elsif ($type =~ /^(varchar|character varying|text)$/) {
				if ($old && ($value eq $old->{$field})) { next; }
				if (($field eq 'repeat_freq') && !$value) {
					unless ($where) { $quote = 'NULL'; }
				} elsif (defined($value) && ($value ne 'NULL')) {
					$quote = $self->quote($value);
				} else {
					unless ($where) { $quote = 'NULL'; }
				}
			}
			elsif ($type eq 'json') {
				if ($old && ($value eq $old->{$field})) { next; }
				if (defined($value) && ($value ne 'NULL')) {
					$quote = $self->quote($value);
				} else {
					unless ($where) { $quote = 'NULL'; }
				}
			}
			elsif ($type =~ /^(point)$/) {
				if ($old && ($value eq $old->{$field})) { next; }
				if (defined($value) && ($value ne 'NULL')) {
					$quote = $self->quote($value);
				} else {
					unless ($where) { $quote = 'NULL'; }
				}
			}
			elsif ($type =~ /^(inet)/) {
				$value =~ s/(?:^\s+|\s+$)//g;
				if ($old && ($value == $old->{$field})) { next; }
				if ($value =~ /^(\d+\.\d+\.\d+\.\d+)/) {
					$quote = $self->quote($1);
				} elsif (!$value || ($value eq 'NULL')) {
					unless ($where) { $quote = 'NULL'; }
				} else {
					$self->{debug}->post( {
						caller	=> [caller(0)],
						level	=> 'warning',
						field	=> $field,
						message	=> "This field ($field) must be an inet."
					} );
				}
			}
			else {
				$self->{debug}->post( {
					caller	=> [caller(0)],
					level	=> 'critical',
					field	=> $field,
					message	=> "Found unknown field type. table='$table', name='$field', type='$type', prec='$prec'."
				} );
			}
#			print STDERR "Found unknown field type. table='$table', name='$field', type='$type', prec='$prec'.\n";
			if (defined($quote)) {
				push(@{$quotedList}, $quote);
			}
			push(@{$inputList}, $newInput);
		}
		
		if (ref($input->{$field}) eq 'ARRAY') {
			if (defined($quotedList->[0])) {
				$quoted->{$field} = $quotedList;
				$modified = 1;
			}
			if ($inputList && (ref($inputList) eq 'ARRAY')) {
				$input->{$field} = $inputList;
			}
		} else {
			if (defined($quotedList->[0])) {
				$quoted->{$field} = $quotedList->[0];
				unless (($field eq 'modified_timestamp') || ($field eq 'modify_timestamp')) { $modified = 1; }
			}
			if ($inputList && (ref($inputList) eq 'ARRAY')) {
				$input->{$field} = $inputList->[0];
			}
		}
	}
	
	return ($quoted, $modified);
}

#=====================================================

=head2 B<getISOTimestamp>

 $timestamp = $dbh->getISOTimestamp;
 returns '2012-10-08T22:24:52.178Z'

=cut
#=====================================================
sub getISOTimestamp {
	my $self = shift || return;
	my ($current) = $self->{dbh}->selectrow_array("
		SELECT CURRENT_TIMESTAMP(3) at time zone 'UTC'
	");
	$current =~ s/ /T/;
	$current .= 'Z';
	return $current;
}


#=====================================================

=head2 B<getServerInfo>

 my $info = getServerInfo($key);

=cut
#=====================================================
sub getServerInfo {
	my $self = shift || return;
	my $key = shift || return;
	$self->{dbName} || return;
	
	if (exists($SitemasonPl::serverInfo->{$self->{dbName}}->{$key})) {
		return copyRef($SitemasonPl::serverInfo->{$self->{dbName}}->{$key});
	}
	return;
}

#=====================================================

=head2 B<setServerInfo>

 my $info = setServerInfo($key, $value);

=cut
#=====================================================
sub setServerInfo {
	my $self = shift || return;
	my $key = shift || return;
	my $value = shift;
	$self->{dbName} || return;
	
	$SitemasonPl::serverInfo->{$self->{dbName}}->{$key} = copyRef($value);
	return TRUE;
}

#=====================================================

=head2 B<clearServerInfo>

 clearServerInfo($key);

=cut
#=====================================================
sub clearServerInfo {
	my $self = shift || return;
	my $key = shift || return;
	$self->{dbName} || return;
	
	if (exists($SitemasonPl::serverInfo->{$self->{dbName}}->{$key})) {
		delete $SitemasonPl::serverInfo->{$self->{dbName}}->{$key};
		return TRUE;
	}
	return;
}



# sub load_schema {
# 	my $table = shift;
# 	my $schema;
# 	if ($table eq 'server') {
# 		$schema = <<"EOL";
# CREATE TABLE "server" (
#   "id" INTEGER PRIMARY KEY AUTOINCREMENT,
#   "ami" VARCHAR(24),
#   "reservation_id" VARCHAR(24),
#   "instance_id" VARCHAR(24),
#   "state" VARCHAR(24),
#   "key" VARCHAR(64),
#   "public_ip" VARCHAR(15),
#   "private_ip" VARCHAR(15),
#   "name" VARCHAR(32),
#   "enterprise" VARCHAR(32),
#   "zone" VARCHAR(16),
#   "last_checkin" INTEGER,
#   "last_load" VARCHAR(16),
#   "last_df" VARCHAR(16),
#   "server_type" VARCHAR(24),
#   "groups" VARCHAR(128)
# );
# EOL
# 	} elsif ($table eq 'service') {
# 		$schema = <<"EOL";
# CREATE TABLE "service" (
#   "id" INTEGER PRIMARY KEY AUTOINCREMENT,
#   "name" VARCHAR(32) NOT NULL
# );
# EOL
# 	} elsif ($table eq 'server_service') {
# 		$schema = <<"EOL";
# CREATE TABLE "server_service" (
#   "service_id" INTEGER,
#   "server_id" INTEGER
# );
# EOL
# 	}
# 	
# 	return split("\n", $schema);
# }



=head1 CHANGES

  20060308 TJM - v0.01 started development
  2006???? TJM - v1.00 added PostgreSQL support
  2007???? TJM - v2.00 added MySQL support
  20080415 TJM - v3.00 added SQLite3 support
  20080716 TJM - v3.50 merged Sitemason::System::Database and Sitemason::Database
  20120105 TJM - v6.0 moved from Sitemason::System to Sitemason6::Library
  20140320 TJM - v7.0 merged 3.50 and 6.0
  20171109 TJM - v8.0 Moved to SitemasonPL open source project and merged with updates

=head1 AUTHOR

  Tim Moses <tim@moses.com>
  Sitemason Open Source <https://github.com/sitemason>

=cut

1;
