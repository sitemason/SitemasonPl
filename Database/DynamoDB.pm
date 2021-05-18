package SitemasonPl::Database::DynamoDB 8.0;
@ISA = qw( SitemasonPl::Database );

=head1 NAME

SitemasonPl::Database::DynamoDB

=head1 DESCRIPTION

An interface for working with DynamoDB tables.

=head1 METHODS

=cut

use v5.012;
use strict;
use utf8;
use constant TRUE => 1;
use constant FALSE => 0;

use JSON;

use SitemasonPl::Common;
use SitemasonPl::IO qw(mark print_object);


sub new {
#=====================================================

=head2 B<new>

 use SitemasonPl::Database::DynamoDB;
 $self->{dd} = SitemasonPl::Database::DynamoDB->new;

=cut
#=====================================================
	my ($class, %arg) = @_;
	$class || return;
	
	my $self = {
		db_type		=> 'DynamoDB',
		io			=> $arg{io},
		dry_run		=> $arg{dry_run},
		pipe_to_cat	=> $arg{pipe_to_cat}
	};
	if (!$self->{io}) { $self->{io} = SitemasonPl::IO->new; }
	
	bless $self, $class;
	return $self;
}


sub list_tables {
#=====================================================

=head2 B<list_tables>

 my $tables = $self->{dd}->list_tables;

=cut
#=====================================================
	my $self = shift || return;
	my $debug = shift;
	
	my $dd_tables = $self->_call_dynamodb("list-tables", $debug);
	return $dd_tables->{TableNames};
}

sub describe_table {
#=====================================================

=head2 B<describe_table>

=cut
#=====================================================
	my $self = shift || return;
	my $table_name = shift || return;
	my $debug = shift;
	state $attr;
	value($attr, $table_name) && return $attr->{$table_name};
	
	my $dd_table = $self->_call_dynamodb("describe-table --table-name $table_name", $debug);
	$attr->{$table_name} = $dd_table->{Table};
	return $attr->{$table_name};
}


sub get_table_keys {
#=====================================================

=head2 B<get_table_keys>

=cut
#=====================================================
	my $self = shift || return;
	my $table_name = shift || return;
	my $debug = shift;
	
	my $keys = [];
	my $attr = $self->describe_table($table_name, $debug);
	value($attr, ['KeySchema', '0', 'AttributeName']) || return;
	push(@{$keys}, $attr->{KeySchema}->[0]->{AttributeName});
	if (value($attr, ['KeySchema', '1', 'AttributeName'])) {
		push(@{$keys}, $attr->{KeySchema}->[1]->{AttributeName});
	}
	return $keys;
}


sub get_keys {
	my $self = shift || return;
	my $table_name = shift || return;
	my $debug = shift;
	
	my $attr = $self->describe_table($table_name, $debug);
	is_array_with_content($attr->{KeySchema}) || return;
	
	my $primary_key;
	my $range_key;
	$self->{io}->print_object($attr->{KeySchema}, '$attr->{KeySchema}');
	foreach my $key (@{$attr->{KeySchema}}) {
		$self->{io}->print_object($key, '$key');
		if ($key->{KeyType} eq 'HASH') { $primary_key = $key->{AttributeName}; }
		if ($key->{KeyType} eq 'RANGE') { $range_key = $key->{AttributeName}; }
	}
	$primary_key || return;
	$range_key || return;
	
	return ($primary_key, $range_key);
}


