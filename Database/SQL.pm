package SitemasonPl::Database::SQL 8.0;
@ISA = qw( SitemasonPl::Database );

=head1 NAME

SitemasonPl::Database::SQL

=head1 DESCRIPTION

An interface for working with SQL databases.

=head1 METHODS

=cut

use v5.012;
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

sub new {
#=====================================================

=head2 B<new>

Creates and returns a database handle.

Errors:
	db:			all
	sql:		sql statements
	command:	summary of every sql call
	{sql cmd}:	each sql command has a tag, like 'select', 'insert', 'update', 'delete'

 use SitemasonPl::Database::SQL;
 my $dbh = SitemasonPl::Database::SQL->new(
	db_type		=> 'pg' || 'mysql' || 'sqlite',
	db_host		=> $db_host,
	db_port		=> $db_port,
	db_sock		=> $db_sock,
	db_name		=> $db_name,
	db_username	=> $db_username,
	db_password	=> $db_password,
	
	# pass original script's debug to share timing and logging
	debug		=> $debug
 );

=cut
#=====================================================
	my ($class, %arg) = @_;
	$class || return;
	
	my $self = {
		db_type		=> $arg{db_type}		|| 'pg',
		db_host		=> $arg{db_host}		|| $SitemasonPl::serverInfo->{db_info}->{db_host},
		db_port		=> $arg{db_port}		|| $SitemasonPl::serverInfo->{db_info}->{db_port},
		db_username	=> $arg{db_username}	|| $SitemasonPl::serverInfo->{db_info}->{db_username},
		db_password	=> $arg{db_password}	|| $SitemasonPl::serverInfo->{db_info}->{db_password},
		db_sock		=> $arg{db_sock},
		db_name		=> $arg{db_name},
		time_zone	=> $arg{time_zone}	|| 'UTC'
	};
	
	if ($self->{db_type} eq 'pg') {
		$self->{db_host}		||= $ENV{PGHOST};
		$self->{db_port}		||= $ENV{PGPORT};
		$self->{db_username}	||= $ENV{PGUSER};
		$self->{db_password}	||= $ENV{PGPASS} || $ENV{PGPASSWORD};
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
	if ($self->{db_name}) { $name = "dbname=$self->{db_name}"; }
	my $host;
	if ($self->{db_host}) { $host = "host=$self->{db_host};"; }
	my $port;
	if ($self->{db_port}) { $port = "port=$self->{db_port};"; }
	my $sock;
	if ($self->{db_sock}) { $sock = "mysql_socket=$self->{db_sock};"; }
	my $user;
	if ($self->{db_username}) { $user = $self->{db_username}; }
	my $pass;
	if ($self->{db_password}) { $pass = $self->{db_password}; }
	
	my $type;
	if ($self->{db_type} eq 'sqlite') { $type = 'SQLite'; }
	elsif ($self->{db_type} eq 'mysql') { $type = 'mysql'; }
	elsif ($self->{db_type} eq 'pg') { $type = 'Pg'; }
	my $connectInfo = "DBI:${type}:${host}${port}${sock}${name}";
	
	bless $self, $class;
	if ($type) {
		my $connectMessage = 'Connecting';
		$self->{dbh} = DBI->connect($connectInfo, $user, $pass, { PrintError => 1, AutoCommit => 1 });
	}
	
	unless (defined($self->{dbh})) {
		$self->{debug}->emergency("Failed to reach database");
		return;
	}
	
	# Set PostgreSQL default time zone to UTC
	if ($self->{db_type} eq 'pg') {
		$self->{dbh}->{'pg_enable_utf8'} = 1;
		$self->{dbh}->do("SET NAMES 'utf8'");
		$self->{dbh}->do("SET SESSION TIME ZONE 'UTC'");
	}
	# Enable UTF8 for MySQL
	elsif ($self->{db_type} eq 'mysql') {
		$self->{dbh}->{'mysql_enable_utf8'} = 1;
		$self->{dbh}->do("SET NAMES 'utf8'");
	}
	
	$self->{db_info_type} = lc($self->{dbh}->get_info(17)); # 'postgresql'
	$self->{db_version} = $self->{dbh}->get_info(18);
	$self->{db_field_quote_char} = $self->{dbh}->get_info(29) || '`';
#	my $rv = $self->{dbh}->do("SET client_encoding TO 'UTF8';");
	
	$self->{log} = {
		select	=> 0,
		insert	=> 0,
		update	=> 0,
		delete	=> 0,
		nextval	=> 0
	};
	
	$self->{connectInfo} = $connectInfo;
	$self->set_server_info('connectInfo', $connectInfo);
	$self->set_server_info('dbh', $self);
	return $self;
}


sub reconnect {
#=====================================================

=head2 B<reconnect>

After a statement is executed, check state. 57000 08000

 my $state = $self->{dbh}->state;
 if ($self->reconnect($state)) { <<redo command>> }

=cut
#=====================================================
	my $self = shift || return; $self->{debug}->call;
	my $state = shift || return;
	if ($state eq '22021') { return; }
	if ($state) { $self->{debug}->error("Potential DB idle timeout ($state) $self->{db_name}"); }
	
	unless (($state eq '57000') || ($state eq '08000')) { $self->{debug}->info('Failing based on state number'); return; }
	
	my $connectInfo = $self->{connectInfo} || $self->get_server_info('connectInfo');
	if (!$connectInfo) { $self->{debug}->warning('Could not get connection info'); return; }
	
	$self->{debug}->info(">>>>>> Reconnecting to db '" . $self->{db_name} . "' <<<<<<");
	$self->{dbh} = DBI->connect($connectInfo, $self->{db_username}, $self->{db_password}, { PrintError => 1, AutoCommit => 1 });
	
	unless (defined($self->{dbh})) {
		$self->{debug}->emergency("Failed to reach database");
		return;
	}
	
	# Set PostgreSQL default time zone to UTC
	if ($self->{db_type} eq 'pg') {
		$self->{dbh}->{'pg_enable_utf8'} = 1;
		$self->{dbh}->do("SET NAMES 'utf8'");
		$self->{dbh}->do("SET SESSION TIME ZONE 'UTC'");
	}
	# Enable UTF8 for MySQL
	elsif ($self->{db_type} eq 'mysql') {
		$self->{dbh}->{'mysql_enable_utf8'} = 1;
		$self->{dbh}->do("SET NAMES 'utf8'");
	}
	
	return TRUE;
}


#=====================================================
# DBI-like Methods
#=====================================================

sub quote {
#=====================================================

=head2 B<quote>

$type can be 'begins', 'ends', 'like', 'qlike', 'word', or default

 my $quoted = $self->{dbh}->quote($stringOrArrayOrHash, $type, $limit);

=cut
#=====================================================
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
		$quoted = _modify_quote($quoted, $type);
	} else {
		$quoted = 'NULL';
	}
	return $quoted;
}

