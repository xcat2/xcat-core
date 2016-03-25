# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head1
  xCAT plugin package to handle getadapter management

   Supported command:
        getadapter->getadapter

=cut

#-------------------------------------------------------
package xCAT_plugin::getadapter;

BEGIN {
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : -d '/opt/xcat' ? '/opt/xcat' : '/usr';
}
use lib "$::XCATROOT/lib/perl";

use xCAT::Table;
use xCAT::Utils;
use xCAT::FifoPipe;
use xCAT::MsgUtils;
use xCAT::State;
use Data::Dumper;
use Getopt::Long;
use File::Path;
use Term::ANSIColor;
use Time::Local;
use strict;
use Class::Struct;
use XML::Simple;
use Storable qw(dclone);

my %usage = (
"getadapter" => "Usage:\n\tgetadapter [-h|--help|-v|--version|V]\n\tgetadapter <noderange> [-f]",
);

my $VERBOSE = 0;
use constant OPT_FORCE  => 0;
use constant OPT_UPDATE => 1;

use constant GET_ADPATER_DIR => "/var/run/getadapter";
use constant ALARM_TIMEOUT   => 1800;

unless (-d GET_ADPATER_DIR) {
    mkpath(GET_ADPATER_DIR);
}

my %child_pids;
my $timeout_event = 0;

#-------------------------------------------------------

=head3  handled_commands

Return list of commands handled by this plugin

=cut

#-------------------------------------------------------

sub handled_commands
{
    return {
        getadapter => "getadapter",
    };
}

#-------------------------------------------------------

=head3  process_request

  Process the command.

=cut

#-------------------------------------------------------
sub process_request
{
    my $request  = shift;
    my $callback = shift;
    my $subreq   = shift;
    my $command  = $request->{command}->[0];

    $SIG{INT} = $SIG{TERM} = sub {
        xCAT::MsgUtils->message("W", "getadapter: int or term signal received, clean up task state");
        exit(clean_up());
    };

    if ($command eq "getadapter") {
        &handle_getadapter($request, $callback, $subreq);
    }
    return;
}

#------------------------------------------------------------------

=head3  route_request

  Route the request, this funciton is called in the reqeust process.

  return REQUEST_UPDATE if update request arrived. Now just send
         message to the waiting process with fifo pipe.

         (TODO) If getadapter is used in chain table to complete
         the discovery process, the adapter information can be
         updated directly in immediate plugin and there is no need
         to fork plugin process.

  return REQUEST_WAIT if inspect request arrived. Tell xcatd fork
         plugin process to handle this request.
  return REQUEST_ERROR if error happened.

  Usage example:
        This is a hook function in xcatd, do not use it directly.
=cut

#-----------------------------------------------------------------
sub route_request {
    my ($request, $callback, $subreq) = @_;
    my $command = $request->{command}->[0];
    my $ret     = xCAT::State->REQUEST_ERROR;

    if (scalar(@{ $request->{node} }) == 0) {
        return $ret;
    }

    my $build_request_message_func = sub {
        my $req = shift;
        my $xs  = new XML::Simple();
        my $nic_info;
        $nic_info->{'nic'}  = $req->{'nic'};
        $nic_info->{'node'} = $req->{node}->[0];
        return $xs->XMLout($nic_info);
    };

    if (defined($request->{'action'}) and $request->{action}->[0] eq xCAT::State->UPDATE_ACTION) {

        # may be a callback request, just check the state then send message
        # no need to fork a plugin process.
        my $node            = ${ $request->{'node'} }[0];
        my $taskstate_table = xCAT::Table->new('taskstate');
        unless ($taskstate_table) {
            xCAT::MsgUtils->message("S", "Unable to open taskstate table, denying");
            return $ret;
        }
        my $node_obj = $taskstate_table->getAttribs({ 'node' => $node, 'command' => $command }, 'state', 'pid');

        if (defined($node_obj) and $node_obj->{'state'} eq xCAT::State->WAIT_STATE) {
            my $msg_queue = xCAT::FifoPipe->send_message(
                xCAT::Utils->full_path($node_obj->{'pid'}, GET_ADPATER_DIR),
                &$build_request_message_func($request));
            $ret = xCAT::State->REQUEST_UPDATE;
        }
        else {
            xCAT::MsgUtils->message("S", "Error to find the node in waiting state");
        }
        $taskstate_table->close();
    } elsif (!defined($request->{'action'}) or $request->{action}->[0] eq xCAT::State->INSPECT_ACTION) {

        # new request, fork a plugin child process to handle this request.
        $ret = xCAT::State->REQUEST_WAIT;
    }
    return $ret;
}

