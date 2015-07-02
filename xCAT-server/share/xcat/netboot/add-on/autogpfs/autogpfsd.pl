#!/usr/bin/perl

use strict;
use IO::Socket;
use IO::File;
use POSIX qw(WNOHANG setsid);
use Sys::Syslog qw(:DEFAULT setlogsock);

use constant PIDFILE => '/var/lock/autogpfsd/autogpfsd.pid';
system("mkdir -p /var/lock/autogpfsd");

my $quit = 0;
my $node;
my $domain;
my $port;
my $max;
my $mode;
my $cc=0;
my $pid=$$;
my %kids;

open(CONFIG,"/etc/sysconfig/autogpfsd") || \
	die "cannot open /etc/sysconfig/autogpfsd\n";

while(<CONFIG>) {
	if(/^domain\b/) {
		$_ =~ m/^domain\s+(.*)/;
		$domain = $1;
	}
	if(/^autogpfsdport\b/) {
		$_ =~ m/^autogpfsdport\s+(.*)/;
		$port = $1;
	}
	if(/^autogpfsdmax\b/) {
		$_ =~ m/^autogpfsdmax\s+(.*)/;
		$max = $1;
	}
	if(/^autogpfsdmode\b/) {
		$_ =~ m/^autogpfsdmode\s+(.*)/;
		$mode = $1;
	}
}

close(CONFIG);

if($domain eq "") {
	logger('err',"domain not defined in /etc/sysconfig/autogpfsd");
	die "domain not defined in /etc/sysconfig/autogpfsd";
}

if($port eq "") {
	logger('err',"autogpfsdport not defined in /etc/sysconfig/autogpfsd");
	die "autogpfsdport not defined in /etc/sysconfig/autogpfsd";
}

if($max eq "") {
	logger('err',"autogpfsdmax not defined in /etc/sysconfig/autogpfsd");
	die "autogpfsdmax not defined in /etc/sysconfig/autogpfsd";
}

if($mode eq "") {
	logger('err',"autogpfsdmode not defined in /etc/sysconfig/autogpfsd");
	die "autogpfsdmode not defined in /etc/sysconfig/autogpfsd";
}

#$SIG{USR1} = sub {$cc--;};
$SIG{CHLD} = sub { while ( waitpid(-1,WNOHANG)>0 ) { } };
$SIG{TERM} = $SIG{INT} = sub { $quit++ };

my $fh = lockfile(PIDFILE);
my $listen_socket =
IO::Socket::INET->new(
	LocalPort => $port,
	Listen    => 20,
	Proto     => 'tcp',
	Reuse     => 1,
	Timeout   => 60*60,
);
die "Cannot create a listening socket: $@" unless $listen_socket;

my $pid = daemonic();
print $fh $pid;
close $fh;

logger('info',"waiting for connection");

while (!$quit) {
	next unless my $connection = $listen_socket->accept;

	my $child = fork();

	if(!defined $child) {
		logger('err',"cannot fork, exiting");
		die "cannot fork";
	}

	if ($child == 0) {
		$listen_socket->close;
		$node = gethostbyaddr(inet_aton($connection->peerhost),AF_INET);
		$node =~ s/\.$domain$//;
		$node =~ s/-eth\d$//;
		$node =~ s/-myri\d$//;
		logger('info',"connection from: $node");
		interact($connection,$node,inet_ntoa($connection->peeraddr));
		#kill(10,$pid);
		exit 0;
	}

	$connection->close;

	my $gotmax = 0;
	do {
		$cc=0;
		$kids{$child} = 1;
		my $key;
		foreach $key (keys(%kids)) {
			if(getpgrp($key) != -1) {
				$cc++;
			}
			else {
				delete $kids{$key};
			}
  		}
		if($cc >= $max) {
			$gotmax++;
			sleep(1);
		}
		if($gotmax == 1) {
			$gotmax++;
			logger('info',"connection count ($cc) max ($max) reached");
		}
	} while ($cc >= $max);

	if($gotmax > 0) {
		logger('info',"connection count ($cc) dropped below max ($max)");
	}
}

logger('info',"exiting clean");

