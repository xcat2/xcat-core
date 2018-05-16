#!/usr/bin/perl
## IBM(c) 2107 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::OPENBMC;

BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use strict;
use warnings "all";

use HTTP::Async;
use HTTP::Request;
use HTTP::Headers;
use HTTP::Cookies;
use Data::Dumper;
use Time::HiRes qw(sleep time);
use JSON;
use File::Path;
use Fcntl ":flock";
use IO::Socket::UNIX qw( SOCK_STREAM );
use xCAT_monitoring::monitorctrl;
use xCAT::TableUtils;

my $LOCK_DIR = "/var/lock/xcat/";
my $LOCK_PATH = "/var/lock/xcat/agent-$$.lock";
my $AGENT_SOCK_PATH = "/var/run/xcat/agent-$$.sock";
my $PYTHON_LOG_PATH = "/var/log/xcat/agent.log";
my $PYTHON_AGENT_FILE = "/opt/xcat/lib/python/agent/agent.py";
my $MSG_TYPE = "message";
my $DB_TYPE = "db";
my $lock_fd;

my $header = HTTP::Headers->new('Content-Type' => 'application/json');

sub new {
    my $async = shift;
    $async = shift if (($async) && ($async =~ /OPENBMC/));
    my $url = shift;
    my $content = shift;
    my $method = 'POST';

    my $id = send_request( $async, $method, $url, $content );

    return $id;
}

sub send_request {
    my $async = shift;
    $async = shift if (($async) && ($async =~ /OPENBMC/));
    my $method = shift;
    my $url = shift;
    my $content = shift;

    my $request = HTTP::Request->new( $method, $url, $header, $content );
    my $id = $async->add_with_opts($request, {});
    return $id;
}

# if lock is released unexpectedly, python side would aware of the error after
# getting this lock
sub acquire_lock {
    mkpath($LOCK_DIR);
    # always create a new lock file
    unlink($LOCK_PATH);
    open($lock_fd, ">>", $LOCK_PATH) or return undef;
    flock($lock_fd, LOCK_EX) or return undef;
    return $lock_fd;
}

sub exists_python_agent {
    if ( -e $PYTHON_AGENT_FILE) {
        return 1;
    }
    return 0;
}
sub python_agent_reaper {
    unlink($LOCK_PATH);
    unlink($AGENT_SOCK_PATH);
}
sub start_python_agent {

    if (!defined(acquire_lock())) {
        xCAT::MsgUtils->message("S", "start_python_agent() Error: Failed to acquire lock");
        return undef;
    }

    my $fd;
    my $pid = fork;
    if (!defined $pid) {
        xCAT::MsgUtils->message("S", "start_python_agent() Error: Unable to fork process");
        return undef;
    } elsif ($pid){

        open($fd, '>', $AGENT_SOCK_PATH) && close($fd);
        $SIG{INT} = $SIG{TERM} = \&python_agent_reaper;
        return $pid;
    }

    $SIG{CHLD} = 'DEFAULT';
    if (!$pid) {
        # child
        open($fd, ">>", $PYTHON_LOG_PATH) && close($fd);
        open(STDOUT, '>>', $PYTHON_LOG_PATH) or die("open: $!");
        open(STDERR, '>>&', \*STDOUT) or die("open: $!");
        my @args = ( "$PYTHON_AGENT_FILE --sock $AGENT_SOCK_PATH --lockfile $LOCK_PATH" );
        my $ret = exec @args;
        if (!defined($ret)) {
            xCAT::MsgUtils->message("S", "start_python_agent() Error: Failed to start the xCAT Python agent.");
            exit(1);
        }
    }

}

sub handle_message {
    my ($data, $callback) = @_;
    if($data->{type} eq $MSG_TYPE) {
        my $msg = $data->{msg};
        if ($msg->{type} eq 'info') {
            xCAT::MsgUtils->message("I", { data => [$msg->{data}] }, $callback);
        } elsif ($msg->{type} eq 'warning') {
            xCAT::MsgUtils->message("W", { data => [$msg->{data}] }, $callback);
        } elsif ($msg->{type} eq 'error'){
            xCAT::SvrUtils::sendmsg([ 1, $msg->{data} ], $callback, $msg->{node});
        } elsif ($msg->{type} eq 'syslog'){
            xCAT::MsgUtils->message("S", $msg->{data});
        }
    } elsif ($data->{type} eq $DB_TYPE) {
        my $attribute = $data->{attribute};
        if ($attribute->{name} eq 'status' and $attribute->{method} eq 'set' and $attribute->{type} eq 'node') {
             my %new_status = ($attribute->{value} => [$attribute->{node}]);
             xCAT_monitoring::monitorctrl::setNodeStatusAttributes(\%new_status, 1)
        }
    }
}