#-------------------------------------------------------

=head3  handle_getadapter

  This function check the command option, then call the
  function to complete the request.

  Usage example:
        This function is called from process_request,
        do not call it directly.
=cut

#-------------------------------------------------------

sub handle_getadapter {
    my $request  = shift;
    my $callback = shift;
    my $subreq   = shift;
    my $command  = $request->{command}->[0];
    my @opts;

    my @args = ();
    my $HELP;
    my $VERSION;
    my $FORCE;
    my $UPDATE;
    if (ref($request->{arg})) {
        @args = @{ $request->{arg} };
    } else {
        @args = ($request->{arg});
    }
    @ARGV = @args;
    Getopt::Long::Configure("bundling");
    Getopt::Long::Configure("no_pass_through");
    if (!GetOptions("h|help" => \$HELP,
            "v|version" => \$VERSION,
            "f"         => \$FORCE,
            "u"         => \$UPDATE,
            "V"         => \$VERBOSE
        )) {
        if ($usage{$command}) {
            my $rsp = {};
            $rsp->{error}->[0]     = $usage{$command};
            $rsp->{errorcode}->[0] = 1;
            $callback->($rsp);
        }
        return;
    }

    if ($HELP) {
        if ($usage{$command}) {
            my %rsp;
            $rsp{data}->[0] = $usage{$command};
            $callback->(\%rsp);
        }
        return;
    }

    if ($VERSION) {
        my $ver = xCAT::Utils->Version();
        my %rsp;
        $rsp{data}->[0] = "$ver";
        $callback->(\%rsp);
        return;
    }
    @opts = ($FORCE, $UPDATE);

    if (!defined($request->{'action'}) or $request->{action}->[0] eq xCAT::State->INSPECT_ACTION) {
        return inspect_adapter($request, $callback, $subreq, \@opts);
    }

    return;
}

#------------------------------------------------------------------

=head3  clean_up

  Clean up the getadapter running environment

  return 1 if clean up failed

  Usage example:
        clean_up()
=cut

#-----------------------------------------------------------------
sub clean_up {
    my $ret = 0;
    foreach (keys %child_pids) {
        kill 2, $_;
    }
    xCAT::MsgUtils->message("S", "Getadapter: clean up task state in database");

   # NOTE(chenglch): Currently xcatd listener process has bug in signal handler,
   # just comment out these code.
    my $taskstate_table = xCAT::Table->new('taskstate');

    if ($taskstate_table) {
        $taskstate_table->delEntries({ 'pid' => getppid() });
        $taskstate_table->close();
    }
    else {
        xCAT::MsgUtils->message("S", "Clean up taskstate error");
        $ret = 1;
    }
    xCAT::FifoPipe->remove_pipe(xCAT::Utils->full_path(getppid(), GET_ADPATER_DIR));
    return $ret;
}


#------------------------------------------------------------------

=head3  deploy_genesis

  Fork processes to boot the target node into genesis

  return array of nodes which are booting geneses.

  Usage example:
        my @nodes= ('node1', 'node2', 'node3');
        my $nodes_desc_ptr,  a hash pointer to the description of nodes array.
        @nodes = deploy_genesis(\@nodes, $nodes_desc_ptr, $callback, $subreq);

=cut

