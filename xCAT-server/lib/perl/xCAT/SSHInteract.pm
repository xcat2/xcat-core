package xCAT::SSHInteract;
use Exporter;
use Net::Telnet;
use strict;
our @ISA = qw/Exporter Net::Telnet/;
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
	$tty_fd = $tty->fileno or die "$!";
	close($pty);
	open STDIN, "<&", $tty_fd;
	open STDOUT,">&",$tty_fd;
	$pty->make_slave_controlling_terminal();
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
	if ($nokeycheck) { delete $args{"-nokeycheck"}; }
	my $self = Net::Telnet->new(%args);
	_startssh($self,$pty,$username,$host,"-nokeycheck"=>$nokeycheck);
    my ($prematch,$match) = $self->waitfor([Match => $args{prompt},'/password:/i',]);
    if ($match =~ /password:/i) {
	    #$self->waitfor("-match" => '/password:/i', -errmode => "return") or die "Unable to reach host ",$self->lastline;
            $self->print($password);
            my $nextline = $self->getline();
            if ($nextline eq "\n") {
		$nextline = $self->get();
	    }
	    if ($nextline =~ /^password:/ or $nextline =~ /Permission denied, please try again/) {
		    die "Incorrect Password";
	    }
    }
	return bless($self,$class);
}
1;
