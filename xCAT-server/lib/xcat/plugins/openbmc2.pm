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
use Getopt::Long;
use xCAT::Usage;
use xCAT::SvrUtils;
use xCAT::OPENBMC;
use xCAT_plugin::openbmc;

#-------------------------------------------------------

=head3  handled_commands

  Return list of commands handled by this plugin

=cut

#-------------------------------------------------------

sub handled_commands {
    return {
        rbeacon        => 'nodehm:mgt=openbmc',
        rflash         => 'nodehm:mgt=openbmc',
        rinv           => 'nodehm:mgt=openbmc',
        rpower         => 'nodehm:mgt=openbmc',
        rsetboot       => 'nodehm:mgt=openbmc',
        rvitals        => 'nodehm:mgt=openbmc',
        rspconfig      => 'nodehm:mgt=openbmc',
        reventlog      => 'nodehm:mgt=openbmc',
    };
}

# Common logging messages:
my $usage_errormsg = "Usage error.";
my $reventlog_no_id_resolved_errormsg = "Provide a comma separated list of IDs to be resolved. Example: 'resolved=x,y,z'";

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

    my $command   = $request->{command}->[0];
    my ($rc, $msg) = xCAT::OPENBMC->run_cmd_in_perl($command, $request->{environment});
    if ($rc != 0) { $request = {}; return;}

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

    if (!xCAT::OPENBMC::exists_python_agent()) {
        xCAT::MsgUtils->message("E", { data => ["The xCAT Python agent does not exist. Check if xCAT-openbmc-py package is installed on management node and service nodes."] }, $callback);
        return;
    }

    my $noderange = $request->{node};
    my $check = parse_node_info($noderange);
    if (&refactor_args($request)) {
        xCAT::MsgUtils->message("E", { data => ["Failed to refactor arguments"] }, $callback);
        return;
    }
    $callback->({ errorcode => [$check] }) if ($check);
    return unless(%node_info);

    # If we can't start the python agent, exit immediately
    my $pid = xCAT::OPENBMC::start_python_agent();
    if (!defined($pid)) {
        xCAT::MsgUtils->message("E", { data => ["Failed to start the xCAT Python agent. Check /var/log/xcat/cluster.log for more information."] }, $callback);
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

    my $verbose;
    unless (GetOptions(
        'V|verbose'  => \$verbose,
    )) {
        return ([ 1, "Error parsing arguments." ]);
    }

    if (scalar(@ARGV) >= 2 and ($command =~ /rbeacon|rinv|rpower|rvitals/)) {
        return ([ 1, "Only one option is supported at the same time for $command" ]);
    } elsif (scalar(@ARGV) == 0 and $command =~ /rbeacon|rpower|rflash/) {
        return ([ 1, "No option specified for $command" ]);
    } else {
        $subcommand = $ARGV[0];
    }

    if ($command eq "rbeacon") {
        unless ($subcommand =~ /^on$|^off$/) {
            return ([ 1, "Only 'on' or 'off' is supported for OpenBMC managed nodes."]);
        }
    } elsif ($command eq "rflash") {
        my ($activate, $check, $delete, $directory, $list, $upload) = (0) x 6;
        my $no_host_reboot;
        GetOptions(
            'a|activate' => \$activate,
            'c|check'    => \$check,
            'delete'     => \$delete,
            'd'          => \$directory,
            'l|list'     => \$list,
            'u|upload'   => \$upload,
            'no-host-reboot' => \$no_host_reboot,
        );
        my $option_num = $activate+$check+$delete+$directory+$list+$upload;
        if ($option_num >= 2) {
            return ([ 1, "Multiple options are not supported."]);
        } elsif ($option_num == 0) {
            for my $arg (@ARGV) {
                if ($arg =~ /^-/) {
                    return ([ 1, "Unsupported command: $command $arg" ]);
                }
            }
            return ([ 1, "No options specified." ]);
        }
        if ($activate or $check or $delete or $upload) {
            return ([ 1, "More than one firmware specified is not supported."]) if ($#ARGV >= 1);
            if ($check) {
                return ([ 1, "Invalid firmware specified with '-c|--check'."]) if (@ARGV and ($ARGV[0] !~ /.*\.tar$/i or $#ARGV >= 1));
            }
            if ($activate or $delete or $upload) {
                my $option = "-a|--activate";
                if ($upload) {
                    $option = "-u|--upload";
                } elsif ($delete) {
                    $option = "--delete"
                }
                return ([ 1, "Invalid firmware specified with '$option'"]) if (!@ARGV);
                my $param = $ARGV[0];
                return ([ 1, "Invalid firmware specified with '$option': $param"]) if (($delete and $param !~ /^[[:xdigit:]]+$/i) 
                    or ($activate and $param !~ /^[[:xdigit:]]+$/i and $param !~ /.*\.tar$/i) or ($upload and $param !~ /.*\.tar$/i));
            }
        }
        if ($directory) {
            return ([ 1, "Unsupported command: $command '-d'" ]);
            return ([ 1, "More than one directory specified is not supported."]) if ($#ARGV >= 1);
            return ([ 1, "Invalid option specified with '-d'."]) if (!@ARGV);
        }
        if ($list) {
            return ([ 1, "Invalid option specified with '-l|--list'."]) if (@ARGV);
        }
    } elsif ($command eq "rinv") {
        $subcommand = "all" if (!defined($ARGV[0]));
        unless ($subcommand =~ /^all$|^cpu$|^dimm$|^firm$|^model$|^serial$/) {
            return ([ 1, "Unsupported command: $command $subcommand" ]);
        }
    } elsif ($command eq "rpower") {
        unless ($subcommand =~ /^on$|^off$|^softoff$|^reset$|^boot$|^bmcreboot$|^bmcstate$|^status$|^stat$|^state$/) {
            return ([ 1, "Unsupported command: $command $subcommand" ]);
        }
    } elsif ($command eq "rsetboot") {
        my $persistant;
        GetOptions('p'  => \$persistant);
        return ([ 1, "Only one option is supported at the same time for $command" ]) if (@ARGV > 1);
        $subcommand = "stat" if (!defined($ARGV[0]));
        unless ($subcommand =~ /^net$|^hd$|^cd$|^def$|^default$|^stat$/) {
            return ([ 1, "Unsupported command: $command $subcommand" ]);
        }
    } elsif ($command eq "rvitals") {
        $subcommand = "all" if (!defined($ARGV[0]));
        unless ($subcommand =~ /^all$|^altitude$|^fanspeed$|^leds$|^power$|^temp$|^voltage$|^wattage$/) {
            return ([ 1, "Unsupported command: $command $subcommand" ]);
        }
    } elsif ($command eq 'rspconfig') {
        xCAT_plugin::openbmc::parse_args('rspconfig', $extrargs, $noderange);
    } elsif ($command eq "reventlog") {
        $subcommand = "all" if (!defined($ARGV[0]));
        if ($subcommand =~ /^resolved=(.*)/) {
            my $value = $1;
            if (not $value) {
                return ([ 1, "$usage_errormsg $reventlog_no_id_resolved_errormsg" ]);
            }

            my $nodes_num = @$noderange;
            if (@$noderange > 1) {
                return ([ 1, "Resolving faults over a xCAT noderange is not recommended." ]);
            }

            xCAT::SvrUtils::sendmsg("Attempting to resolve the following log entries: $value...", $callback);
        } elsif ($subcommand !~ /^\d+$|^all$|^clear$/) {
            if ($subcommand =~ "resolved") {
                return ([ 1, "$usage_errormsg $reventlog_no_id_resolved_errormsg" ]);
            }
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
                delete $node_info{$node};
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

#-------------------------------------------------------

=head3  refactor_args

  refractor args to be easily dealt by python client

=cut

#-------------------------------------------------------

sub refactor_args {
    my $request = shift;
    my $command   = $request->{command}->[0];
    my $extrargs  = $request->{arg};    
    my $subcommand; 
    if ($command eq "rspconfig") {
        $subcommand = $extrargs->[0];
        if ($subcommand !~ /^dump$|^sshcfg$|^ip=dhcp$|^gard$/) {
            if (grep /=/, @$extrargs) {
                unshift @$extrargs, "set";
            } else {
                unshift @$extrargs, "get";
            }
        }
        if ($subcommand eq "dump") {
            if (defined($extrargs->[1]) and $extrargs->[1] =~ /-c|--clear|-d|--download/){
                splice(@$extrargs, 2, 0, "--id");
            }
        }
    }
    if ($command eq "reventlog") {
        if (!defined($extrargs->[0])) {
            # If no parameters are passed, default to list all records
            $request->{arg} = ["list","all"];
        }
        else {
            $subcommand = $extrargs->[0];
        }
        if ($subcommand =~ /^\d+$/) {
            unshift @$extrargs, "list";
        }
        elsif ($subcommand =~/^resolved=(.*)/) {
            unshift @$extrargs, "resolved";
        }
        elsif ($subcommand =~/^all$/) {
            unshift @$extrargs, "list";
        }
    }
    return 0;
}

1;