sub get_max_range_value {
	my $self = shift || return;
	my $table_name = shift || return;
	my $key_value = shift || return;
	my $debug = shift;
	
	my ($primary_key, $range_key) = $self->get_keys();
	print "($primary_key, $range_key)\n";
	
	my $records = $self->query($table_name, undef, {
		$primary_key	=> $key_value
	}, {
		scan_index_forward	=> FALSE,
		limit				=> 1
	}, TRUE);
	$self->{io}->print_object($records, '$records');
	
	return;
}
	
	
sub query {
#=====================================================

=head2 B<query>

 my $records = $self->{dd}->query($table_name, undef, $query_hash);
 my $records = $self->{dd}->query($table_name, $index_name, $query_hash);

=cut
#=====================================================
	my $self = shift || return;
	my $table_name = shift || return;
	my $index_name = shift;
	my $data = shift || return;
	my $args = shift;
	my $debug = shift;
	if (!$debug && !is_hash($args) && $args) { $debug = TRUE; }
	
	my $expression = _convert_to_expression($data);
	my $key_condition_expression = join(' and ', @{$expression->{comparisons}});
	
	my $index = '';
	if ($index_name) { $index = " --index-name $index_name"; }
	my $scan_direction = '';
	my $max_items = ' --max-items 100';
	if (is_hash_with_content($args)) {
		if (exists($args->{scan_index_forward}) && !$args->{scan_index_forward}) {
			$scan_direction = ' --no-scan-index-forward'
		}
		if (exists($args->{limit}) && is_pos_int($args->{limit})) {
			$max_items = " --max-items $args->{limit}"
		}
	}
	my $dd_results = $self->_call_dynamodb("query --table-name $table_name$index$scan_direction$max_items --key-condition-expression '$key_condition_expression' --expression-attribute-names '$expression->{names_json}' --expression-attribute-values '$expression->{values_json}'", $debug);
	my $results = _convert_from_dynamodb($dd_results);
	$debug && $self->{io}->print_object($results, '$results');
	return $results->{Items};
}


sub scan {
#=====================================================

=head2 B<scan>

 my $record = $self->{dd}->scan($table_name);

=cut
#=====================================================
	my $self = shift || return;
	my $table_name = shift || return;
	my $debug = shift;
	
	my $dd_results = $self->_call_dynamodb("scan --table-name $table_name --max-items 100", $debug);
	my $results = _convert_from_dynamodb($dd_results);
	return $results->{Items};
}


sub get_item {
#=====================================================

=head2 B<get_item>

 my $record = $self->{dd}->get_item($table_name, $partition_key_value[, $sort_key_value]);

=cut
#=====================================================
	my $self = shift || return;
	my $table_name = shift || return;
	my $key = shift || return;
	my $key2 = shift;
	my $debug = shift;
	
	my $key_hash = {};
	my $keys = $self->get_table_keys($table_name);
	$key_hash->{$keys->[0]} = $key;
	if ($keys->[1]) { $key_hash->{$keys->[1]} = $key2; }
	my $key_json = _convert_to_key_json($key_hash);
	
	my $dd_results = $self->_call_dynamodb("get-item --table-name $table_name --key '$key_json'", $debug);
	my $results = _convert_from_dynamodb($dd_results);
	return $results->{Item};
}


sub put_item {
#=====================================================

=head2 B<put_item>

 $self->{dd}->put_item($table_name, $record_hash);

=cut
#=====================================================
	my $self = shift || return;
	my $table_name = shift || return;
	my $item = shift;
	my $debug = shift;
	
	my $dd_item = _convert_to_dynamodb($item);
	my $json = make_json($dd_item, { compress => TRUE, escape_for_bash => TRUE });
	if ($self->{dry_run}) {
		my $json = make_json($item, { compress => TRUE });
		$self->{io}->dry_run("DD put-item --table-name $table_name");
		$self->{io}->dry_run("     $json");
		return {};
	}
	my $dd_results = $self->_call_dynamodb("put-item --table-name $table_name --item '$json'", $debug);
# 	$debug && $self->{io}->print_object($dd_results, '$dd_results');
	return $dd_results;
}


sub update_item {
#=====================================================

=head2 B<update_item>

 $self->{dd}->update_item($table_name, $key_hash, $record_hash);

=cut
#=====================================================
	my $self = shift || return;
	my $table_name = shift || return;
	my $key_hash = shift;
	my $source = shift;
	my $debug = shift;
	
	my $item = copy_ref($source);
	foreach my $name (keys(%{$key_hash})) {
		delete $item->{$name};
	}
	
	my $key_json = _convert_to_key_json($key_hash);
	my $expressions = _convert_to_expression($item);
	my $update = "SET " . join(', ', @{$expressions->{comparisons}});
	if ($self->{dry_run}) {
		my $key_json = make_json($key_hash, { compress => TRUE });
		my $json = make_json($item, { compress => TRUE });
		$self->{io}->dry_run("DD update-item --table-name $table_name");
		$self->{io}->dry_run("     --key '$key_json'");
		$self->{io}->dry_run("     $json");
		return {};
	}
	my $results = $self->_call_dynamodb("update-item --table-name $table_name --key '$key_json' --update-expression '$update' --expression-attribute-names '$expressions->{names_json}' --expression-attribute-values '$expressions->{values_json}'", $debug);
	$debug && $self->{io}->print_object($results, '$results');
	return $results;
}