#-----------------------------------------------------------------
sub deploy_genesis {
    my $nodes_ptr      = shift;
    my $nodes_desc_ptr = shift;
    my $callback       = shift;
    my $subreq         = shift;
    my @nodes          = @{$nodes_ptr};
    my $pid;

    my $child_process_func = sub {
        my ($node, $node_desc_ptr, $callback, $subreq) = @_;
        my $outref = xCAT::Utils->runxcmd(
            {
                command => ['nodeset'],
                node    => ["$node"],
                arg     => ['runcmd=getadapter'],
            },
            $subreq, 0, 1);
        if ($::RUNCMD_RC != 0) {
            $callback->({ error => "failed to run command: nodeset $node rumcmd=getadapter", errorcode => 1 });
            return 1;
        }
        if ($node_desc_ptr->{mgt} eq "ipmi") {
            $outref = xCAT::Utils->runxcmd(
                {
                    command => ["rsetboot"],
                    node    => ["$node"],
                    arg     => ['net'],
                },
                $subreq, 0, 1);
            if ($::RUNCMD_RC != 0) {
                $callback->({ error => "failed to run command: rsetboot $node net", errorcode => 1 });
                return 1;
            }

            $outref = xCAT::Utils->runxcmd(
                {
                    command => ['rpower'],
                    node    => ["$node"],
                    arg     => ['reset'],
                },
                $subreq, 0, 1);
            if ($::RUNCMD_RC != 0) {
                $callback->({ error => "failed to run command: rpower $node reset", errorcode => 1 });
                return 1;
            }
        } else {
            $outref = xCAT::Utils->runxcmd(
                {
                    command => ["rnetboot"],
                    node    => ["$node"],
                },
                $subreq, 0, 1);
            if ($::RUNCMD_RC != 0) {
                $callback->({ error => "failed to run command: rnetboot $node", errorcode => 1 });
                return 1;
            }
        }
        return 0;
    };    # end of child_process_func

    $SIG{CHLD} = 'DEFAULT';
    foreach my $node (@nodes) {
        $pid = xCAT::Utils->xfork();
        if (!defined($pid)) {
            $callback->({ error => "failed to fork process to restart $node", errorcode => 1 });
            $node = undef;
            last;
        } elsif ($pid == 0) {

            # child process
            $SIG{INT} = $SIG{TERM} = 'DEFAULT';
            my $node_desc_ptr = $nodes_desc_ptr->{$node};
            xCAT::MsgUtils->trace($VERBOSE, "d", "getadapter: fork new process $$ to start scaning $node");
            my $ret = &$child_process_func($node, $node_desc_ptr, $callback, $subreq);
            exit($ret);
        } else {

            # Parent process
            $child_pids{$pid} = $node;
        }
    }

    # Wait for all processes to end
    my $cpid = 0;
    while (keys %child_pids) {
        if (($cpid = wait()) > 0) {
            my $status = $?;
            if ($status != 0) {
                my $node = $child_pids{$cpid};

                #delete nodes if child process error.
                map { $_ = undef if $_ eq $node } @nodes;
            }
            delete $child_pids{$cpid};
        }
    }

    # delete undef
    @nodes = grep /./, @nodes;
    return @nodes;
}

#------------------------------------------------------------------

=head3  update_adapter_result

  Update the adapter information in the nics table.
  Print the adapter information to STDOUT.

  Input:
        $msg: A hash pointer parsed from message from fifopipe
        $nodes_desc_ptr: Nodes description pointer
        $opts_ptr: A pointer to the nodes option
        $callback: callback object

  return -1 if unexpectd error.
  return 0 success

  Usage example:
        my $msg;
        my $nodes_desc_ptr;
        my $opts_ptr;
        my $callback
        update_adapter_result($msg, $nodes_desc_ptr, $opts_ptr, $callback));

=cut