sub _modify_quote {
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

sub quote_list {
	my $self = shift || return;
	my $inputList = shift || return;
	my $qlist = $self->quote($inputList);
	my $qstring = join(', ', @{$qlist});
	return $qstring;
}

sub uncommit {
#=====================================================

=head2 B<uncommit>

 $dbh->uncommit;

=cut
#=====================================================
	my $self = shift || return; $self->{debug}->call;
	$self->{dbh}->{'AutoCommit'} = 0;
}

sub commit {
#=====================================================

=head2 B<commit>

 $dbh->commit;

=cut
#=====================================================
	my $self = shift || return; $self->{debug}->call;
	$self->{dbh}->{'AutoCommit'} = 1;
}


sub current_date {
#=====================================================

=head2 B<current_date>

=cut
#=====================================================
	my $self = shift || return; $self->{debug}->call;
	my $time_zone = shift || 'UTC';
	
	my $qzone = $self->{dbh}->quote($time_zone);
	$self->uncommit;
	$self->{dbh}->do("SET LOCAL TIME ZONE $qzone");
	my ($current_date) = $self->{dbh}->selectrow_array("SELECT CURRENT_DATE");
	$self->commit;
	return $current_date;
}

sub quoted_current_date {
#=====================================================

=head2 B<quoted_current_date>

=cut
#=====================================================
	my $self = shift || return; $self->{debug}->call;
	my $time_zone = shift;
	my $current_date = $self->current_date($time_zone);
	return $self->{dbh}->quote($current_date);
}

sub nextval {
#=====================================================

=head2 B<nextval>

 $id = $self->{dbh}->nextval($table);
 $id = $self->{dbh}->nextval($table, $idFieldName);

=cut
#=====================================================
	my $self = shift || return; $self->{debug}->call;
	my $table = shift || return;
	my $idFieldName = shift;
	my $log = shift;
	
	if (!$idFieldName || is_pos_int($idFieldName) || ($idFieldName eq 'debug')) { $log = $idFieldName; $idFieldName = 'id'; }
	
	my $statement = "SELECT nextval('${table}_${idFieldName}_seq')";
	$self->_log_sql($statement, [caller(0)], $log);
	
	my $id;
	if ($log eq 'debug') {
		($id) = $self->selectrow_array("SELECT max($idFieldName) as id FROM $table", 'noLog');
	} else {
		my $timerKey = $self->timer_start($statement, $log);
		($id) = $self->selectrow_array($statement, 'noLog');
		my $duration = $self->timer_stop($timerKey, $log);
		$self->_log_transaction($statement, $duration, [caller(0)], $log);
	}
	return $id;
}


sub do {
#=====================================================

=head2 B<do>

 $rv = $dbh->do($statement);
 $rv = $dbh->do($statement, 'sql' || 'results' || 'both' || 'debug');

=cut
#=====================================================
	my $self = shift || return; $self->{debug}->call;
	my $statement = shift;
	my $log = shift;
	$self->_log_sql($statement, [caller(0)], $log);
	unless ($statement) { return; }
	
	my $rv;
	$statement = $self->_clean_sql($statement);
	if ($log eq 'debug') {
		$rv = '1';
		my ($command, $table) = $self->_get_command_from_statement($statement);
		if (($command eq 'update') || ($command eq 'delete')) {
			my $columns = $self->get_column_info($table);
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
		my $timerKey = $self->timer_start($statement, $log);
		$rv = $self->{dbh}->do($statement);
		if ($self->reconnect($self->{dbh}->state)) {
			$rv = $self->{dbh}->do($statement);
		}
		my $duration = $self->timer_stop($timerKey, $log);
		$self->_log_transaction($statement, $duration, [caller(0)], $log);
	}
	my ($command, $table) = $self->_get_command_from_statement($statement);
	if ($rv eq '0E0') {
		my $message;
		if ($command eq 'delete') { $message = 'Nothing to delete.'; }
		elsif ($command eq 'update') { $message = 'Nothing to update.'; }
		elsif ($command eq 'alter') { return $rv; }
		if ($message) {
#			$self->{debug}->debug($message, new_hash({ tags => 'results' }, $log));
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
#			$self->{debug}->debug($message, new_hash({ tags => 'results' }, $log));
		} else {
			$self->{debug}->critical("Unrecognized command, $command on " . $message, $log);
		}
	}
	return $rv;
}


sub selectrow_array {
#=====================================================

=head2 B<selectrow_array>

 @rowAry  = $dbh->selectrow_array($statement);

=cut
#=====================================================
	my $self = shift || return; $self->{debug}->call;
	my $statement = shift;
	my $log = shift;
	$self->_log_sql($statement, [caller(0)], $log);
	$statement = $self->_clean_sql($statement);
	unless ($statement) { return; }
	
	my $timerKey = $self->timer_start($statement, $log);
	my @rowAry = $self->{dbh}->selectrow_array($statement);
	if ($self->reconnect($self->{dbh}->state)) {
		@rowAry = $self->{dbh}->selectrow_array($statement);
	}
	my $duration = $self->timer_stop($timerKey, $log);
	$self->_log_transaction($statement, $duration, [caller(0)], $log);
	return @rowAry;
}


sub selectrow_arrayref {
#=====================================================

=head2 B<selectrow_arrayref>

 $aryRef  = $dbh->selectrow_arrayref($statement);

=cut
#=====================================================
	my $self = shift || return; $self->{debug}->call;
	my $statement = shift;
	my $log = shift;
	$self->_log_sql($statement, [caller(0)], $log);
	$statement = $self->_clean_sql($statement);
	unless ($statement) { return; }
	
	my $timerKey = $self->timer_start($statement, $log);
	my $aryRef = $self->{dbh}->selectrow_arrayref($statement);
	if ($self->reconnect($self->{dbh}->state)) {
		$aryRef = $self->{dbh}->selectrow_arrayref($statement);
	}
	my $duration = $self->timer_stop($timerKey, $log);
	$self->_log_transaction($statement, $duration, [caller(0)], $log);
	return $aryRef;
}


sub selectrow_hashref {
#=====================================================

=head2 B<selectrow_hashref>

 $hashRef = $dbh->selectrow_hashref($statement);

=cut
#=====================================================
	my $self = shift || return; $self->{debug}->call;
	my $statement = shift;
	my $log = shift;
	$self->_log_sql($statement, [caller(0)], $log);
	$statement = $self->_clean_sql($statement);
	unless ($statement) { return; }
	
	my $timerKey = $self->timer_start($statement, $log);
	my $hashRef = $self->{dbh}->selectrow_hashref($statement);
	if ($self->reconnect($self->{dbh}->state)) {
		$hashRef = $self->{dbh}->selectrow_hashref($statement);
	}
	my $duration = $self->timer_stop($timerKey, $log);
	$self->_log_transaction($statement, $duration, [caller(0)], $log);
	return $hashRef;
}


sub selectcol_arrayref {
#=====================================================

=head2 B<selectcol_arrayref>

 $aryRef  = $dbh->selectcol_arrayref($statement);

=cut
#=====================================================
	my $self = shift || return; $self->{debug}->call;
	my $statement = shift;
	my $log = shift;
	$self->_log_sql($statement, [caller(0)], $log);
	$statement = $self->_clean_sql($statement);
	unless ($statement) { return; }
	
	my $timerKey = $self->timer_start($statement, $log);
	my $aryRef = $self->{dbh}->selectcol_arrayref($statement);
	if ($self->reconnect($self->{dbh}->state)) {
		$aryRef = $self->{dbh}->selectcol_arrayref($statement);
	}
	my $duration = $self->timer_stop($timerKey, $log);
	$self->_log_transaction($statement, $duration, [caller(0)], $log);
	return $aryRef;
}


sub selectall_arrayref {
#=====================================================

=head2 B<selectall_arrayref>

$aryRef  = $dbh->selectall_arrayref($statement);

=cut
#=====================================================
	my $self = shift || return; $self->{debug}->call;
	my $statement = shift;
	my $log = shift;
	$self->_log_sql($statement, [caller(0)], $log);
	$statement = $self->_clean_sql($statement);
	unless ($statement) { return; }
	
	my $timerKey = $self->timer_start($statement, $log);
	my $aryRef = $self->{dbh}->selectall_arrayref($statement);
	if ($self->reconnect($self->{dbh}->state)) {
		$aryRef = $self->{dbh}->selectall_arrayref($statement);
	}
	my $duration = $self->timer_stop($timerKey, $log);
	$self->_log_transaction($statement, $duration, [caller(0)], $log);
	return $aryRef;
}


sub selectall_hashref {
#=====================================================

=head2 B<selectall_hashref>

 $hashRef = $dbh->selectall_hashref($statement, $keyField);

=cut
#=====================================================
	my $self = shift || return; $self->{debug}->call;
	my $statement = shift;
	my $keyField = shift;
	my $log = shift;
	$self->_log_sql($statement, [caller(0)], $log);
	$statement = $self->_clean_sql($statement);
	unless ($statement) { return; }
	unless ($keyField) {
		$self->{debug}->critical('No key field', $log);
		return;
	}
	
	my $timerKey = $self->timer_start($statement, $log);
	my $hashRef = $self->{dbh}->selectall_hashref($statement, $keyField);
	if ($self->reconnect($self->{dbh}->state)) {
		$hashRef = $self->{dbh}->selectall_hashref($statement, $keyField);
	}
	my $duration = $self->timer_stop($timerKey, $log);
	$self->_log_transaction($statement, $duration, [caller(0)], $log);
	return $hashRef;
}


sub selectall_arrayhash {
#=====================================================

=head2 B<selectall_arrayhash>

$aryRef  = $dbh->selectall_arrayhash($statement);

=cut
#=====================================================
	my $self = shift || return; $self->{debug}->call;
	my $statement = shift;
	my $log = shift;
	$self->_log_sql($statement, [caller(0)], $log);
	$statement = $self->_clean_sql($statement);
	unless ($statement) { return; }
	
	my $timerKey = $self->timer_start($statement, $log);
	my $sth = $self->{dbh}->prepare($statement);
	if ($self->reconnect($self->{dbh}->state)) {
		$sth = $self->{dbh}->prepare($statement);
	}
	$sth->execute;
	my $aryRef = $sth->fetchall_arrayref({});
	my $duration = $self->timer_stop($timerKey, $log);
	$self->_log_transaction($statement, $duration, [caller(0)], $log);
	return $aryRef;
}




#=====================================================
# Aggregated Execute Methods
#=====================================================

sub reorder_records {
#=====================================================

=head2 B<reorder_records>

	$self->{dbh}->reorder_records( {
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
		my $idSQL = $self->make_list_sql($idName, $idList, 'int');
		my $records = $self->selectall_hashref("
			SELECT $idName as x_id, $groupName as x_group_id
			FROM $table
			WHERE $idSQL
		", 'x_id', $log);
		
		# Load all relevant groups
		my $targetGroupIdList = to_array($moves, 'target_group_id');
		my $groupIds = toArray($records, 'x_group_id');
		push(@{$groupIds}, @{$targetGroupIdList});
		my $groupIdSQL = $self->make_list_sql($groupName, $groupIds, 'int');
		my $sortNameSQL;
		if ($sortName) { $sortNameSQL = ", $sortName"; }
		my $whereSQL;
		if ($where) { $whereSQL = " and $where"; }
		my $complete = $self->selectall_arrayhash("
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
		my $idSQL = $self->make_list_sql($idName, \@checkIds, 'int');
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
		my $idSQL = $self->make_list_sql($idName, \@uncheckIds, 'int');
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

sub do_insert { do_update_insert(@_); }
sub do_update_insert {
#=====================================================

=head2 B<do_update_insert>

 $id = $dbh->do_update_insert( {
 	id		=> $id,
 	table	=> $table,
 	input	=> $input,
 	where	=> $where,
 	idName		=> $idName,
 	noNextval	=> 1 || 0,
 	force		=> 1
 } );
 
 Most inserts...
 $id = $dbh->do_update_insert( {
 	table	=> $table,
 	input	=> $input
 } );
 
 Most updates...
 $id = $dbh->do_update_insert( {
 	id		=> $id,
 	table	=> $table,
 	input	=> $input
 } );

=cut
#=====================================================
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
		if (!$id && !$noNextval && ($self->{db_type} eq 'pg')) {
			if ($idName eq 'id') { $id = $self->nextval($table, $log); }
			else {
				($id) = $self->selectrow_array("SELECT nextval('${table}_${idName}_seq')");
			}
			$input->{$idName} = $id;
		}
	}
	
	my ($quoted, $modified) = $self->check_field_input($table, $input, $old);
	if ($modified || $force) {
		$self->_modify_fields($input, $modifiers, $old);
		($quoted, $modified) = $self->check_field_input($table, $input, $old);
	} else { return $old->{$idName}; }
	
	my $changes;
	# Update
	if ($old->{$idName}) {
		$attempt = 'update';
		my @set;
		while (my($field, $value) = each(%{$quoted})) {
			$changes->{$field} = $value;
			if ($field eq $idName) { next; }
			push(@set, "$self->{db_field_quote_char}$field$self->{db_field_quote_char}=$value");
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
			push(@names, "$self->{db_field_quote_char}$field$self->{db_field_quote_char}");
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
					if ($self->{db_type} eq 'mysql') {
						($id) = $self->{dbh}->selectrow_array("
							SELECT last_insert_id()
						");
					} elsif ($self->{db_type} eq 'sqlite') {
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


sub copy {
#=====================================================

=head2 B<copy>

 my $recordCount = $self->{dbh}->copy($table, $recordsArrayHash);

=cut
#=====================================================
	my $self = shift || return; $self->{debug}->call;
	my $table = shift || return;
	my $records = shift || return;
	my $log = shift;
	
	if (!is_arrayhash($records)) { return; }
	
	my $columns = $self->get_column_info($table);
	
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
	$self->_log_sql($copySQL, [caller(0)], $log);
	unless ($copySQL) { return; }
	
	my $timerKey = $self->timer_start($copySQL, $log);
	
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
				if ($quoted) { $quoted = $self->quote_for_copy($quoted); }
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
	my $duration = $self->timer_stop($timerKey, $log);
	$self->_log_transaction($copySQL, $duration, [caller(0)], $log);
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


sub quote_for_copy {
#=====================================================

=head2 B<quote_for_copy>

=cut
#=====================================================
	my $self = shift || return;
	my $value = shift;
	$value =~ s/\\/\\\\/g;
	$value =~ s/\t/\\t/g;
	$value =~ s/\n/\\n/g;
	$value =~ s/\r/\\r/g;
	$value =~ s/\f/\\f/g;
	return $value;
}


sub do_delete {
#=====================================================

=head2 B<do_delete>

 $success = $dbh->do_delete( {
 	table	=> $table,
 	idName	=> 'id', # defaults to 'id'
 	where	=> {
 		field1	=> $scalar || $arrayRef,
 		field2	=> $scalar || $arrayRef
 	}
 } );

=cut
#=====================================================
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
	my ($quoted) = $self->check_field_input($table, $where, {}, 1);
	
	# Delete
	if ($quoted->{$idName}) {
		my $whereSQL = $self->make_where_sql($quoted);
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

sub _log_sql {
#=====================================================

=head2 B<_log_sql>

=cut
#=====================================================
	my $self = shift || return; $self->{debug}->call;
	my $statement = shift;
	my $caller = shift;
	my $log = shift;
	if ($log eq 'noLog') { return; }
	
	if ($statement) {
		if ($log eq 'results') { return; }
		if (!$log) { return; }
		my ($cmd, $table) = $self->_get_command_from_statement($statement);
		my $level = 'debug';
		if ($log) { $level = 'info'; }
		$statement =~ s/^[ \t]*(\r\n|\n|\r)//;
		my ($tabs) = $statement =~ /^(\s+)/;
		$statement =~ s/^$tabs/  /mg;
		$statement =~ s/\t/  /g;
		$self->{debug}->post( new_hash({
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


sub _log_transaction {
#=====================================================

=head2 B<_log_transaction>

=cut
#=====================================================
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
		my ($cmd, $table) = $self->_get_command_from_statement($statement);
		my $message = "$cmd on $table";
		if ($duration) {
			$message .= " ($duration ms)";
		}
		$self->{debug}->post( new_hash({
			caller		=> $caller,
			level		=> 'debug',
			message		=> $message,
			tags		=> ['transaction', $cmd, $table],
			duration	=> $duration
		}, $log) );
	}
}


sub _get_command_from_statement {
#=====================================================

=head2 B<_get_command_from_statement>

 my ($cmd, $table) = $self->_get_command_from_statement($statement);

=cut
#=====================================================
	my $self = shift || return; $self->{debug}->call;
	my $statement = lc(shift) || return;
	
	my ($cmd) = $statement =~ /^\s*(\w+)/;
	my ($table) = $statement =~ /^\s*(?:select\s+.*?\s+from\s+|insert\s+into\s+|update\s+|delete\s+from\s+)(\w+)/s;
	if ($statement =~ /^\s*select\s+nextval\('(\w+)_id_seq/) { $cmd = 'nextval'; $table = $1; }
	
	return ($cmd, $table);
}


sub _clean_sql {
#=====================================================

=head2 B<_clean_sql>

 my $statement = $self->_clean_sql($statement);

=cut
#=====================================================
	my $self = shift || return; $self->{debug}->call;
	my $statement = shift || return;
	
	my ($tabs) = $statement =~ /^(\t+)/;
	$statement =~ s/^$tabs//mg;
	$statement =~ s/(^\s+|\s+$)//g;
	utf8::downgrade($statement, 1);
	return $statement;
}


sub _modify_fields {
#=====================================================

=head2 B<_modify_fields>

 my $modified = $self->_modify_fields($input, {
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


sub timer_start {
#=====================================================

=head2 B<timer_start>

=cut
#=====================================================
	my $self = shift || return;
	my $statement = shift;
	my $log = shift || return;
	if ($log eq 'noLog') { return; }
	
	my ($cmd, $table) = $self->_get_command_from_statement($statement);
#	my ($parent) = (caller(0))[3];
	my $unique = uniqueKey;
	my $key = 'db_' . $cmd . '_on_' . $table . '_' . $unique;
	$self->{debug}->timerStart($key);
	return $key;
}

sub timer_stop {
#=====================================================

=head2 B<timer_stop>

=cut
#=====================================================
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

sub make_list_sql {
#=====================================================

=head2 B<make_list_sql>

Returns sql for a single field of a where clause. Give it the field name and a list of values. It will quote, filter out blank values, and remove duplicates. If you also specify a type, it will test the input and generate the appropriate sql for the type.

 $sql = $self->{dbh}->make_list_sql($fieldName, $listOfValues, $type);

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
			if (is_pos_int($item)) {
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


sub make_where_sql {
#=====================================================

=head2 B<make_where_sql>

Converts a hash of name and values into a where clause. Values are used as is, unless a table name is given as a second argument. In that case, it will quote according to the field types in the table.

Name/value pairs are pieced together with 'and'. In a future version, a hierarchy of name/values could be passed with args specifying 'and' or 'or'.

 $whereSQL = $self->{dbh}->make_where_sql( {
 	$fieldName1	=> $listOfQuotedValues,
 	$fieldName2	=> $quotedValue
 }, $table);

=cut
#=====================================================
	my $self = shift || return; $self->{debug}->call;
	my $where = shift || return;
	my $table = shift;
	my $tableAbbr = shift;
	my $whereList = [];
	
	if ($table) {
		my ($quoted) = $self->check_field_input($table, $where, {}, 1);
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


sub make_sql {
#=====================================================

=head2 B<make_sql>

An easier way to parse searches and call make_search_sql and makeOrderSQL.

	my ($whereSQL, $suffixSQL, $search) = $self->{dbh}->make_sql($searchSchema, $searchArguments);
	my ($whereSQL, $suffixSQL, $search) = $self->{dbh}->make_sql( {
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
	my $self = shift || return; $self->{debug}->call;
	my $args = shift || return;
	
	my $input = $self->process_make_sql_input($args);
	my ($whereSQL, $suffixSQL);
	my $whereSQL = $self->make_search_sql( {
		search				=> $input->{search},
		valid_search		=> $input->{valid_search}
	} );
	my $suffixSQL = $self->make_suffix_sql( {
		search				=> $input->{search},
		valid_order_by		=> $input->{valid_order_by},
		default_order_by	=> $args->{default_order_by}
	} );
	
	return ($whereSQL, $suffixSQL, $input->{search}, $input->{commands});
}


sub process_make_sql_input {
#=====================================================

=head2 B<process_make_sql_input>

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
		if (is_array_with_content($params->{'m'})) {
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
		if (is_array_with_content($params->{'c'})) {
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
		if (is_array_with_content($params->{'u'})) {
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
					} elsif (is_array_with_content($params->{$fieldname})) {
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


sub make_search_sql {
#=====================================================

=head2 B<make_search_sql>

=cut
#=====================================================
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


sub make_suffix_sql {
#=====================================================

=head2 B<make_suffix_sql>

=cut
#=====================================================
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


sub get_table_info {
#=====================================================

=head2 B<get_table_info>

=cut
#=====================================================
	my $self = shift || return; $self->{debug}->call;
	my $table = shift || return;
	
	my $tableInfo = $self->get_server_info('tableInfo');
	if (is_arrayhash($tableInfo->{$table})) {
		return $tableInfo->{$table};
	} else {
		my $sth = $self->{dbh}->table_info(undef, '%', $table, 'TABLE');
		my $tableResults = $sth->fetchall_arrayref({});
		$tableInfo->{$table} = $tableResults->[0];
		$self->set_server_info('tableInfo', $tableInfo);
		return $tableInfo->{$table};
	}
}


sub get_column_info {
#=====================================================

=head2 B<get_column_info>

=cut
#=====================================================
	my $self = shift || return; $self->{debug}->call;
	my $table = shift || return;
	
	my $columnInfo = $self->get_server_info('columnInfo');
	if (is_arrayhash($columnInfo->{$table})) {
		return $columnInfo->{$table};
	} else {
		my $sth = $self->{dbh}->column_info(undef, '%', $table, '%');
		my $columns = $sth->fetchall_arrayref({});
		foreach my $column (@{$columns}) {
			$column->{name} = $column->{COLUMN_NAME};
			$column->{name} =~ s/["`$self->{db_field_quote_char}]//g;
			$column->{quoted} = "$self->{db_field_quote_char}$column->{name}$self->{db_field_quote_char}";
		}
		
		$columnInfo->{$table} = $columns;
		$self->set_server_info('columnInfo', $columnInfo);
		return $columns;
	}
}


sub check_input {
#=====================================================

=head2 B<check_input>

 $success = $dbh->check_input($fieldType, $fieldValue);

=cut
#=====================================================
	my $self = shift || return; $self->{debug}->call;
	my $type = shift || return;
	my $value = shift || return;
	
	my ($quoted) = $self->check_field_input('noTable', { field => $value }, $type);
	return $quoted->{field};
}


sub check_field_input {
#=====================================================

=head2 B<check_field_input>

You probably won't need to call this method directly. It is used by other methods in this module.

 my $quoted = $self->check_field_input($table, $input, $old);
 
 $table - name of the table
 $input - hash of field name/value pairs of new data
 $old - optional hash of existing field name/value pairs for comparison

=cut
#=====================================================
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
	} elsif ($self->{db_type} eq 'sqlite') {
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
		$columns = $self->get_column_info($table);
	}
# 	if ($table eq 'item_time_draft') {
# 		$self->{debug}->print_object($input, 'check_field_input $input');
# 	}
	
	my $modified;
	# Check input and quote
	my $quoted;
	foreach my $column (@{$columns}) {
		my $field = $column->{COLUMN_NAME};
		$field =~ s/["`$self->{db_field_quote_char}]//g;
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
					my $tz = $part->[7] || $self->{time_zone};
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
					my $tz = $part->[7] || $self->{time_zone};
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
					my $tz = $part->[6] || $self->{time_zone};
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

sub get_iso_timestamp {
#=====================================================

=head2 B<get_iso_timestamp>

 $timestamp = $dbh->get_iso_timestamp;
 returns '2012-10-08T22:24:52.178Z'

=cut
#=====================================================
	my $self = shift || return;
	my ($current) = $self->{dbh}->selectrow_array("
		SELECT CURRENT_TIMESTAMP(3) at time zone 'UTC'
	");
	$current =~ s/ /T/;
	$current .= 'Z';
	return $current;
}


sub get_server_info {
#=====================================================

=head2 B<get_server_info>

 my $info = get_server_info($key);

=cut
#=====================================================
	my $self = shift || return;
	my $key = shift || return;
	$self->{db_name} || return;
	
	if (exists($SitemasonPl::serverInfo->{$self->{db_name}}->{$key})) {
		return copy_ref($SitemasonPl::serverInfo->{$self->{db_name}}->{$key});
	}
	return;
}

sub set_server_info {
#=====================================================

=head2 B<set_server_info>

 my $info = set_server_info($key, $value);

=cut
#=====================================================
	my $self = shift || return;
	my $key = shift || return;
	my $value = shift;
	$self->{db_name} || return;
	
	$SitemasonPl::serverInfo->{$self->{db_name}}->{$key} = copy_ref($value);
	return TRUE;
}

sub clear_server_info {
#=====================================================

=head2 B<clear_server_info>

 clear_server_info($key);

=cut
#=====================================================
	my $self = shift || return;
	my $key = shift || return;
	$self->{db_name} || return;
	
	if (exists($SitemasonPl::serverInfo->{$self->{db_name}}->{$key})) {
		delete $SitemasonPl::serverInfo->{$self->{db_name}}->{$key};
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