sub interact {
	my $sock = shift;
	my $node = shift;
	my $addr = shift;

	STDIN->fdopen($sock,"<")  or die "Can't reopen STDIN: $!";
	STDOUT->fdopen($sock,">") or die "Can't reopen STDOUT: $!";
	STDERR->fdopen($sock,">") or die "Can't reopen STDERR: $!";
	$| = 1;

#	if($cc > $max) {
#		logger('info',"rejected connection from: $node ($cc) autogpfsdmax exceeded");
#		print "busy\n";
#		return;
#	}

	if($node eq "") {
		print "gethostbyaddr failed, who are you $addr?\n";
		logger('info',"gethostbyaddr failed for $addr");
		last;
	}

	while(<>) {
		my $line = $_;

		if(!hostcheck($node)) {
			print "unauthorized request\n";
			logger('info',"unauthorized request from $node");
			last;
		}

		if(!open(OUTPUT,"/usr/lpp/mmfs/bin/mmlscluster 2>&1 |")) {
			print "mmlscluster failed\n";
			logger('info',"mmlscluster failed");
			last;
		}

		my $inlist = 0;
		my $status = "new";
		while(<OUTPUT>) {
			my $line = $_;

			if($line =~ /Node number/ || $line =~ /Daemon node name/) {
				$line = <OUTPUT>;
				$inlist = 1;
				next;
			}

			if($line =~ /------------------------------------------------/) {
				$inlist = 1;
				next;
			}

			if($inlist == 0) {
				next;
			}

			s/^\s+//;
			if($_ eq "") {
				next;
			}
			my @a = split(/[\.\s]+/);
			my $lnode = $a[1];

			if($lnode eq $node) {
				$status = "old";
				last;
			}
		}
		while(<OUTPUT>) {
			# let mmlscluster finish up
		}
		close(OUTPUT);

		logger('info',"$node detected as $status");

		if($status eq "new") {
			if($mode ne $status) {
				print "$status run mmaddnode $node manually\n";
				logger('info',"run mmaddnode $node manually");
				last;
			}
			my $ok = 0;
			print "$status started\n";
			if(!open(OUTPUT,"/usr/lpp/mmfs/bin/mmaddnode $node 2>&1 |")) {
				print "$status mmaddnode failed\n";
				logger('info',"mmaddnode $node failed");
				last;
			}
			while(<OUTPUT>) {
				if(/Command successfully completed/) {
					$ok = 1;
				}
				logger('info',"mmaddnode $node output: $_");
			}
			close(OUTPUT);
			if($ok == 0) {
				print "$status mmaddnode failed\n";
			}
			else {
				print "$status ended\n";
			}
		}

		if($status eq "old") {
			if($mode ne $status) {
				print "$status suspending autogpfs while adding nodes\n";
				logger('info',"suspending autogpfs while adding nodes");
				last;
			}
			my $ok = 0;
			print "$status started\n";

			if(!open(OUTPUT,"/etc/fstab")) {
				print "$status failed\n";
				logger('info',"cannot read /etc/fstab");
				last;
			}
			while(<OUTPUT>) {
				chomp();
				s/^\s+//g;
				if(/^#/) {
					next;
				}
				my @a = split(/\s+/);
				my $fstype = $a[2];
				if($fstype ne "gpfs") {
					next;
				}
				print "$status gpfs $_\n";

				s/.*dev=([^,]+).*/\1/;
				my $devgpfs = "/dev/$_";
				my $mm = `ls -l $devgpfs | head -1`;
				$mm =~ s/,//g;
				@a = split(/\s+/,$mm);
				my $major = $a[4];
				my $minor = $a[5];

				print "$status dev $devgpfs $major $minor\n";
			}
			close(OUTPUT);

			print "$status mmsdrfs start\n";
			if(!open(OUTPUT,"/var/mmfs/gen/mmsdrfs")) {
				print "$status failed\n";
				logger('info',"cannot read /var/mmfs/gen/mmsdrfs");
				last;
			}
			while(<OUTPUT>) {
				print $_;
			}
			close(OUTPUT);
			print "EOF\n";

			$ok = 1;
			
			if($ok == 0) {
				print "$status failed\n";
			}
			else {
				print "$status ended\n";
			}
		}

		last;

	}

	logger('info',"connection from: $node ended");
}

sub daemonic {
	my $child = fork();

	if(!defined $child) {
		die "Can't fork";
	}
	if($child) {
		exit 0;
	}
	setsid();
	open(STDIN, "</dev/null");
	open(STDOUT,">/dev/null");
	open(STDERR,">&STDOUT");
	chdir('/');
	umask(0);
	#$ENV{PATH} = "$ENV{XCATROOT}/bin:$ENV{XCATROOT}/sbin:$ENV{XCATROOT}/lib:$ENV{PATH}";
	return $$;
}

sub lockfile {
	my $file = shift;
	my $fh;

	if(-e $file) {
		if(!($fh = IO::File->new($file))) {
			return($fh);
		}
		my $pid = <$fh>;
		if(kill 0 => $pid) {
			die "Server already running with PID $pid";
		}
		warn "Removing PID file for defunct server process $pid.\n";
		unless(-w $file && unlink $file) {
			die "Can't unlink PID file $file"
		}
	}
	if($fh = IO::File->new($file,O_WRONLY|O_CREAT|O_EXCL,0644)) {
		return($fh);
	}
	else {
		die "Can't create $file: $!\n";
	}
}

sub hostcheck {
	my $node = shift;
	my $nodename;
	my $attributes;

	#TBD, check DNS or xCAT for valid

	return(1);
}

sub logger {
	my $type = shift;
	my $msg = shift;

	setlogsock('unix');
	openlog('xcat','','local0');
	syslog($type,$msg);
	closelog();

	#no syslog hack
	system("(date;echo : $type $msg) >>/tmp/autogpfsd.log");
}

END { unlink PIDFILE if $$ == $pid; }