#-----------------------------------------------------------------
sub update_adapter_result {
    my $msg            = shift;
    my $nodes_desc_ptr = shift;
    my $opts_ptr       = shift;
    my $callback       = shift;
    my $node           = $msg->{'node'};
    my $nicnum         = scalar @{ $msg->{nic} };
    my ($output, $data, $interface_exists, $has_nic, %updates);

    $data   = "";
    $output = "[$node] scan successfully below is result:\n";
    for (my $i = 0 ; $i < $nicnum ; $i++) {
        $output.= "$node:[$i]->";
        $interface_exists = 0;

        if (exists($msg->{nic}->[$i]->{interface})) {
            $output .= $msg->{nic}->[$i]->{interface};
            if ($has_nic) {
                $data .= "," . $msg->{nic}->[$i]->{interface} . "!";
            }
            else {
                $data .= $msg->{nic}->[$i]->{interface} . "!";
            }
            $interface_exists = 1;
            $has_nic          = 1;
        }
        if (exists($msg->{nic}->[$i]->{mac})) {
            $output .= "!mac=" . $msg->{nic}->[$i]->{mac};
            if ($interface_exists) {
                $data .= " mac=" . $msg->{nic}->[$i]->{mac};
            }
        }
        if (exists($msg->{nic}->[$i]->{pcilocation})) {
            $output .= "|pci=" . $msg->{nic}->[$i]->{pcilocation};
            if ($interface_exists) {
                $data .= "pci=" . $msg->{nic}->[$i]->{pcilocation};
            }
        }
        if (exists($msg->{nic}->[$i]->{predictablename})) {
            $output .= "|candidatename=" . $msg->{nic}->[$i]->{predictablename};
        }
        if (exists($msg->{nic}->[$i]->{vendor})) {
            $output .= "|vendor=" . $msg->{nic}->[$i]->{vendor};
        }
        if (exists($msg->{nic}->[$i]->{model})) {
            $output .= "|model=" . $msg->{nic}->[$i]->{model};
        }
        if (exists($msg->{nic}->[$i]->{linkstate})) {
            $output .= "|linkstate=" . $msg->{nic}->[$i]->{linkstate};
            if ($interface_exists) {
                $data .= " linkstate=" . $msg->{nic}->[$i]->{linkstate};
            }
        }
        $output .= "\n";
    }
    $callback->({ data => "$output" });
    my $nics_table = xCAT::Table->new('nics');
    unless ($nics_table) {
        xCAT::MsgUtils->message("S", "Unable to open nics table, denying");
        $callback->({ error => "Error to connect to nics table.",
                errorcode => 1 });
        return -1;
    }
    $updates{'nicsadapter'} = $data;
    if ($nics_table->setAttribs({ 'node' => $node }, \%updates) != 0) {
        xCAT::MsgUtils->message("S", "Error to update nics table.");
        $callback->({ error => "Error to update nics table.",
                errorcode => 1 });
        return -1;
    }
    return 0;
}

#------------------------------------------------------------------

=head3  do_inspect

  The main function to run the getadapter process


  Input:
        $nodesptr: The nodes pointer
        $nodes_desc_ptr: Nodes description pointer
        $opts_ptr: Option pointer
        $callback: callback object
        $subreq: xcat sub request

  return -1 if unexpectd error.
  return 0 success

=cut

#-----------------------------------------------------------------

sub do_inspect {
    my $nodesptr       = shift;
    my $nodes_desc_ptr = shift;
    my $opts_ptr       = shift;
    my $callback       = shift;
    my $subreq         = shift;
    my @nodes          = @{$nodesptr};
    my $updates;
    my $msg;    # parse from xml

    my $parse_request_message_func = sub {
        my $xml = shift;
        my $xs  = new XML::Simple();
        return $xs->XMLin($xml);
    };

    my $timeout_output_func = sub {
        my $nodes_ptr = shift;
        my $callback  = shift;
        foreach my $node (@{$nodes_ptr}) {
            if ($node) {
                $callback->({ error => "$node: Timeout to get the adapter information",
                        errorcode => 1 });
            }
        }
    };

    my $taskstate_table = xCAT::Table->new('taskstate');
    unless ($taskstate_table) {
        xCAT::MsgUtils->message("S", "Unable to open taskstate table, denying");
        $callback->({ error => "Error to connect to taskstate table.",
                errorcode => 1 });
        return -1;
    }

    # TODO(chenglch) Currently xcat db access is a single process model, this is
    # safe. In the future:
    # 1. If database is refactored, we need to protect the task
    #    state with Optimistic Lock of database.
    # 2. If we leverage the memcache or other cache database, we can make use of
    #    the feature of the CAS to provide the atomic operation.
    foreach my $node (@nodes) {
        $updates->{$node}->{'command'} = "getadapter";
        $updates->{$node}->{'state'}   = xCAT::State->WAIT_STATE;
        $updates->{$node}->{'pid'}     = getppid();
    }
    $taskstate_table->setNodesAttribs($updates);
    $taskstate_table->close();
    @nodes = deploy_genesis(\@nodes, $nodes_desc_ptr, $callback, $subreq);
    my $total = scalar(@nodes);
    my $count = 0;
    my @node_buf;

    $SIG{ALRM} = sub {
        xCAT::MsgUtils->message("W", "getadapter: alarm signal received");
        $timeout_event = 1;

        # pipe broken, wake up the wait fifo pipe
        xCAT::FifoPipe->remove_pipe(xCAT::Utils->full_path(getppid(), GET_ADPATER_DIR));
    };
    alarm(ALARM_TIMEOUT);

    while ($count < $total) {
        my $c = xCAT::FifoPipe->recv_message(
            xCAT::Utils->full_path(getppid(), GET_ADPATER_DIR),
            \@node_buf);
        if ($c <= 0) {
            if ($timeout_event == 1) {
                &$timeout_output_func(\@nodes, $callback);
                clean_up();
                return -1;
            }
            xCAT::MsgUtils->message("S", "Unexpected pipe error, abort.");
            return -1;
        }

        my $nics_table = xCAT::Table->new('nics');
        unless ($nics_table) {
            xCAT::MsgUtils->message("S", "Unable to open nics table, denying");
            return -1;
        }

        my $taskstate_table = xCAT::Table->new('taskstate');
        unless ($taskstate_table) {
            xCAT::MsgUtils->message("S", "Unable to open taskstate table, denying");
            return -1;
        }

        for (my $i = 0 ; $i < $c ; $i++) {
            $msg = &$parse_request_message_func($node_buf[$i]);

            # delete the node
            map { $_ = undef if $_ eq $msg->{'node'} } @nodes;
            if (update_adapter_result($msg, $nodes_desc_ptr, $opts_ptr, $callback)) {
                return -1;
            }
            $taskstate_table->delEntries({ 'node' => $msg->{'node'} });
        }
        $count += $c;
        $taskstate_table->close();
        $nics_table->close();
    }
    xCAT::MsgUtils->trace($VERBOSE, "d", "getadapter: remove pipe " . xCAT::Utils->full_path(getppid(), GET_ADPATER_DIR));
    xCAT::FifoPipe->remove_pipe(xCAT::Utils->full_path(getppid(), GET_ADPATER_DIR));
    return 0;
}

