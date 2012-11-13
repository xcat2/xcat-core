package xCAT::SSHInteract;
use Exporter;
use Net::Telnet;
BEGIN {
	our @ISA = qw/Exporter Net::Telnet/;
};
use strict;
our @EXPORT_OK = ();
use IO::Pty;
use POSIX;

sub _startssh {
	my $self = shift;
	my $pty = shift;
	my $name = shift;
	my $dest = shift;
	my %args=@_;
	my $tty;
	my $tty_fd;
	my $pid = fork();
	if ($pid) {
		return;
	}
	#in child
	$tty = $pty->slave or die "$!";
	$pty->make_slave_controlling_terminal();
	$tty_fd = $tty->fileno or die "$!";
	close($pty);
	open STDIN, "<&", $tty_fd;
	open STDOUT,">&",$tty_fd;
        open STDERR, ">&", STDOUT;
	close($tty);
	my @cmd =  ("ssh","-o","StrictHostKeyChecking=no");
	if ($args{"-nokeycheck"}) {
		push @cmd,("-o","UserKnownHostsFile=/dev/null");
	}
	push @cmd,("-l",$name,$dest);
	exec @cmd;
}

sub new {
    my $class = shift;
    my %args = @_;
    my $pty = IO::Pty->new or die "Unable to perform ssh: $!";
    $args{"-fhopen"} = $pty;
    $args{"-telnetmode"} = 0;
    $args{"-telnetmode"} = 0;
    $args{"-cmd_remove_mode"} = 1;
    my $username = $args{"-username"};
    my $host = $args{"-host"};
    my $password = $args{"-password"};
    delete $args{"-host"};
    delete $args{"-username"};
    delete $args{"-password"};
    my $nokeycheck = $args{"-nokeycheck"};
    delete $args{"-nokeycheck"};
    my $self = $class->Net::Telnet::new(%args);
    _startssh($self,$pty,$username,$host,"-nokeycheck"=>$nokeycheck);
    my $promptex = $args{Prompt};
    $promptex =~ s!^/!!;
    $promptex =~ s!/\z!!;
    my ($prematch,$match) = $self->waitfor(Match => $args{Prompt},Match=>'/password:/i',Match=>'/REMOTE HOST IDENTIFICATION HAS CHANGED/') or die "Login Failed:", $self->lastline;
    #print "prematch=$prematch, match=$match\n";
    if ($match =~ /password:/i) {
	#$self->waitfor("-match" => '/password:/i', -errmode => "return") or die "Unable to reach host ",$self->lastline;
	$self->print($password);
	my $nextline = $self->getline();
	chomp($nextline);
	while ($nextline =~ /^\s*$/) {
	    $nextline = $self->get();
	    chomp($nextline);
	}
	if ($nextline =~ /password:/i or $nextline =~ /Permission denied, please try again/ or $nextline =~ /disconnect from/) {
	    die "Incorrect Password";
	} elsif ($nextline =~ /$promptex/) {
	    *$self->{_xcatsshinteract}->{_atprompt}=1;
	}
    } elsif ($match =~ /$promptex/) {
	*$self->{_xcatsshinteract}->{_atprompt}=1;
    } elsif ($match =~ /REMOTE HOST IDENTIFICATION HAS CHANGED/){
	die "Known_hosts issue";
    }
    return bless($self,$class);
}
sub atprompt {
	my $self=shift;
	return *$self->{_xcatsshinteract}->{_atprompt};
}
1;