sub delete_item {
#=====================================================

=head2 B<delete_item>

 $self->{dd}->delete_item($table_name, $key_hash);

=cut
#=====================================================
	my $self = shift || return;
	my $table_name = shift || return;
	my $key_hash = shift;
	my $debug = shift;
	
	my $key_json = _convert_to_key_json($key_hash);
	if ($self->{dry_run}) {
		my $key_json = make_json($key_hash, { compress => TRUE });
		$self->{io}->dry_run("DD delete-item --table-name $table_name");
		$self->{io}->dry_run("     --key '$key_json'");
		return {};
	}
	my $results = $self->_call_dynamodb("delete-item --table-name $table_name --key '$key_json'", $debug);
	$debug && $self->{io}->print_object($results, '$results');
	return $results;
}


sub _convert_to_key_json {
#=====================================================

=head2 B<_convert_to_key_json>

 my $key_json = _convert_to_key_json($key_hash);

=cut
#=====================================================
	my $keys = shift || return;
	my $debug = shift;
	is_hash($keys) || return;
	
	my $key_hash = {};
	while (my($name, $value) = each(%{$keys})) {
		my $new_value = _convert_to_dynamodb($value, undef, 1) || next;
		$key_hash->{$name} = $new_value;
	}
	my $key_json = make_json($key_hash, { compress => TRUE });
	return $key_json;
}

sub _convert_to_expression {
#=====================================================

=head2 B<_convert_to_expression>

 my $expression = _convert_to_expression($data);

=cut
#=====================================================
	my $data = shift || return;
	is_hash($data) || return;
	
	my $container = {
		comparisons	=> [],
		names		=> {},
		values		=> {},
		name_count	=> 1,
		value_count	=> 1
	};
	_convert_to_expression_traverse($data, $container, []);
	my $expression = join(', ', @{$container->{comparisons}});
	my $names = make_json($container->{names}, { compress => TRUE });
	my $values = make_json($container->{values}, { compress => TRUE, include_nulls => TRUE });
	return {
		comparisons		=> $container->{comparisons},
		names_json		=> $names,
		values_json		=> $values
	};
}
sub _convert_to_expression_traverse {
	my $data = shift || return;
	my $container = shift || return;
	my $path = shift;
	my @path = @{$path};
	
	if (is_hash($data)) {
		while (my($name, $value) = each(%{$data})) {
			_convert_to_expression_item($container, $name, $value, [@path]);
		}
	} elsif (is_array($data)) {
		my $cnt = 0;
		foreach my $value (@{$data}) {
			my $name = "[$cnt]";
			_convert_to_expression_item($container, $name, $value, [@path]);
			$cnt++;
		}
	}
}
sub _convert_to_expression_item {
	my $container = shift || return;
	my $name = shift || return;
	my $value = shift || return;
	my $path = shift || return;
	my @path = @{$path};
	
	if (is_hash_with_content($value) || is_array_with_content($value)) {
		_convert_to_expression_traverse($value, $container, [@path, $name]);
	} elsif (defined($value)) {
		push(@path, $name);
		my $comparison_name;
		foreach my $item (@path) {
			if ($item =~ /^\[(\d+)\]$/) {
				$comparison_name .= $item;
			} else {
				if ($comparison_name) { $comparison_name .= '.'; }
				my $name_ref = "#N" . $container->{name_count}++;
				$comparison_name .= $name_ref;
				$container->{names}->{$name_ref} = $item;
			}
		}
		my $comp;
		if (is_text($value)) {
			($comp, $value) = $value =~ m#^(=|<=|<|>=|>|/)?(.*)$#;
		}
		$comp ||= '=';
		
		my $new_value = _convert_to_dynamodb($value, undef, 1);
		my $value_ref = ":v" . $container->{value_count}++;
		$container->{values}->{$value_ref} = $new_value;
		if ($comp eq '/') {
			push(@{$container->{comparisons}}, "begins_with($comparison_name, $value_ref)");
		} else {
			push(@{$container->{comparisons}}, $comparison_name . $comp . $value_ref);
		}
	}
}