#------------------------------------------------------------------

=head3  inspect_adapter

  Process the getadapter command option.

  return -1 if unexpectd error.
  return 0 success.

=cut

#-----------------------------------------------------------------
sub inspect_adapter {
    my $request  = shift;
    my $callback = shift;
    my $subreq   = shift;
    my $opts_ptr = shift;
    my @nodes;
    my @entries;
    my %nodes_desc;

    my $init_desc_func = sub {
        my $nodes_ptr      = shift;
        my $callback       = shift;
        my $nodes_desc_ptr = shift;
        my @nodes          = @{$nodes_ptr};
        my $nodehm_table = xCAT::Table->new('nodehm');
        unless ($nodehm_table) {
            xCAT::MsgUtils->message("S", "Unable to open nodehm table, denying");
            return -1;
        }
        my $entries = $nodehm_table->getNodesAttribs($nodes_ptr, ['mgt']);
        unless ($entries) {
            xCAT::MsgUtils->message("S", "No records about " . join(",", @nodes) . " in nodehm table");
            return -1;
        }
        $nodehm_table->close();
        foreach my $node (@nodes) {
            if(!defined($entries->{$node}) || !defined($entries->{$node}->[0]->{mgt})) {
                $callback->({ error => "$node: mgt configuration can not be found.",
                              errorcode => 1 });
                next;
            }
            $nodes_desc_ptr->{$node}->{'mgt'} = $entries->{$node}->[0]->{mgt};
        }
        return 0;
    };    # end of init_desc_func

    # Get the nodes should be inspect.
    if ($opts_ptr->[OPT_FORCE]) {
        @nodes = @{ $request->{node} };
    } else {
        my $nics_table = xCAT::Table->new('nics');
        unless ($nics_table) {
            xCAT::MsgUtils->message("S", "Unable to open nics table, denying");
            return -1;
        }
        my $entries = $nics_table->getNodesAttribs($request->{node}, ['nicsadapter']);
        foreach my $node (@{ $request->{node} }) {
            if($entries->{$node} && $entries->{$node}->[0]->{nicsadapter}) {
                $callback->({ data => "$node: Adapter information exists, no need to inspect." });
                next;
            }
            push(@nodes, $node);
        }
    }
    if (scalar(@nodes) == 0) {
        $callback->({ data => "No adapter information need to inspect." });
        return -1;
    }
    xCAT::MsgUtils->trace($VERBOSE, "d", "getadapter: scaning start for " . join(",", @nodes));
    if (&$init_desc_func(\@nodes, $callback, \%nodes_desc)) {
        return -1;
    }
    return do_inspect(\@nodes, \%nodes_desc, $opts_ptr, $callback, $subreq);
}

1;