sub submit_agent_request {
    my ($pid, $req, $nodeinfo, $callback) = @_;
    my $sock;
    my $retry = 0;
    while($retry < 30) {
        $sock = IO::Socket::UNIX->new(Peer => $AGENT_SOCK_PATH, Type => SOCK_STREAM, Timeout => 10, Blocking => 1);
        if (!defined($sock)) {
            sleep(0.1);
        } else {
            last;
        }
        $retry++;
    }
    if (!defined($sock)) {
        xCAT::MsgUtils->message("E", { data => ["OpenBMC management is using a Python framework. An error has occurred when trying to create socket $AGENT_SOCK_PATH."] }, $callback);
        kill('TERM', $pid);
        return;
    }
    my $xcatdebugmode = 0;
    if ($::XCATSITEVALS{xcatdebugmode}) { $xcatdebugmode = $::XCATSITEVALS{xcatdebugmode} }
    my %env_hash = ();
    $env_hash{debugmode} = $xcatdebugmode;
    my ($data, $sz, $ret, $buf);
    $data->{module} = 'openbmc';
    $data->{command} = $req->{command}->[0];
    $data->{args} = $req->{arg};
    $data->{cwd} = $req->{cwd};
    $data->{nodes} = $req->{node};
    $data->{nodeinfo} = $nodeinfo;
    $data->{envs} = \%env_hash;
    $buf = encode_json($data);
    $sz = pack('i', length($buf));
    # send length of data first
    $ret = $sock->send($sz);
    if (!$ret) {
        xCAT::MsgUtils->message("E", { data => ["Failed to send message to the agent"] }, $callback);
        $sock->close();
        kill('TERM', $pid);
        return;
    }
    # send data
    $ret = $sock->send($buf);
    if (!$ret) {
        xCAT::MsgUtils->message("E", { data => ["Failed to send message to the agent"] }, $callback);
        $sock->close();
        kill('TERM', $pid);
        return;
    }
    while(1) {
        $ret = $sock->recv($buf, 4);
        if (!$ret) {
            last;
        }
        # receive the length of data
        $sz = unpack('i', $buf);
        # read data with length is $sz
        $ret = $sock->recv($buf, $sz);
        if (!$ret) {
            xCAT::MsgUtils->message("E", { data => ["receive data from python agent unexpectedly"] }, $callback);
            last;
        }
        $data = decode_json($buf);
        handle_message($data, $callback);
    }
    # no message received, the socket on the agent side should be closed.
    $sock->close();
}

sub wait_agent {
    my ($pid, $callback) = @_;
    waitpid($pid, 0);
    if ($? >> 8 != 0) {
        xCAT::MsgUtils->message("E", { data => ["Agent exited unexpectedly.  See $PYTHON_LOG_PATH for details."] }, $callback);
        xCAT::MsgUtils->message("I", { data => ["To revert to Perl framework: chdef -t site clustersite openbmcperl=ALL"] }, $callback);
    }
    python_agent_reaper();
}

#--------------------------------------------------------------------------------

=head3 run_cmd_in_perl 
      Check if specified command should run in perl
      The policy is:
            Get value from `openbmcperl`, `XCAT_OPENBMC_DEVEL`, agent.py:

            1. If agent.py does not exist:                          ==> 1: Go Perl
            2. If `openbmcperl` not set or doesn't contain command: ==> 0: Go Python
            3. If `openbmcperl` lists the command OR set to "ALL"   ==> 1: Go Perl
            4. If command is one of unsupported commands AND
                  a. XCAT_OPENBMC_DEVEL = YES                       ==> 0: Go Python
                  b. XCAT_OPENBMC_DEVEL = NO or not set             ==> 1: Go Perl
=cut

#--------------------------------------------------------------------------------
sub run_cmd_in_perl {
    my ($class, $command, $env) = @_;
    if (! -e $PYTHON_AGENT_FILE) {
        return (1, ''); # Go Perl: agent file is not there
    }

    my @entries = xCAT::TableUtils->get_site_attribute("openbmcperl");
    my $site_entry = $entries[0];
    my $support_obmc = undef;
    if (ref($env) eq 'ARRAY' and ref($env->[0]->{XCAT_OPENBMC_DEVEL}) eq 'ARRAY') {
        $support_obmc = $env->[0]->{XCAT_OPENBMC_DEVEL}->[0];
    } elsif (ref($env) eq 'ARRAY') {
        $support_obmc = $env->[0]->{XCAT_OPENBMC_DEVEL};
    } else {
        $support_obmc = $env->{XCAT_OPENBMC_DEVEL};
    }
    if ($support_obmc and uc($support_obmc) ne 'YES' and uc($support_obmc) ne 'NO') {
        return (-1, "Invalid value $support_obmc for XCAT_OPENBMC_DEVEL, only 'YES' and 'NO' are supported.");
    }
    if ($site_entry and ($site_entry =~ $command or uc($site_entry) eq "ALL")) {
        return (1, ''); # Go Perl: command listed in "openbmcperl" or "ALL"
    }

    # List of commands currently not supported in Python
    my @unsupported_in_python_commands = ('rflash', 'getopenbmccons');

    if ($command ~~ @unsupported_in_python_commands) {
        # Command currently not supported in Python
        if ($support_obmc and uc($support_obmc) eq 'YES') {
            return (0, ''); # Go Python: unsuppored command, but XCAT_OPENBMC_DEVEL=YES overrides
        } else {
            return (1, ''); # Go Perl: unsuppored command
        }
    }

    return (0, ''); # Go Python: default
}

1;
