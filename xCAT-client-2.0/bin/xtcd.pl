#!/usr/bin/perl

#use strict;
use IO::Socket;
use File::Path;
use POSIX qw(:signal_h WNOHANG);
use Sys::Syslog qw(:DEFAULT setlogsock);

my $sock_dir = "/tmp/.xtcd";
mkpath($sock_dir);
my $display = shift;
my $node = shift;
my $title = shift;
my $quit = 0;

my $sock_path = "$sock_dir/$display.$node";

$SIG{CHLD} = sub { while ( waitpid(-1,WNOHANG) > 0 ) { } };
$SIG{HUP} = $SIG{TERM} = $SIG{INT} = sub { $quit++ };

unlink($sock_path);
umask(0111);

my $listen;

$listen = IO::Socket::UNIX->new(
	Local => $sock_path,
	Listen => SOMAXCONN
);
unless($listen) {
	print("xtcd: $display.$node cannot create a listening socket: $@");
	die "cannot create a listening socket $sock_path: $@";
}

while(!$quit) {
	my $connected = $listen->accept();
	my $child = launch_child();

	if(!defined $child) {
		print("xtcd: $display.$node cannot fork, exiting");
		die "cannot fork";
	} 

	if($child) {
		close $connected;
	}
	else {
		close $listen;
		interact($connected);
		exit 0;
	}
}

unlink($sock_path);
exit(0);

sub launch_child {
	my $signals = POSIX::SigSet->new(SIGINT,SIGCHLD,SIGTERM,SIGHUP);
	sigprocmask(SIG_BLOCK,$signals);
	my $child = fork();
	unless($child) {
		$SIG{$_} = 'DEFAULT' foreach qw(HUP INT TERM CHLD);
	}
	sigprocmask(SIG_UNBLOCK,$signals);
	return $child;
}

sub interact {
	my $c = shift;
	my $command;

	my $commandstring = <$c>;
	chomp($commandstring);

	foreach(split(/ /,$commandstring)) {
		$command = $_;

		if($command eq "ping") {
#			print $c "ok ping\n";
		}
		elsif($command =~ /move=/) {
			$command =~ s/move=//;
			my ($x,$y) = split(/x/,$command);
			print "\033[3;${x};${y}t";
#			print $c "ok move\n";
		}
		elsif($command =~ /font=/) {
			$command =~ s/font=//;
			print "\033]50;${command}\007";
#			print $c "ok font\n";
		}
		elsif($command eq "raise") {
			print "\033[5t";
#			print $c "ok raise\n";
		}
		elsif($command eq "lower") {
			print "\033[6t";
#			print $c "ok lower\n";
		}
		elsif($command eq "refresh") {
			print "\033[7t";
#			print $c "ok refresh\n";
		}
		elsif($command eq "iconify") {
			print "\033[2t";
#			print $c "ok iconify\n";
		}
		elsif($command eq "restore") {
			print "\033[1t";
#			print $c "ok restore\n";
		}
		elsif($command eq "title") {
			print "\033]2;${title}\007";
#			print $c "ok title\n";
		}
		elsif($command =~ /title=/) {
			$command =~ s/title=//;
			print "\033]2;${command}\007";
#			print $c "ok title\n";
		}
	}

	close $c;
}
