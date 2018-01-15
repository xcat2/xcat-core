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

my $LOCK_DIR = "/var/lock/xcat/";
my $LOCK_PATH = "/var/lock/xcat/agent.lock";
my $AGENT_SOCK_PATH = "/var/run/xcat/agent.sock";
my $PYTHON_LOG_PATH = "/var/log/xcat/agent.log";
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
sub start_python_agent {
    if (!defined(acquire_lock())) {
        xCAT::MsgUtils->message("S", "Error: Faild to require lock");
        return undef;
    }
    my $fd;
    open($fd, '>', $AGENT_SOCK_PATH) && close($fd);
    my $pid = fork;
    if (!defined $pid) {
        xCAT::MsgUtils->message("S", "Error: Unable to fork process");
        return undef;
    }
    $SIG{CHLD} = 'DEFAULT';
    if (!$pid) {
        # child
        open($fd, ">>", $PYTHON_LOG_PATH) && close($fd);
        open(STDOUT, '>>', $PYTHON_LOG_PATH) or die("open: $!");
        open(STDERR, '>>&', \*STDOUT) or die("open: $!");
        my $ret = exec ("/opt/xcat/lib/python/agent/agent.py");
        if (!defined($ret)) {
            xCAT::MsgUtils->message("S", "Error: Failed to start python agent");
        }
    }
    return $pid;
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
            xCAT::MsgUtils->message("E", { data => [$msg->{data}] }, $callback);
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
        xCAT::MsgUtils->message("E", { data => ["Error: Failed to connect to the agent"] }, $callback);
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
    $ret = $sock->send($sz);
    if (!$ret) {
        xCAT::MsgUtils->message("E", { data => ["Error: Failed to send message to the agent"] }, $callback);
        $sock->close();
        kill('TERM', $pid);
        return;
    }
    $ret = $sock->send($buf);
    if (!$ret) {
        xCAT::MsgUtils->message("E", { data => ["Error: Failed to send message to the agent"] }, $callback);
        $sock->close();
        kill('TERM', $pid);
        return;
    }
    while(1) {
        $ret = $sock->recv($buf, 4);
        if (!$ret) {
            last;
        }
        $sz = unpack('i', $buf);
        $ret = $sock->recv($buf, $sz);
        if (!$ret) {
            xCAT::MsgUtils->message("E", { data => ["Error: receive data from python agent unexpectedly"] }, $callback);
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
        xCAT::MsgUtils->message("E", { data => ["Error: python agent exited unexpectedly"] }, $callback);
    }
}

1;
