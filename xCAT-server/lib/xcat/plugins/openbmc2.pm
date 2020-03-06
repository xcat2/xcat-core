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
use xCAT::AGENT;

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
$::VERBOSE = 0;

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
    # Request usage for openbmc sections only
    my $usage_string = xCAT::Usage->parseCommand($command . ".openbmc", @exargs);

    if ($usage_string) {
        if ($usage_string =~ /cannot be found/) {
            # Could not find usage for openbmc section, try getting usage for all sections
            $usage_string = xCAT::Usage->parseCommand($command, @exargs);
        }
        $callback->({ data => [$usage_string] });
        $request = {};
        return;
    }

    #pdu commands will be handled in the pdu plugin
    if ($command eq "rpower") {
        my $subcmd = $exargs[0];
        if(($subcmd eq 'pduoff') || ($subcmd eq 'pduon') || ($subcmd eq 'pdustat') || ($subcmd eq 'pdureset')){
             return;
        }
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

    if ($::VERBOSE) {
        xCAT::SvrUtils::sendmsg("Running command in Python", $callback);
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

    if (!xCAT::AGENT::exists_python_agent()) {
        xCAT::MsgUtils->message("E", { data => ["The xCAT Python agent does not exist. Check if xCAT-openbmc-py package is installed on management node and service nodes."] }, $callback);
        return;
    }

    my $noderange = $request->{node};
    my $check = xCAT::AGENT::parse_node_info($noderange, "openbmc", \%node_info, $callback);
    if (&refactor_args($request)) {
        xCAT::MsgUtils->message("E", { data => ["Failed to refactor arguments"] }, $callback);
        return;
    }
    $callback->({ errorcode => [$check] }) if ($check);
    return unless(%node_info);

    # If we can't start the python agent, exit immediately
    my $pid = xCAT::AGENT::start_python_agent($$);
    if (!defined($pid)) {
        xCAT::MsgUtils->message("E", { data => ["Failed to start the xCAT Python agent. Check /var/log/xcat/cluster.log for more information."] }, $callback);
        return;
    }

    xCAT::AGENT::submit_agent_request($pid, $request, "openbmc", \%node_info, $callback);
    xCAT::AGENT::wait_agent($pid, $callback);
}

my @rsp_common_options = qw/autoreboot bootmode thermalmode powersupplyredundancy powerrestorepolicy timesyncmethod
                            ip netmask gateway hostname vlan ntpservers/;
my @rspconfig_set_options = (@rsp_common_options, qw/admin_passwd/);
my %rsp_set_valid_values = (
    autoreboot            => "0|1",
    bootmode              => "regular|safe|setup",
    thermalmode           => "default|custom|heavy_io|max_base_fan_floor",
    powersupplyredundancy => "disabled|enabled",
    powerrestorepolicy    => "always_off|always_on|restore",
    timesyncmethod        => "manual|ntp",
);
my @rspconfig_get_options = (@rsp_common_options, qw/ipsrc sshcfg gard dump/);
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

    unless (GetOptions(
        'V|verbose'  => \$::VERBOSE,
    )) {
        return ([ 1, "Error parsing arguments." ]);
    }

    if (scalar(@ARGV) >= 2 and ($command =~ /rbeacon|rpower|rvitals/)) {
        return ([ 1, "Only one option is supported at the same time for $command" ]);
    } elsif (scalar(@ARGV) == 0 and $command =~ /rbeacon|rspconfig|rpower|rflash/) {
        return ([ 1, "No option specified for $command" ]);
    } else {
        $subcommand = $ARGV[0];
    }

    if ($command eq "rbeacon") {
        unless ($subcommand =~ /^on$|^off$|^stat$/) {
            return ([ 1, "Only 'on', 'off' and 'stat' are supported for OpenBMC managed nodes."]);
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
            return ([ 1, "More than one directory specified is not supported."]) if ($#ARGV >= 1);
            return ([ 1, "Invalid option specified with '-d'."]) if (!@ARGV);
        }
        if ($list) {
            return ([ 1, "Invalid option specified with '-l|--list'."]) if (@ARGV);
        }
    } elsif ($command eq "rinv") {
        if (!defined($ARGV[0])) {
            $subcommand = "all";
        } else {
            foreach my $each_subcommand (@ARGV) {
                # Check if each passed subcommand is valid
                if ($each_subcommand =~ /^all$|^cpu$|^dimm$|^firm$|^model$|^serial$/) {
                    $subcommand .= $each_subcommand . " ";
                } else {
                    # Exit once we find an invalid subcommand
                    return ([ 1, "Unsupported command: $command $each_subcommand" ]);
                }
            }
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
        my $num_subcommand = @ARGV;
        my ($set, $get);
        my $all_subcommand = "";
        my %set_net_info = ();
        foreach $subcommand (@ARGV) {
            my ($key, $value);
            if ($subcommand =~ /^(\w+)=(.*)/) {
                $key = $1;
                $value = $2;
                $set = 1;
            } else {
                $key = $subcommand;
                $get = 1;
            }
            if ($set and $get) {
                return ([1, "Can not set and query OpenBMC information at the same time"]);
            } elsif ($set and $value eq '' and ($key ne "ntpservers")) {
                return ([1, "Invalid parameter for option $key"]);
            } elsif ($set and $value ne '' and exists($rsp_set_valid_values{$key})) {
                unless ($value =~ /^($rsp_set_valid_values{$key})$/) {
                    return([1, "Invalid value '$value' for '$key', Valid values: " . join(',', split('\|',$rsp_set_valid_values{$key}))]);
                }
            }
            if (($set and !grep /$key/, @rspconfig_set_options) or
                ($get and !grep /$key/, @rspconfig_get_options)) {
                return ([1, "Unsupported command: $command $subcommand"]);
            }
            if ($set) {
                if ($key =~ /^hostname$|^admin_passwd$|^ntpservers$/ and $num_subcommand > 1) {
                    return([1, "The option '$key' can not work with other options"]);
                } elsif ($key eq "admin_passwd") {
                    if ($value =~ /^([^,]*),([^,]*)$/) {
                        if ($1 eq '' or $2 eq '') {
                            return([1, "Invalid parameter for option $key: $value"]);
                        }
                    } else {
                        return([1, "Invalid parameter for option $key: $value"]);
                    }
                } elsif ($key eq "netmask") {
                    if (!xCAT::NetworkUtils->isIpaddr($value)) {
                        return ([ 1, "Invalid parameter for option $key: $value" ]);
                    }
                    $set_net_info{"netmask"} = 1;
                } elsif ($key eq "gateway") {
                    if ($value ne "0.0.0.0" and !xCAT::NetworkUtils->isIpaddr($value)) {
                        return ([ 1, "Invalid parameter for option $key: $value" ]);
                    }
                    $set_net_info{"gateway"} = 1;
                } elsif ($key eq "vlan") {
                    $set_net_info{"vlan"} = 1;
                } elsif ($key eq "ip") {
                    if ($value ne "dhcp") {
                        if (@$noderange > 1) {
                            return ([ 1, "Can not configure more than 1 nodes' ip at the same time" ]);
                        } elsif (!xCAT::NetworkUtils->isIpaddr($value)) {
                            return ([ 1, "Invalid parameter for option $key: $value" ]);
                        }
                        $set_net_info{"ip"} = 1;
                    } elsif($num_subcommand > 1) {
                        return ([ 1, "Setting ip=dhcp must be issued without other options." ]);
                    }
                }
            } else {
                if ($key eq "sshcfg" and $num_subcommand > 1) {
                    return ([ 1, "Configure sshcfg must be issued without other options." ]);
                } elsif ($key eq "gard") {
                    if ($num_subcommand > 2) {
                        return  ([ 1, "Clear GARD cannot be issued with other options." ]);
                    } elsif (!defined($ARGV[1]) or $ARGV[1] !~ /^-c$|^--clear$/) {
                        return ([ 1, "Invalid parameter for $command $key" ]);
                    }
                    return;
                } elsif ($key eq "dump") {
                    my $dump_option = "";
                    $dump_option = $ARGV[1] if (defined $ARGV[1]);
                    if ($dump_option =~ /^-d$|^--download$/) {
                        return ([ 1, "No dump file ID specified" ]) unless ($ARGV[2]);
                        return ([ 1, "Invalid parameter for $command $key $dump_option $ARGV[2]" ]) if ($ARGV[2] !~ /^\d*$/ and $ARGV[2] ne "all");
                        return ([ 1, "dump $dump_option must be issued without other options." ]) if ($num_subcommand > 3);
                    } elsif ($dump_option =~ /^-c$|^--clear$/) {
                        return ([ 1, "No dump file ID specified. To clear all, specify 'all'." ]) unless ($ARGV[2]);
                        return ([ 1, "Invalid parameter for $command $key $dump_option $ARGV[2]" ]) if ($ARGV[2] !~ /^\d*$/ and $ARGV[2] ne "all");
                        return ([ 1, "dump $dump_option must be issued without other options." ]) if ($num_subcommand > 3);
                    } elsif ($dump_option =~ /^-l$|^--list$|^-g$|^--generate$/) {
                        return ([ 1, "dump $dump_option must be issued without other options." ]) if ($num_subcommand > 2);
                    } elsif ($dump_option) {
                        return ([ 1, "Invalid parameter for $command $dump_option" ]);
                    }
                    return;
                }
            }
        }
        if ($set and scalar(keys %set_net_info) > 0) {
            if (!exists($set_net_info{"ip"}) or !exists($set_net_info{"netmask"}) or !exists($set_net_info{"gateway"})) {
                if (exists($set_net_info{"vlan"})) {
                    return ([ 1, "VLAN must be configured with IP, netmask and gateway" ]);
                } else {
                    return ([ 1, "IP, netmask and gateway must be configured together." ]);
                }
            }

        }
    } elsif ($command eq "reventlog") {
        $subcommand = "all" if (!defined($ARGV[0]));
        if (scalar(@ARGV) >= 2) {
            if ($ARGV[1] =~ /^-s$/) {
                return ([ 1, "The -s option is not supported for OpenBMC." ]);
            }
            return ([ 1, "Only one option is supported at the same time for $command" ]);
        } elsif ($subcommand =~ /^resolved=(.*)/) {
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
        if ((!defined($extrargs->[0])) or ($extrargs->[0] =~ /^-V/)) {
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
    if ($command eq "rflash") {
        my @new_args = ('') x 4;
        foreach my $tmp (@$extrargs) {
            if ($tmp =~ /^-/) {
                if ($tmp !~ /^-V$|^--verbose$/) {
                    $new_args[0] = $tmp;
                } elsif ($tmp =~ /^--no-host-reboot$/) {
                    $new_args[2] = $tmp;
                } else {
                    $new_args[3] = $tmp;
                }
            } else {
                $new_args[1] = $tmp;
            }
        }
        @$extrargs = grep(/.+/, @new_args);
    }
    return 0;
}

1;