sub _is_dynamodb_item {
#=====================================================

=head2 B<_is_dynamodb_item>

=cut
#=====================================================
	my $item = shift;
	if (!is_hash_with_content($item)) { return FALSE; }
	my @keys = keys(%{$item});
	if (scalar @keys != 1) { return FALSE; }
	if ($keys[0] =~ /^(S|N|B|SS|NS|BS|M|L|NULL|BOOL)$/) { return TRUE; }
}


sub _convert_to_dynamodb {
#=====================================================

=head2 B<_convert_to_dynamodb>

=cut
#=====================================================
	my $item = shift || return;
	my $type = shift;
	my $level = shift;
	if (is_hash($item)) {
		my $new_hash = {};
		while (my($name, $value) = each(%{$item})) {
			my $value_type;
			if ($name =~ /^#/) { $value_type = 'N'; $name =~ s/^#//; }
			my $new_value = _convert_to_dynamodb($value, $value_type, $level+1);
			$new_hash->{$name} = $new_value;
		}
		if ($level) { return { "M" => $new_hash }; }
		else { return $new_hash; }
	} elsif (is_array($item)) {
		my $new_array = [];
		foreach my $value (@{$item}) {
			my $new_value = _convert_to_dynamodb($value, undef, $level+1);
			push(@{$new_array}, $new_value);
		}
		if ($level) { return { "L" => $new_array }; }
		else { return $new_array; }
	} elsif (($type eq 'N') && is_number($item)) {
		return { "N" => $item };
	} elsif (JSON::is_bool($item)) {
		return { "BOOL" => $item };
	} else {
		return { "S" => $item };
	}
}

sub _convert_from_dynamodb {
#=====================================================

=head2 B<_convert_from_dynamodb>

=cut
#=====================================================
	my $item = shift || return;
	if (_is_dynamodb_item($item)) {
		my $key = (keys(%{$item}))[0];
		my $value = $item->{$key};
		if ($key eq 'S') {
			return $value . '';
		} elsif ($key eq 'N') {
			return $value + 0;
		} elsif (($key eq 'B') || ($key eq 'SS') || ($key eq 'NS') || ($key eq 'BS')) {
			return $value + 0;
		} elsif ($key eq 'M') {
			my $new_value = _convert_from_dynamodb($value);
			return $new_value;
		} elsif ($key eq 'L') {
			my $new_value = _convert_from_dynamodb($value);
			return $new_value;
		} elsif ($key eq 'NULL') {
			return undef;
		} elsif ($key eq 'BOOL') {
			if ($value) { return TRUE; }
			else { return FALSE; }
		}
		return;
	} elsif (is_hash($item)) {
		my $new_hash = {};
		while (my($name, $value) = each(%{$item})) {
			my $new_value = _convert_from_dynamodb($value);
			$new_hash->{$name} = $new_value;
		}
		return $new_hash;
	} elsif (is_array($item)) {
		my $new_array = [];
		foreach my $value (@{$item}) {
			my $new_value = _convert_from_dynamodb($value);
			push(@{$new_array}, $new_value);
		}
		return $new_array;
	}
	return $item;
}


sub _call_dynamodb {
#=====================================================

=head2 B<_call_dynamodb>

=cut
#=====================================================
	my $self = shift || return;
	my $args = shift || return;
	my $debug = shift;
	
	my $awscli = '/usr/bin/aws';
	if (!-e $awscli) {
		$awscli = '/usr/local/bin/aws';
		if (!-e $awscli) {
			$self->{io}->error("AWS CLI not found.");
		}
	}
	
	my $command = "$awscli dynamodb $args";
	if ($self->{pipe_to_cat}) { $command .= ' | cat'; }
	$debug && say $command;
	my $json = `$command`;
	is_json($json) || return;
	return parse_json($json);
}




=head1 CHANGES

  2017-11-16 TJM - v8.0 Started development

=head1 AUTHOR

  Tim Moses <tim@moses.com>
  Sitemason Open Source <https://github.com/sitemason>

=cut

1;
