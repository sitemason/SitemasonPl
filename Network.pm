package SitemasonPl::Network 1.0;

=head1 NAME

Network

=head1 DESCRIPTION

Contains functions for maintaining tunnels and testing network connections.

=cut

use v5.012;
use strict;
use warnings;
use utf8;
use open ':std', ':encoding(UTF-8)';
use constant TRUE => 1;
use constant FALSE => 0;

use lib qw( /opt/lib/site_perl );
use SitemasonPl::Common;
use SitemasonPl::IO qw(mark print_object trace);


sub new {
#=====================================================

=head2 B<new>

 use SitemasonPl::Network;
 my $network = SitemasonPl::Network->new;
 my $network = SitemasonPl::Network->new(
	ssh_timeout	=> 3,
	io			=> $self->{io},
	dry_run		=> $self->{dry_run},
	verbose		=> $self->{verbose}
 );

=cut
#=====================================================
	my ($class, %arg) = @_;
	$class || return;
	
	my $self = {
		ssh_timeout	=> $arg{ssh_timeout} || 3,
		io			=> $arg{io}
	};
	if (!$self->{io}) { $self->{io} = SitemasonPl::IO->new(dry_run => $self->{dry_run}, verbose => $self->{verbose}); }
	
	bless $self, $class;
	return $self;
}

