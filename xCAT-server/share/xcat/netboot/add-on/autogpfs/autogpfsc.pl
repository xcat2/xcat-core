#!/usr/bin/perl

use strict;
use IO::Socket;
use IO::File;
use Sys::Syslog qw(:DEFAULT setlogsock);

my $autogpfsdhost = shift;
my $autogpfsdport = shift;
my $line;

my $sock = IO::Socket::INET->new(
	PeerAddr => $autogpfsdhost,
	PeerPort => $autogpfsdport,
);

if(!defined($sock)) {
	logger('info',"could not open socket");
	exit(2);
}

#print "Starting autoGPFS...\n";

print $sock "hello\n";

while(<$sock>) {
	chomp();
	$line = $_;

	if($line =~ /^busy/) {
		exit(3);
	}
	if($line =~ /^new started/) {
		next;
	}
	if($line =~ /^new ended/) {
		system("/usr/lpp/mmfs/bin/mmstartup");
		$line = "";
		last;
	}
	if($line =~ /^new .*/) {
		s/^new //;
		$line = $_;
		last;
	}
	if($line =~ /^old started/) {
		next;
	}
	if($line =~ /^old ended/) {
		system("/usr/lpp/mmfs/bin/mmstartup");
		$line = "";
		last;
	}
	if($line =~ /^old gpfs /) {
		my $gotit = 0;

		s/^old gpfs //;
		$line = $_;

		open(FSTAB,"/etc/fstab");
		while(<FSTAB>) {
			chomp();
			if($_ eq $line) {
				$gotit = 1;
				last;
			}
		}
		close(FSTAB);

		if($gotit == 1) {
			next;
		}

		open(FSTAB,">>/etc/fstab");
		print FSTAB "$line\n";
		close(FSTAB);

		next;
	}
	if($line =~ /^old dev /) {
		my @a = split(/\s+/);
		my $dev = $a[2];
		my $major = $a[3];
		my $minor = $a[4];

		unlink($dev);
		system("mknod $dev b $major $minor");
		system("chmod 644 $dev");

		next;
	}
	if($line =~ /^old mmsdrfs start/) {
		unlink("/var/mmfs/gen/mmsdrfs");
		system("mkdir -p /var/mmfs/gen");
		open(OUTPUT,">/var/mmfs/gen/mmsdrfs");
		while(<$sock>) {
			if($_ =~ /^EOF/) {
				last;
			}
			print OUTPUT $_;
		}
		close(OUTPUT);
		next;
	}
	if($line =~ /^old .*/) {
		s/^old //;
		$line = $_;
		last;
	}
}

if($line ne "") {
	logger('err',$line);
	print "$line\n";
	exit(1);
}

#print "autoGPFS complete.\n";

exit(0);

sub logger {
	my $type = shift;
	my $msg = shift;

	setlogsock('unix');
	openlog('xcat','','local0');
	syslog($type,$msg);
	closelog();
}

