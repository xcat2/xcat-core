#!/usr/bin/perl
### IBM(c) 2017 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT_plugin::openbmc2;

BEGIN
    {
        $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
    }
use lib "$::XCATROOT/lib/perl";
use strict;
use warnings "all";

use JSON;
use xCAT::Utils;
use xCAT::Usage;
use xCAT::SvrUtils;
use xCAT::OPENBMC;

#-------------------------------------------------------

=head3  handled_commands

  Return list of commands handled by this plugin

=cut

#-------------------------------------------------------

sub handled_commands {
    return {
        rpower         => 'nodehm:mgt=openbmc',
    };
}

my %node_info = ();
my $callback;

#-------------------------------------------------------

=head3  preprocess_request

  preprocess the command

=cut

#-------------------------------------------------------
sub preprocess_request {
    my $request = shift;
    $callback  = shift;

    # if $::OPENBMC_PYTHON is 'YES', will run this script
    if (ref($request->{environment}) eq 'ARRAY' and ref($request->{environment}->[0]->{XCAT_OPENBMC_PYTHON}) eq 'ARRAY') {
        $::OPENBMC_PYTHON = $request->{environment}->[0]->{XCAT_OPENBMC_PYTHON}->[0];
    } elsif (ref($request->{environment}) eq 'ARRAY') {
        $::OPENBMC_PYTHON = $request->{environment}->[0]->{XCAT_OPENBMC_PYTHON};
    } else {
        $::OPENBMC_PYTHON = $request->{environment}->{XCAT_OPENBMC_PYTHON};
    }

    if (! (defined($::OPENBMC_PYTHON) and $::OPENBMC_PYTHON eq "YES")) {
        $request = {};
        return;
    }

    my $command   = $request->{command}->[0];
    my $noderange = $request->{node};
    my $extrargs  = $request->{arg};
    my @exargs    = ($request->{arg});
    my @requests;

    if (ref($extrargs)) {
        @exargs = @$extrargs;
    }
    my $usage_string = xCAT::Usage->parseCommand($command, @exargs);
    if ($usage_string) {
        $callback->({ data => [$usage_string] });
        $request = {};
        return;
    }

    my $parse_result = parse_args($command, $extrargs, $noderange);
    if (ref($parse_result) eq 'ARRAY') {
        my $error_data;
        foreach my $node (@$noderange) {
            $error_data .= "\n" if ($error_data);
            $error_data .= "$node: Error: " . "$parse_result->[1]";
        }
        $callback->({ errorcode => [$parse_result->[0]], data => [$error_data] });
        $request = {};
        return;
    }

    my $sn = xCAT::ServiceNodeUtils->get_ServiceNode($noderange, "xcat", "MN");
    foreach my $snkey (keys %$sn) {
        my $reqcopy = {%$request};
        $reqcopy->{node}                   = $sn->{$snkey};
        $reqcopy->{'_xcatdest'}            = $snkey;
        $reqcopy->{_xcatpreprocessed}->[0] = 1;
        push @requests, $reqcopy;
    }

    return \@requests;
}

#-------------------------------------------------------

=head3  process_request

  Process the command

=cut

#-------------------------------------------------------
sub process_request {
    my $request = shift;
    $callback = shift;
    my $noderange = $request->{node};
    my $check = parse_node_info($noderange);
    $callback->({ errorcode => [$check] }) if ($check);
    my $pid = xCAT::OPENBMC::start_python_agent();
    if (!defined($pid)) {
        xCAT::MsgUtils->message("E", { data => ["Error: Failed to start python agent"] }, $callback);
        return;
    }
    xCAT::OPENBMC::submit_agent_request($pid, $request, \%node_info, $callback);
    xCAT::OPENBMC::wait_agent($pid, $callback);
}

#-------------------------------------------------------

=head3  parse_args

  Parse the command line options and operands

=cut

#-------------------------------------------------------
sub parse_args {
    my $command  = shift;
    my $extrargs = shift;
    my $noderange = shift;
    my $subcommand = undef;

    if (scalar(@ARGV) >= 2 and ($command =~ /rpower/)) {
        return ([ 1, "Only one option is supported at the same time for $command" ]);
    } elsif (scalar(@ARGV) == 0 and $command =~ /rpower/) {
        return ([ 1, "No option specified for $command" ]);
    } else {
        $subcommand = $ARGV[0];
    }

    if ($command eq "rpower") {
        unless ($subcommand =~ /^on$|^off$|^softoff$|^reset$|^boot$|^bmcreboot$|^bmcstate$|^status$|^stat$|^state$/) {
            return ([ 1, "Unsupported command: $command $subcommand" ]);
        }
    } else {
        return ([ 1, "Unsupported command: $command" ]);
    }
}

#-------------------------------------------------------

=head3  parse_node_info

  Parse the node information: bmc, bmcip, username, password

=cut

#-------------------------------------------------------
sub parse_node_info {
    my $noderange = shift;
    my $rst = 0;

    my $passwd_table = xCAT::Table->new('passwd');
    my $passwd_hash = $passwd_table->getAttribs({ 'key' => 'openbmc' }, qw(username password));

    my $openbmc_table = xCAT::Table->new('openbmc');
    my $openbmc_hash = $openbmc_table->getNodesAttribs(\@$noderange, ['bmc', 'username', 'password']);

    foreach my $node (@$noderange) {
        if (defined($openbmc_hash->{$node}->[0])) {
            if ($openbmc_hash->{$node}->[0]->{'bmc'}) {
                $node_info{$node}{bmc} = $openbmc_hash->{$node}->[0]->{'bmc'};
                $node_info{$node}{bmcip} = xCAT::NetworkUtils::getNodeIPaddress($openbmc_hash->{$node}->[0]->{'bmc'});
            }
            unless($node_info{$node}{bmc}) {
                xCAT::SvrUtils::sendmsg("Error: Unable to get attribute bmc", $callback, $node);
                $rst = 1;
                next;
            }
            unless($node_info{$node}{bmcip}) {
                xCAT::SvrUtils::sendmsg("Error: Unable to resolve ip address for bmc: $node_info{$node}{bmc}", $callback, $node);
                delete $node_info{$node};
                $rst = 1;
                next;
            }
            if ($openbmc_hash->{$node}->[0]->{'username'}) {
                $node_info{$node}{username} = $openbmc_hash->{$node}->[0]->{'username'};
            } elsif ($passwd_hash and $passwd_hash->{username}) {
                $node_info{$node}{username} = $passwd_hash->{username};
            } else {
                xCAT::SvrUtils::sendmsg("Error: Unable to get attribute username", $callback, $node);
                delete $node_info{$node};
                $rst = 1;
                next;
            }

            if ($openbmc_hash->{$node}->[0]->{'password'}) {
                $node_info{$node}{password} = $openbmc_hash->{$node}->[0]->{'password'};
            } elsif ($passwd_hash and $passwd_hash->{password}) {
                $node_info{$node}{password} = $passwd_hash->{password};
            } else {
                xCAT::SvrUtils::sendmsg("Error: Unable to get attribute password", $callback, $node);
                delete $node_info{$node};
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

1;