sub read_tunnel_config {
	my $self = shift || return;
	my $config = shift || "$ENV{HOME}/.tunnel.cnf";
	unless (-e $config) { return []; }
	
	my $tunnels = [];
	my $cnt = 0;
	my @config_lines = read_file($config);
	foreach my $line (@config_lines) {
		$cnt++;
		chomp $line;
		if ($line =~ /^#/) { next; }
		if ($line !~ /^\S/) { next; }
		my $t = { connect_string => $line };
		($t->{local}, $t->{gateway}, $t->{remote}) = split(/ +/, $line);
		if ($self->check_tunnel($t)) {
			push(@{$tunnels}, $t);
		} else {
			$self->{io}->warning("Config $config, Line $cnt:");
			$self->{io}->warning("  $t->{connect_string}");
		}
	}
	return $tunnels;
}

sub read_pass_file {
	# my $creds = $self->{network}->read_pass_file($engine);
	my $self = shift || return;
	my $engine = shift || "mysql";
	
	my $pass_file = "$ENV{HOME}/.mypass";
	if ($engine eq 'postgres') { $pass_file = "$ENV{HOME}/.pgpass"; }
	unless (-e $pass_file) { return []; }
	
	my $creds = [];
	my $cnt = 0;
	my @pass_lines = read_file($pass_file);
	foreach my $line (@pass_lines) {
		$cnt++;
		chomp $line;
		if ($line =~ /^#/) { next; }
		if ($line !~ /^\S/) { next; }
		my $c = { engine => $engine };
		($c->{host}, $c->{port}, $c->{dbname}, $c->{username}, $c->{password}) = split(/:/, $line);
		$c->{host_ro} = $c->{host};
		push(@{$creds}, $c);
	}
	return $creds;
}

sub add_to_pass_file {
	# my $success = $self->{network}->add_to_pass_file($creds);
	my $self = shift || return;
	my $c = shift || return;
	
	my $pass_file = "$ENV{HOME}/.mypass";
	if ($c->{engine} eq 'postgres') { $pass_file = "$ENV{HOME}/.pgpass"; }
	my $string = "$c->{host}:$c->{port}:$c->{dbname}:$c->{username}:$c->{password}\n";
	open(PASS, ">>$pass_file");
	print PASS $string;
	close(PASS);
	return TRUE;
}

sub check_tunnel {
	my $self = shift || return;
	my $tunnel = shift || return;
	my $success = TRUE;
	
	if (!$tunnel->{local}) {
		$self->{io}->error("Local login is required.");
		$success = FALSE;
	}
	($tunnel->{local_login}, $tunnel->{local_port}) = $tunnel->{local} =~ /^((?:[\w-]+\@)?[\w.-]+):(\d+)$/;
	if (!$tunnel->{local_login} || !$tunnel->{local_port}) {
		$self->{io}->error("Invalid local login: $tunnel->{local}");
		$success = FALSE;
	} elsif ($tunnel->{local_port} < 1024) {
		$self->{io}->error("Local port must be greater than 1023.");
		$success = FALSE;
	}
	
	if (!$tunnel->{gateway}) {
		$self->{io}->error("Gateway login is required.");
		$success = FALSE;
	}
	($tunnel->{gateway_login}, $tunnel->{gateway_port}) = $tunnel->{gateway} =~ /^((?:[\w-]+\@)?[\w.-]+)(?::(\d+))?$/;
	if (!$tunnel->{gateway_login}) {
		$self->{io}->error("Invalid gateway login: $tunnel->{gateway}");
		$success = FALSE;
	}
	
	if (!$tunnel->{remote}) {
		$self->{io}->error("Remote login is required.");
		$success = FALSE;
	}
	if (!$tunnel->{remote}) {
		$self->{io}->error("Invalid remote login: $tunnel->{remote}");
		$success = FALSE;
	}
	$tunnel->{remote_login} = $tunnel->{remote};
	($tunnel->{remote_host}, $tunnel->{remote_port}) = split(':', $tunnel->{remote_login});
	
	return $success;
}

sub test_connection {
	my $self = shift || return;
	
}

sub create_tunnel {
	my $self = shift || return;
	my $tunnel = shift || return;
	
	my $local_login = $tunnel->{local_login} || return;
	my $local_port = $tunnel->{local_port} || return;
	my $gateway_login = $tunnel->{gateway_login} || return;
	my $gateway_port = $tunnel->{gateway_port};
	my $remote_login = $tunnel->{remote_login} || return;
	
	my $ps_cmd = "ps -ef | grep 'ssh -fN' | grep -E '\\-L $local_port:$remote_login' | grep -v grep";
	my @ps = `$ps_cmd`;
	chomp(@ps);

	my $is_connected;
	foreach my $ps (@ps) {
		my ($pid) = $ps =~ /^\s*\d+\s+(\d+)/;
		# Test SSH connection
		if ($remote_login =~ /:22$/) {
			# Test if given a test login
			if ($tunnel->{local_login}) {
				my $cmd = "ssh -p $local_port -o ConnectTimeout=$self->{ssh_timeout} $tunnel->{local_login} \"hostname\"";
				$self->{io}->verbose($cmd);
				my $test = `$cmd`;
				if ($test =~ /\w+\.\w+/) {
					$self->{io}->body("Remote server already connected on port $tunnel->{local_port}");
					$is_connected = TRUE;
					next;
				}
			}
			# Reset connection
			if ($pid) {
				$self->{io}->body("Existing connection failed on port $tunnel->{local_port}. Killing $pid");
				$self->kill_pid($pid);
			}
		# Test Pg connection
		} elsif (($remote_login =~ /:5432$/) && ($tunnel->{local_login} =~ /^([\w-]+)\@([\w.-]+)$/)) {
			$tunnel->{db_user} = $1;
			$tunnel->{db_name} = $2;
			my $cmd = "psql -p $local_port -h localhost -U $tunnel->{db_user} $tunnel->{db_name} -c \"SELECT 'tunnel';\"";
			$self->{io}->verbose($cmd);
			my $test = `$cmd`;
			if ($test =~ /tunnel/) {
				$self->{io}->body("Remote server already connected on port $tunnel->{local_port}");
				$is_connected = TRUE;
				next;
			}
			# Reset connection
			if ($pid) {
				$self->{io}->body("Existing connection failed on port $tunnel->{local_port}. Killing $pid");
				$self->kill_pid($pid);
			}
		# Test MySQL connection
		} elsif (($remote_login =~ /:3306$/) && $tunnel->{local_login}) {
			($tunnel->{db_user}, $tunnel->{db_name}) = $tunnel->{local_login} =~ /^([\w-]+)(?:\@([\w.-]+))?$/;
			$tunnel->{db_name} ||= 'mysql';
			my $cmd = "echo \"SELECT 'tunnel';\" | mysql -P $local_port -h 127.0.0.1 --ssl-mode=disabled -u $tunnel->{db_user} $tunnel->{db_name}";
			$self->{io}->verbose($cmd);
			my $test = `$cmd`;
			if ($test =~ /tunnel/) {
				$self->{io}->body("Remote server already connected on port $tunnel->{local_port}");
				$is_connected = TRUE;
				next;
			}
			# Reset connection
			if ($pid) {
				$self->{io}->body("Existing connection failed on port $tunnel->{local_port}. Killing $pid");
				$self->kill_pid($pid);
			}
		# Assume the connection is ok since we can't test for it.
		} elsif ($pid) {
			$self->{io}->body("Remote server already connected on port $tunnel->{local_port}");
			$is_connected = TRUE;
		}
	}
	
	unless ($is_connected) {
		$self->{io}->body("Creating new tunnel on port $tunnel->{local_port}");
		my $port = '';
		if ($gateway_port) { $port = ' -p ' . $gateway_port; }
		$self->run_command("ssh -fN$port -L $local_port:$remote_login $gateway_login");
	}
	
	return TRUE;
}

sub run_command {
	my $self = shift || return;
	my $cmd = shift || return;
	
	if ($self->{io}->run($cmd)) {
		system($cmd);
	}
}

sub kill_pid {
	my $self = shift || return;
	my $pid = shift || return;
	
	if ($self->{io}->run("kill 9, $pid")) {
		kill 9, $pid;
	}
}




=head1 CHANGES

  20220623 TJM - v1.0 Moved functions from the tunnel scripts.

=head1 AUTHOR

  Tim Moses <tim@moses.com>
  Sitemason Open Source <https://github.com/sitemason>

=cut

1;
