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

use SitemasonPl::Common;
use SitemasonPl::CLI qw(mark print_object);


sub new {
#=====================================================

=head2 B<new>

 my $db = SitemasonPl::Database::DynamoDB->new;

=cut
#=====================================================
	my ($class, %arg) = @_;
	$class || return;
	
	my $self = {
		db_type		=> 'DynamoDB',
		cli			=> $arg{cli}
	};
	if (!$self->{cli}) { $self->{cli} = SitemasonPl::CLI->new; }
	
	bless $self, $class;
	return $self;
}


sub describe_table {
#=====================================================

=head2 B<describe_table>

=cut
#=====================================================
	my $self = shift || return;
	my $table = shift || return;
	my $debug = shift;
	
	my $dd_table = $self->_call_dynamodb("describe-table --table-name $table", $debug);
	return $dd_table->{Table};
}


sub get_table_key {
#=====================================================

=head2 B<get_table_key>

=cut
#=====================================================
	my $self = shift || return;
	my $table = shift || return;
	my $attr = $self->describe_table($table);
	return $attr->{KeySchema}->[0]->{AttributeName};
}


sub get_item {
#=====================================================

=head2 B<get_item>

 my $record = $self->{dd}->get_item($table_name, $key_name, $key_value);

=cut
#=====================================================
	my $self = shift || return;
	my $table = shift || return;
	my $key_name = shift;
	my $key = shift;
	my $debug = shift;
	
	if (!$key_name) { $key_name = $self->get_table_key($table); }
	my $dd_results = $self->_call_dynamodb("get-item --table-name $table --key '{\"$key_name\":{\"S\":\"$key\"}}'", $debug);
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
	my $table = shift || return;
	my $item = shift;
	my $debug = shift;
	
	my $dd_item = _convert_to_dynamodb($item);
	$self->{cli}->print_object($dd_item, '$dd_item');
	my $json = make_json($dd_item, { compress => TRUE });
	$self->{cli}->print_object($json);
	my $dd_results = $self->_call_dynamodb("put-item --table-name $table --item '$json'", $debug);
	return $dd_results;
}


sub update_item {
#=====================================================

=head2 B<update_item>

 $self->{dd}->update_item($table_name, $key_name, $key_value, $record_hash);

=cut
#=====================================================
	my $self = shift || return;
	my $table = shift || return;
	my $key_name = shift;
	my $key = shift;
	my $item = shift;
	my $debug = shift;
	
	my ($update, $names, $values) = $self->_convert_for_update($item, $debug);
	$self->_call_dynamodb("update-item --table-name $table --key '{\"$key_name\":{\"S\":\"$key\"}}' --update-expression '$update' --expression-attribute-names '$names' --expression-attribute-values '$values'", $debug);
}


sub _convert_for_update {
#=====================================================

=head2 B<_convert_for_update>

=cut
#=====================================================
	my $self = shift || return;
	my $data = shift || return;
	is_hash($data) || return;
	
	my $container = {
		update		=> [],
		names		=> {},
		values		=> {},
		name_count	=> 1,
		value_count	=> 1
	};
	_convert_for_update_traverse($data, $container, []);
	my $update = "SET " . join(', ', @{$container->{update}});
	my $names = make_json($container->{names}, { compress => TRUE });
	my $values = make_json($container->{values}, { compress => TRUE });
	return ($update, $names, $values);
}
sub _convert_for_update_traverse {
	my $data = shift || return;
	my $container = shift || return;
	my $path = shift;
	
	if (is_hash($data)) {
		while (my($name, $value) = each(%{$data})) {
			_convert_for_update_item($container, $name, $value, $path);
		}
	} elsif (is_array($data)) {
		my $cnt = 0;
		foreach my $value (@{$data}) {
			my $name = "[$cnt]";
			_convert_for_update_item($container, $name, $value, $path);
			$cnt++;
		}
	}
}
sub _convert_for_update_item {
	my $container = shift || return;
	my $name = shift || return;
	my $value = shift || return;
	my $path = shift || return;
	
	if (is_hash($value) || is_array($value)) {
		_convert_for_update_traverse($value, $container, [@{$path}, $name]);
	} elsif (is_text($value)) {
		push(@{$path}, $name);
		my $update_name;
		foreach my $item (@{$path}) {
			if ($item =~ /^\[(\d+)\]$/) {
				$update_name .= $item;
			} else {
				if ($update_name) { $update_name .= '.'; }
				my $name_ref = "#N" . $container->{name_count}++;
				$update_name .= $name_ref;
				$container->{names}->{$name_ref} = $item;
			}
		}
		my $new_value = _convert_to_dynamodb($value, 1);
		my $value_ref = ":v" . $container->{value_count}++;
		$container->{values}->{$value_ref} = $new_value;
		push(@{$container->{update}}, $update_name . ' = ' . $value_ref);
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
	my $level = shift;
	if (is_hash($item)) {
		my $new_hash = {};
		while (my($name, $value) = each(%{$item})) {
			my $new_value = _convert_to_dynamodb($value, $level+1);
			$new_hash->{$name} = $new_value;
		}
		if ($level) { return { "M" => $new_hash }; }
		else { return $new_hash; }
	} elsif (is_array($item)) {
		my $new_array = [];
		foreach my $value (@{$item}) {
			my $new_value = _convert_to_dynamodb($value, $level+1);
			push(@{$new_array}, $new_value);
		}
		if ($level) { return { "L" => $new_array }; }
		else { return $new_array; }
	} elsif (is_number($item)) {
		return { "N" => $item };
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
			if ($value eq 'true') { return TRUE; }
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
	
	my $command = "/usr/bin/aws dynamodb $args";
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
