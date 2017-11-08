package Sitemason::Scripts::Scripts;

use strict;
use utf8;
use constant TRUE => 1;
use constant FALSE => 0;

use Getopt::Long;
use Pod::Usage qw(pod2usage);
use Proc::ProcessTable;

use Sitemason::Common;
use Sitemason::Debug;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(initialize isAlreadyRunning isAlreadyRunningWithArgs getOptions printUsage);


#=====================================================

=head2 B<initialize>

Sets the following:
 debug - Sitemason::Debug
 logAction - Sitemason::Debug::LogAction
 prefs - Sitemason::Debug::ScriptPreferences
 
 mode - the first argument prior to options
 scriptName - name of the script as it was originally called
 options - the command line dash options; @ARGV holds the remaining arguments

 initialize($self, {
 	blockSize                => 1000,     # Number of records to process per batch
 	maxRecords               => 1000000,  # Maximum number of records to process
 	pause                    => 0,        # Number of seconds to pause between batches
 	logAction                => TRUE,     # Log actions to action table and dashboard
 	preventMultipleProcesses => TRUE,     # Prevent this script from running if already running with matching arguments
 });

=cut
#=====================================================
sub initialize {
	my $self = shift || return;
	my $arg = shift;
	
	$self->{blockSize}		= $arg->{blockSize} || 5;
	$self->{maxRecords}		= $arg->{maxRecords} || 5;
	$self->{pause}			= $arg->{pause} || 0;
	$self->{options}		= {};
	($self->{scriptName})	= $0 =~ /\/([^\/]+?)$/;
	
	$self->{debug} = Sitemason::Debug->new(
		logLevel	=> 'debug',
		logLevelAll	=> 'info',
		logTags		=> ['!call']
	);
	
	if ($arg->{preventMultipleProcesses}) {
		if (isAlreadyRunningWithArgs(@ARGV)) { $self->{debug}->warning("Already running", { header => 0 }); exit; }
	}
	
	if (isArrayWithContent($arg->{options})) {
		$self->{options} = getOptions(@{$arg->{options}});
	}
	
	if (@ARGV[0] && (@ARGV[0] !~ /^\-/)) { $self->{mode} = shift(@ARGV); }
	
	if ($arg->{logAction}) {
		$self->{logAction} = Sitemason::Debug::LogAction->new(debug => $self->{debug}, source => $self->{scriptName}, source_arg => $self->{mode});
	}
	
	$self->{prefs} = Sitemason::Debug::ScriptPreferences->new(debug => $self->{debug}) || return;
	
	return TRUE;
}


#=====================================================

=head2 B<isAlreadyRunning>

 if (isAlreadyRunning) { die "Already running"; }
 if (isAlreadyRunning) { $self->{debug}->{isPerson} && $self->{debug}->warning("Already running"); exit; }

=cut
#=====================================================
sub isAlreadyRunning {
	my $limit = shift || 1;
	
	my ($script) = $0 =~ /\/([^\/]+?)$/;
	my $pid = $$;
	my $ps = new Proc::ProcessTable( 'cache_ttys' => 1 );
	my $processTable = $ps->table;
	my $cnt;
	foreach my $process (@{$processTable}) {
		my $fname = $process->fname;
		my $line = $process->cmndline;
		if (($script =~ /^($fname|perl)/) && ($line =~ /perl .*\Q$script\E(\s|$)/) && ($process->pid != $pid)) { $cnt++; }
	}
	if ($cnt > ($limit - 1)) { return TRUE; }
}


#=====================================================

=head2 B<isAlreadyRunningWithArgs>

 if (isAlreadyRunningWithArgs(@ARGV)) { die "Already running"; }

=cut
#=====================================================
sub isAlreadyRunningWithArgs {
	my $limit = 1;
	
	my ($script) = $0 =~ /\/([^\/]+?)$/;
	my $cmdline = $script;
	if (isArrayWithContent($_[0])) { $cmdline .= " " . join(' ', @{$_[0]}); }
	elsif ($_[0]) { $cmdline .= " " . join(' ', @_); }
	
	my $pid = $$;
	my $ps = new Proc::ProcessTable( 'cache_ttys' => 1 );
	my $processTable = $ps->table;
	my $cnt;
	foreach my $process (@{$processTable}) {
		my $fname = $process->fname;
		my $line = $process->cmndline;
		if (($script =~ /^($fname|perl)/) && ($line =~ /perl .*\Q$cmdline\E$/) && ($process->pid != $pid)) {
			$cnt++;
		}
	}
	if ($cnt > ($limit - 1)) { return TRUE; }
}


#=====================================================

=head2 B<getOptions>

=cut
#=====================================================
sub getOptions {
	my @params = ();
	my $options = {};
	foreach my $arg (@_) {
		$arg || next;
		my $name = $arg;
		$name =~ s/\W.*$//;
		if ($arg =~ /\%$/) {
			$options->{$name} = {};
			push(@params, $arg, $options->{$name});
		} elsif ($arg =~ /\@$/) {
			$options->{$name} = [];
			push(@params, $arg, $options->{$name});
		} else {
			push(@params, $arg, \$options->{$name});
		}
	}
	GetOptions(@params);
	if ($options->{help}) {
		printUsage();
		exit;
	}
	if ($options->{version}) {
		pod2usage({ -indent => 4, -width => 140, -verbose => 99, -sections => ['VERSION'] });
		exit;
	}
	return $options;
}


#=====================================================

=head2 B<printUsage>

=cut
#=====================================================
sub printUsage {
	pod2usage({ -indent => 4, -width => 140, -verbose => 99, -sections => ['USAGE'] });
	return TRUE;
}




1;

