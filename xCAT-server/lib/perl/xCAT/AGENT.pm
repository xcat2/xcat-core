#!/usr/bin/perl
## IBM(c) 2018 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::AGENT;

BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use strict;
use warnings "all";

use JSON;
use Time::HiRes qw(sleep time);
use File::Path;
use Fcntl ":flock";
use IO::Socket::UNIX qw( SOCK_STREAM );
use xCAT_monitoring::monitorctrl;
use xCAT::TableUtils;

my $LOCK_DIR = "/var/lock/xcat/";
my $LOCK_PATH = "/var/lock/xcat/agent.lock";
my $AGENT_SOCK_PATH = "/var/run/xcat/agent.sock";
my $PYTHON_LOG_PATH = "/var/log/xcat/agent.log";
my $PYTHON_AGENT_FILE = "/opt/xcat/lib/python/agent/agent.py";
my $MSG_TYPE = "message";
my $DB_TYPE = "db";
my $lock_fd;

my %module_type = (
    "openbmc" => "OpenBMC",
    "redfish" => "Redfish",
);

#-------------------------------------------------------

=head3  parse_node_info

  Parse the node information: bmc, bmcip, username, password

=cut

#-------------------------------------------------------
sub parse_node_info {
    my $noderange = shift;
    my $module = shift;
    my $node_info_ref = shift;
    my $callback = shift;
    my $rst = 0;

    my $passwd_table = xCAT::Table->new('passwd');
    my $passwd_hash = $passwd_table->getAttribs({ 'key' => $module }, qw(username password));

    my $openbmc_table = xCAT::Table->new('openbmc');
    my $openbmc_hash = $openbmc_table->getNodesAttribs(\@$noderange, ['bmc', 'username', 'password']);

    foreach my $node (@$noderange) {
        if (defined($openbmc_hash->{$node}->[0])) {
            if ($openbmc_hash->{$node}->[0]->{'bmc'}) {
                $node_info_ref->{$node}->{bmc} = $openbmc_hash->{$node}->[0]->{'bmc'};
                $node_info_ref->{$node}->{bmcip} = xCAT::NetworkUtils::getNodeIPaddress($openbmc_hash->{$node}->[0]->{'bmc'});
            }
            unless($node_info_ref->{$node}->{bmc}) {
                xCAT::SvrUtils::sendmsg("Error: Unable to get attribute bmc", $callback, $node);
                delete $node_info_ref->{$node};
                $rst = 1;
                next;
            }
            unless($node_info_ref->{$node}->{bmcip}) {
                xCAT::SvrUtils::sendmsg("Error: Unable to resolve ip address for bmc: $node_info_ref->{$node}->{bmc}", $callback, $node);
                delete $node_info_ref->{$node};
                $rst = 1;
                next;
            }
            if ($openbmc_hash->{$node}->[0]->{'username'}) {
                $node_info_ref->{$node}->{username} = $openbmc_hash->{$node}->[0]->{'username'};
            } elsif ($passwd_hash and $passwd_hash->{username}) {
                $node_info_ref->{$node}->{username} = $passwd_hash->{username};
            } else {
                xCAT::SvrUtils::sendmsg("Error: Unable to get attribute username", $callback, $node);
                delete $node_info_ref->{$node};
                $rst = 1;
                next;
            }

            if ($openbmc_hash->{$node}->[0]->{'password'}) {
                $node_info_ref->{$node}->{password} = $openbmc_hash->{$node}->[0]->{'password'};
            } elsif ($passwd_hash and $passwd_hash->{password}) {
                $node_info_ref->{$node}->{password} = $passwd_hash->{password};
            } else {
                xCAT::SvrUtils::sendmsg("Error: Unable to get attribute password", $callback, $node);
                delete $node_info_ref->{$node};
                $rst = 1;
                next;
            }
        } else {
            xCAT::SvrUtils::sendmsg("Error: Unable to get information from openbmc table", $callback, $node);
            $rst = 1;
            next;
        }
    }

    return $rst;
}

sub acquire_lock {
    my $ppid = shift;
    $ppid = shift if (($ppid) && ($ppid =~ /AGENT/));

    mkpath($LOCK_DIR);
    # always create a new lock file
    if ($ppid) {
        $LOCK_PATH = "$LOCK_PATH.$ppid";
        $AGENT_SOCK_PATH = "$AGENT_SOCK_PATH.$ppid";
    }
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
    my $ppid = shift;
    $ppid = shift if (($ppid) && ($ppid =~ /AGENT/));

    if (!defined(acquire_lock($ppid))) {
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
        } elsif ($msg->{type} eq 'info_with_host') {
            xCAT::MsgUtils->message("I", { data => [$msg->{data}], host => [1] }, $callback);
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
    my ($pid, $req, $module, $nodeinfo, $callback) = @_;
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
        xCAT::MsgUtils->message("E", { data => ["$module_type{$module} management is using a Python framework. An error has occurred when trying to create socket $AGENT_SOCK_PATH."] }, $callback);
        kill('TERM', $pid);
        return;
    }
    my $xcatdebugmode = 0;
    if ($::XCATSITEVALS{xcatdebugmode}) { $xcatdebugmode = $::XCATSITEVALS{xcatdebugmode} }
    my %env_hash = ();
    $env_hash{debugmode} = $xcatdebugmode;
    my ($data, $sz, $ret, $buf);
    $data->{module} = $module;
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
    }
    python_agent_reaper();
}

1;
