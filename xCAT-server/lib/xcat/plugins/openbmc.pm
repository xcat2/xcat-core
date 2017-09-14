#!/usr/bin/perl
## IBM(c) 2017 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT_plugin::openbmc;

BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
    my $async_path = "/usr/local/share/perl5/";
    unless (grep { $_ eq $async_path } @INC) {
        push @INC, $async_path;
    }
}
use lib "$::XCATROOT/lib/perl";
use strict;
use warnings "all";

use JSON;
use HTTP::Async;
use HTTP::Cookies;
use File::Basename;
use File::Spec;
use Data::Dumper;
use Getopt::Long;
use xCAT::OPENBMC;
use xCAT::Utils;
use xCAT::Table;
use xCAT::Usage;
use xCAT::SvrUtils;
use xCAT::GlobalDef;
use xCAT_monitoring::monitorctrl;

$::VERBOSE                  = 0;
# String constants for rbeacon states
$::BEACON_STATE_OFF         = "off";
$::BEACON_STATE_ON          = "on";
# String constants for rpower states
$::POWER_STATE_OFF          = "off";
$::POWER_STATE_ON           = "on";
$::POWER_STATE_POWERING_OFF = "powering-off";
$::POWER_STATE_POWERING_ON  = "powering-on";
$::POWER_STATE_QUIESCED     = "quiesced";
$::POWER_STATE_RESET        = "reset";
$::POWER_STATE_REBOOT       = "reboot";
$::UPLOAD_FILE              = "";
$::UPLOAD_FILE_VERSION      = "";

$::NO_ATTRIBUTES_RETURNED   = "No attributes returned from the BMC.";

sub unsupported {
    my $callback = shift;
    if (defined($::OPENBMC_DEVEL) && ($::OPENBMC_DEVEL eq "YES")) {
        return;
    } else {
        return ([ 1, "This openbmc related function is not yet supported. Please contact xCAT development team." ]);
    }
}

#-------------------------------------------------------

=head3  handled_commands

  Return list of commands handled by this plugin

=cut

#-------------------------------------------------------
sub handled_commands {
    return {
        getopenbmccons => 'nodehm:cons',
        rbeacon        => 'nodehm:mgt',
        renergy        => 'nodehm:mgt',
        reventlog      => 'nodehm:mgt',
        rflash         => 'nodehm:mgt',
        rinv           => 'nodehm:mgt',
        rpower         => 'nodehm:mgt',
        rsetboot       => 'nodehm:mgt',
        rspconfig      => 'nodehm:mgt',
        rspreset       => 'nodehm:mgt',
        rvitals        => 'nodehm:mgt',
    };
}

my $prefix = "xyz.openbmc_project";

my %sensor_units = (
    "$prefix.Sensor.Value.Unit.DegreesC" => "C",
    "$prefix.Sensor.Value.Unit.RPMS" => "RPMS",
    "$prefix.Sensor.Value.Unit.Volts" => "Volts",
    "$prefix.Sensor.Value.Unit.Meters" => "Meters",
    "$prefix.Sensor.Value.Unit.Amperes" => "Amps",
    "$prefix.Sensor.Value.Unit.Watts" => "Watts",
    "$prefix.Sensor.Value.Unit.Joules" => "Joules"
); 

my $http_protocol="https";
my $openbmc_url = "/org/openbmc";
my $openbmc_project_url = "/xyz/openbmc_project";
#-------------------------------------------------------

# The hash table to store method and url for request, 
# process function for response 

#-------------------------------------------------------
my %status_info = (
    LOGIN_REQUEST      => {
        method         => "POST",
        init_url       => "/login",
    },
    LOGIN_RESPONSE     => {
        process        => \&login_response,
    },

    RBEACON_ON_REQUEST  => {
        method         => "PUT",
        init_url       => "$openbmc_project_url/led/groups/enclosure_identify/attr/Asserted", 
        data           => "true",
    },
    RBEACON_ON_RESPONSE => {
        process        => \&rbeacon_response,
    },
    RBEACON_OFF_REQUEST  => {
        method         => "PUT",
        init_url       => "$openbmc_project_url/led/groups/enclosure_identify/attr/Asserted",
        data           => "false",
    },
    RBEACON_OFF_RESPONSE => {
        process        => \&rbeacon_response,
    },

    REVENTLOG_REQUEST => {
        method         => "GET",
        init_url       => "$openbmc_project_url/logging/enumerate",
    },
    REVENTLOG_RESPONSE => {
        process        => \&reventlog_response,
    },
    REVENTLOG_CLEAR_REQUEST => {
        method         => "POST",
        init_url       => "$openbmc_project_url/logging//action/delete",
        data           => '{ "data": [] }',
    },
    REVENTLOG_CLEAR_RESPONSE => {
        process        => \&reventlog_response,
    },

    RFLASH_LIST_REQUEST  => {
        method         => "GET",
        init_url       => "$openbmc_project_url/software/enumerate",
    },
    RFLASH_LIST_RESPONSE => {
        process        => \&rflash_response,
    },
    RFLASH_FILE_UPLOAD_REQUEST  => {
        method         => "PUT",
        init_url       => "$openbmc_project_url/upload/image/",
    },
    RFLASH_FILE_UPLOAD_RESPONSE => {
        process        => \&rflash_response,
    },
    RFLASH_UPDATE_ACTIVATE_REQUEST  => {
        method         => "PUT",
        init_url       => "$openbmc_project_url/software",
        data           => "xyz.openbmc_project.Software.Activation.RequestedActivations.Active",
    },
    RFLASH_UPDATE_ACTIVATE_RESPONSE => {
        process        => \&rflash_response,
    },
    RFLASH_UPDATE_CHECK_STATE_REQUEST  => {
        method         => "GET",
        init_url       => "$openbmc_project_url/software",
    },
    RFLASH_UPDATE_CHECK_STATE_RESPONSE => {
        process        => \&rflash_response,
    },
    RFLASH_UPDATE_CHECK_ID_REQUEST  => {
        method         => "GET",
        init_url       => "$openbmc_project_url/software/enumerate",
    },
    RFLASH_UPDATE_CHECK_ID_RESPONSE => {
        process        => \&rflash_response,
    },
    RFLASH_SET_PRIORITY_REQUEST  => {
        method         => "PUT",
        init_url       => "$openbmc_project_url/software",
        data           => "false", # Priority state of 0 sets image to active
    },
    RFLASH_SET_PRIORITY_RESPONSE => {
        process        => \&rflash_response,
    },
    RFLASH_DELETE_IMAGE_REQUEST  => {
        method         => "POST",
        init_url       => "$openbmc_project_url/software",
        data           => "[]",
    },
    RFLASH_DELETE_IMAGE_RESPONSE => {
        process        => \&rflash_response,
    },

    RINV_REQUEST => {
        method         => "GET",
        init_url       => "$openbmc_project_url/inventory/enumerate",
    },
    RINV_RESPONSE => {
        process        => \&rinv_response,
    },

    RINV_FIRM_REQUEST => {
        method         => "GET",
        init_url       => "$openbmc_project_url/software/enumerate",
    },
    RINV_FIRM_RESPONSE => {
        process        => \&rinv_response,
    },

    RPOWER_BMCREBOOT_REQUEST  => {
        method         => "PUT",
        init_url       => "$openbmc_project_url/state/bmc0/attr/RequestedBMCTransition",
        data           => "xyz.openbmc_project.State.BMC.Transition.Reboot",
    },
    RPOWER_ON_REQUEST  => {
        method         => "PUT",
        init_url       => "$openbmc_project_url/state/host0/attr/RequestedHostTransition",
        data           => "xyz.openbmc_project.State.Host.Transition.On",
    },
    RPOWER_ON_RESPONSE => {
        process        => \&rpower_response,
    },
    RPOWER_OFF_REQUEST  => {
        method         => "PUT",
        init_url       => "$openbmc_project_url/state/chassis0/attr/RequestedPowerTransition",
        data           => "xyz.openbmc_project.State.Chassis.Transition.Off",
    },
    RPOWER_OFF_RESPONSE => {
        process        => \&rpower_response,
    },
    RPOWER_SOFTOFF_REQUEST  => {
        method         => "PUT",
        init_url       => "$openbmc_project_url/state/host0/attr/RequestedHostTransition",
        data           => "xyz.openbmc_project.State.Host.Transition.Off",
    },
    RPOWER_RESET_REQUEST  => {
        method         => "PUT",
        init_url       => "$openbmc_project_url/state/host0/attr/RequestedHostTransition",
        data           => "xyz.openbmc_project.State.Host.Transition.Reboot",
    },
    RPOWER_RESET_RESPONSE => {
        process        => \&rpower_response,
    },
    RPOWER_STATUS_REQUEST  => {
        method         => "GET",
        init_url       => "$openbmc_project_url/state/enumerate",
    },
    RPOWER_STATUS_RESPONSE => {
        process        => \&rpower_response,
    },

    RSETBOOT_SET_REQUEST => {
        method         => "PUT",
        init_url       => "$openbmc_project_url/control/host0/boot_source/attr/BootSource",
        data           => "xyz.openbmc_project.Control.Boot.Source.Sources.",
    },
    RSETBOOT_SET_RESPONSE => {
        process        => \&rsetboot_response,
    },
    RSETBOOT_STATUS_REQUEST  => {
        method         => "GET",
        init_url       => "$openbmc_project_url/control/host0/boot_source",
    },
    RSETBOOT_STATUS_RESPONSE => {
        process        => \&rsetboot_response,
    },

    RSPCONFIG_GET_REQUEST => {
        method         => "GET",
        init_url       => "$openbmc_project_url/network/enumerate",
    },
    RSPCONFIG_GET_RESPONSE => {
        process        => \&rspconfig_response,
    },
    RSPCONFIG_SET_REQUEST => {
        method         => "PUT",
        init_url       => "$openbmc_project_url/network",
        data           => "[]",
    },
    RSPCONFIG_SET_RESPONSE => {
        process        => \&rspconfig_response,
    },
    RSPCONFIG_DHCP_REQUEST => {
        method         => "POST",
        init_url       => "$openbmc_project_url/network/action/Reset",
        data           => "[]",
    },
    RSPCONFIG_DHCP_RESPONSE => {
        process        => \&rspconfig_response,
    },
    RSPCONFIG_SSHCFG_REQUEST => {
        method         => "GET",
        init_url       => "",
    },
    RSPCONFIG_SSHCFG_RESPONSE => {
        process        => \&rspconfig_sshcfg_response,
    },
    RVITALS_REQUEST => {
        method         => "GET",
        init_url       => "$openbmc_project_url/sensors/enumerate",
    },
    RVITALS_RESPONSE => {
        process        => \&rvitals_response,
    },
);

$::RESPONSE_OK                  = "200 OK";
$::RESPONSE_SERVER_ERROR        = "500 Internal Server Error";
$::RESPONSE_SERVICE_UNAVAILABLE = "503 Service Unavailable";
$::RESPONSE_FORBIDDEN           = "403 Forbidden";
$::RESPONSE_METHOD_NOT_ALLOWED  = "405 Method Not Allowed";
$::RESPONSE_SERVICE_TIMEOUT     = "504 Gateway Timeout";

#-----------------------------

=head3 %node_info

  $node_info = (
      $node => {
          bmc        => "x.x.x.x",
          username   => "username",
          password   => "password",
          cur_status => "LOGIN_REQUEST",
          cur_url    => "",
          method     => "",
      },
  );

  'cur_url', 'method' used for path has a trailing-slash

=cut

#-----------------------------
my %node_info = ();

my %next_status = ();

my %handle_id_node = ();

my $wait_node_num;

my $async;

my $cookie_jar;

my $callback;

my %allerrornodes = ();

my $xcatdebugmode = 0;

my $flag_debug = "[openbmc_debug]";

#-------------------------------------------------------

=head3  preprocess_request

  preprocess the command

=cut

#-------------------------------------------------------
sub preprocess_request {
    my $request = shift;
    if (defined $request->{_xcatpreprocessed}->[0] and $request->{_xcatpreprocessed}->[0] == 1) {
        return [$request];
    }

    ##############################################
    # Delete this when could be released

    if (ref($request->{environment}) eq 'ARRAY' and ref($request->{environment}->[0]->{XCAT_OPENBMC_DEVEL}) eq 'ARRAY') {
        $::OPENBMC_DEVEL = $request->{environment}->[0]->{XCAT_OPENBMC_DEVEL}->[0];
    } elsif (ref($request->{environment}) eq 'ARRAY') {
        $::OPENBMC_DEVEL = $request->{environment}->[0]->{XCAT_OPENBMC_DEVEL};
    } else {
        $::OPENBMC_DEVEL = $request->{environment}->{XCAT_OPENBMC_DEVEL};
    }
    ##############################################

    $callback  = shift;

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
        $callback->({ errorcode => [$parse_result->[0]], data => [$parse_result->[1]] });
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
    my $command   = $request->{command}->[0];
    my $noderange = $request->{node};
    my $extrargs       = $request->{arg};
    $::cwd = $request->{cwd}->[0];
    my @exargs         = ($request->{arg});
    if (ref($extrargs)) {
        @exargs = @$extrargs;
    }

    if ($::XCATSITEVALS{xcatdebugmode}) { $xcatdebugmode = $::XCATSITEVALS{xcatdebugmode} }

    my $check = parse_node_info($noderange);
    my $rst = parse_command_status($command, \@exargs);
    return if ($rst);

    if ($request->{command}->[0] ne "getopenbmccons") {
        $cookie_jar = HTTP::Cookies->new({});
        $async = HTTP::Async->new(
            slots => 500,
            cookie_jar => $cookie_jar,
            timeout => 60,
            max_request_time => 60,
            ssl_options => {
                SSL_verify_mode => 0,
            },
        );    
    }

    my $bmcip;
    my $login_url;
    my $handle_id;
    my $content;
    $wait_node_num = keys %node_info;
    my @donargs = ();

    foreach my $node (keys %node_info) {
        $bmcip = $node_info{$node}{bmc};

        if ($request->{command}->[0] eq "getopenbmccons") {
            push @donargs, [ $node,$bmcip,$node_info{$node}{username}, $node_info{$node}{password}];
        } else {
            $login_url = "$http_protocol://$bmcip/login";
            $content = '{ "data": [ "' . $node_info{$node}{username} .'", "' . $node_info{$node}{password} . '" ] }';
            $handle_id = xCAT::OPENBMC->new($async, $login_url, $content); 
            $handle_id_node{$handle_id} = $node;
            $node_info{$node}{cur_status} = $next_status{ $node_info{$node}{cur_status} };
            if ($xcatdebugmode) {
                my $debug_info = "curl -k -c cjar -H \"Content-Type: application/json\" -d '{ \"data\": [\"$node_info{$node}{username}\", \"xxxxxx\"] }' $login_url";
                process_debug_info($node, $debug_info);
            }
        }
    }  

    #process rcons
    if ($request->{command}->[0] eq "getopenbmccons") {
        foreach (@donargs) {
            getopenbmccons($_, $callback);
        }
        return;
    }

    while (1) { 
        last unless ($wait_node_num);
        while (my ($response, $handle_id) = $async->wait_for_next_response) {
            deal_with_response($handle_id, $response);
        }
    } 

    $callback->({ errorcode => [$check] }) if ($check);
    return;
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
    my $check = undef;
    my $subcommand = undef;
    my $verbose    = undef;
    unless (GetOptions(
        'V|verbose'  => \$verbose,
    )) {
        return ([ 1, "Error parsing arguments." ]);
    }

    # If command includes '-V', it must be the last one prarmeter. Or print error message.
    if ($verbose) {
        my $option = $$extrargs[-1];
        return ([ 1, "Error parsing arguments." ]) if ($option !~ /V|verbose/);
    }

    if (scalar(@ARGV) >= 2 and ($command =~ /rpower|rinv|rsetboot|rvitals/)) {
        return ([ 1, "Only one option is supported at the same time for $command" ]);
    } elsif (scalar(@ARGV) == 0 and $command =~ /rpower|rspconfig|rflash/) {
        return ([ 1, "No option specified for $command" ]);
    } else { 
        $subcommand = $ARGV[0];
    }

    if ($command eq "rbeacon") { 
        unless ($subcommand =~ /^on$|^off$/) {
	    return ([ 1, "Unsupported command: $command $subcommand" ]);
        }
    } elsif ($command eq "rpower") {
        unless ($subcommand =~ /^on$|^off$|^softoff$|^reset$|^boot$|^bmcreboot$|^bmcstate$|^status$|^stat$|^state$/) {
            return ([ 1, "Unsupported command: $command $subcommand" ]);
        }
    } elsif ($command eq "rinv") {
        $subcommand = "all" if (!defined($ARGV[0]));
        unless ($subcommand =~ /^model$|^serial$|^firm$|^cpu$|^dimm$|^all$/) {
            return ([ 1, "Unsupported command: $command $subcommand" ]);
        }
    } elsif ($command eq "getopenbmccons") {
        # command for openbmc rcons
    } elsif ($command eq "rsetboot") {
        $subcommand = "stat" if (!defined($ARGV[0]));
        unless ($subcommand =~ /^net$|^hd$|^cd$|^def$|^default$|^stat$/) {
            return ([ 1, "Unsupported command: $command $subcommand" ]);
        }
    } elsif ($command eq "reventlog") {
        my $option_s = 0;
        unless (GetOptions("s" => \$option_s,)) {
            return ([1, "Error parsing arguments." ]);
        }
        $subcommand = "all" if (!defined($ARGV[0]));
        unless ($subcommand =~ /^\d$|^\d+$|^all$|^clear$/) {
            return ([ 1, "Unsupported command: $command $subcommand" ]);
        }
    } elsif ($command eq "rspconfig") {
        my $setorget;
        foreach $subcommand (@ARGV) {
            if ($subcommand =~ /^(\w+)=(.*)/) {
                return ([ 1, "Can not configure and display nodes' value at the same time" ]) if ($setorget and $setorget eq "get");
                my $key = $1;
                my $value = $2;
                return ([ 1, "Unsupported command: $command $key" ]) unless ($key =~ /^ip$|^netmask$|^gateway$|^hostname$|^vlan$/);

                my $nodes_num = @$noderange;
                return ([ 1, "Invalid parameter for option $key" ]) unless ($value);
                return ([ 1, "Invalid parameter for option $key: $value" ]) if ($key =~ /^netmask$|^gateway$/ and !xCAT::NetworkUtils->isIpaddr($value));
                if ($key eq "ip") {
                    return ([ 1, "Can not configure more than 1 nodes' ip at the same time" ]) if ($nodes_num >= 2 and $value ne "dhcp");
                    if ($value ne "dhcp" and !xCAT::NetworkUtils->isIpaddr($value)) {
                        return ([ 1, "Invalid parameter for option $key: $value" ]);
                    }
                }
                $setorget = "set";
                #
                # disable function until fully tested
                #
                unless (($key eq "ip" and $value eq "dhcp") or $key eq "hostname") {
                    $check = unsupported($callback); if (ref($check) eq "ARRAY") { return $check; }
                }
            } elsif ($subcommand =~ /^ip$|^netmask$|^gateway$|^hostname$|^vlan$/) {
                return ([ 1, "Can not configure and display nodes' value at the same time" ]) if ($setorget and $setorget eq "set");
                $setorget = "get";
            } elsif ($subcommand =~ /^sshcfg$/) {
                $setorget = ""; # SSH Keys are copied using a RShellAPI, not REST API
            } else {
                return ([ 1, "Unsupported command: $command $subcommand" ]);
            }
        }  
    } elsif ($command eq "rvitals") {
        $subcommand = "all" if (!defined($ARGV[0]));
        unless ($subcommand =~ /^temp$|^voltage$|^wattage$|^fanspeed$|^power$|^altitude$|^all$/) {
            return ([ 1, "Unsupported command: $command $subcommand" ]);
        }
    } elsif ($command eq "rflash") {
        my $filename_passed = 0;
        my $updateid_passed = 0;
        my $option_flag;
        foreach my $opt (@$extrargs) {
            # Only files ending on .tar are allowed
            if ($opt =~ /.*\.tar$/i) {
                $filename_passed = 1;
                next;
            }
            # Check if hex number for the updateid is passed
            if ($opt =~ /^[[:xdigit:]]+$/i) {
                $updateid_passed = 1;
                next;
            }
            # check if option starting with - was passed
            if ($opt =~ /^-/) {
                $option_flag = $opt;
            }
        }
        if ($filename_passed) {
            # Filename was passed, check flags allowed with file
            if ($option_flag !~ /^-c$|^--check$|^-u$|^--upload$|^-a$|^--activate$/) {
                return ([ 1, "Invalid option specified when a file is provided: $option_flag" ]);
            }
        }
        else {
            if ($updateid_passed) {
                # Updateid was passed, check flags allowed with update id
                if ($option_flag !~ /^^-d$|^--delete$|^-a$|^--activate$/) {
                    return ([ 1, "Invalid option specified when an update id is provided: $option_flag" ]);
                }
            }
            else {
                # Neither Filename nor updateid was not passed, check flags allowed without file or updateid
                if ($option_flag !~ /^-c$|^--check$|^-l$|^--list/) {
                    return ([ 1, "Invalid option specified: $option_flag" ]);
               }
            }  
        }
    } else {
        return ([ 1, "Command is not supported." ]);
    }

    return;
}

#-------------------------------------------------------

=head3  parse_command_status

  Parse the command to init status machine

=cut

#-------------------------------------------------------
sub parse_command_status {
    my $command     = shift;
    my $subcommands = shift;
    my $subcommand;

    if ($$subcommands[-1] and $$subcommands[-1] =~ /V|verbose/) {
        $::VERBOSE = 1;
        pop(@$subcommands);
    }

    $next_status{LOGIN_REQUEST} = "LOGIN_RESPONSE";

    if ($command eq "rbeacon") { 
        $subcommand = $$subcommands[0];

        if ($subcommand eq "on") {
            $next_status{LOGIN_RESPONSE} = "RBEACON_ON_REQUEST";
            $next_status{RBEACON_ON_REQUEST} = "RBEACON_ON_RESPONSE";
        } elsif ($subcommand eq "off") {
            $next_status{LOGIN_RESPONSE} = "RBEACON_OFF_REQUEST";
            $next_status{RBEACON_OFF_REQUEST} = "RBEACON_OFF_RESPONSE";
        }
    }

    if ($command eq "rpower") {
        $subcommand = $$subcommands[0];

        if ($subcommand eq "on") {
            $next_status{LOGIN_RESPONSE} = "RPOWER_ON_REQUEST";
            $next_status{RPOWER_ON_REQUEST} = "RPOWER_ON_RESPONSE";
        } elsif ($subcommand eq "off") {
            $next_status{LOGIN_RESPONSE} = "RPOWER_OFF_REQUEST";
            $next_status{RPOWER_OFF_REQUEST} = "RPOWER_OFF_RESPONSE";
        } elsif ($subcommand eq "softoff") {
            $next_status{LOGIN_RESPONSE} = "RPOWER_SOFTOFF_REQUEST";
            $next_status{RPOWER_SOFTOFF_REQUEST} = "RPOWER_OFF_RESPONSE";
        } elsif ($subcommand eq "reset") {
            $next_status{LOGIN_RESPONSE} = "RPOWER_RESET_REQUEST";
            $next_status{RPOWER_RESET_REQUEST} = "RPOWER_RESET_RESPONSE";
        } elsif ($subcommand =~ /^bmcstate$|^status$|^state$|^stat$/) {
            $next_status{LOGIN_RESPONSE} = "RPOWER_STATUS_REQUEST";
            $next_status{RPOWER_STATUS_REQUEST} = "RPOWER_STATUS_RESPONSE";
            $status_info{RPOWER_STATUS_RESPONSE}{argv} = "$subcommand";
        } elsif ($subcommand eq "boot") {
            $next_status{LOGIN_RESPONSE} = "RPOWER_STATUS_REQUEST";
            $next_status{RPOWER_STATUS_REQUEST} = "RPOWER_STATUS_RESPONSE";
            $next_status{RPOWER_STATUS_RESPONSE}{OFF} = "RPOWER_ON_REQUEST";
            $next_status{RPOWER_ON_REQUEST} = "RPOWER_ON_RESPONSE";
            $next_status{RPOWER_STATUS_RESPONSE}{ON} = "RPOWER_RESET_REQUEST";
            $next_status{RPOWER_RESET_REQUEST} = "RPOWER_RESET_RESPONSE";
        } elsif ($subcommand eq "bmcreboot") {
            $next_status{LOGIN_RESPONSE} = "RPOWER_BMCREBOOT_REQUEST";
            $next_status{RPOWER_BMCREBOOT_REQUEST} = "RPOWER_RESET_RESPONSE";
            $status_info{RPOWER_RESET_RESPONSE}{argv} = "$subcommand";
        }
    } 

    if ($command eq "rinv") {
        if (defined($$subcommands[0])) {
            $subcommand = $$subcommands[0];
        } else {
            $subcommand = "all";
        }

        if ($subcommand eq "firm") {
            $next_status{LOGIN_RESPONSE} = "RINV_FIRM_REQUEST";
            $next_status{RINV_FIRM_REQUEST} = "RINV_FIRM_RESPONSE";
        } elsif ($subcommand eq "all") {
            $next_status{LOGIN_RESPONSE} = "RINV_REQUEST";
            $next_status{RINV_REQUEST} = "RINV_RESPONSE";
            $status_info{RINV_RESPONSE}{argv} = "$subcommand";
            $next_status{RINV_RESPONSE} = "RINV_FIRM_REQUEST";
            $next_status{RINV_FIRM_REQUEST} = "RINV_FIRM_RESPONSE";
        } else {
            $next_status{LOGIN_RESPONSE} = "RINV_REQUEST";
            $next_status{RINV_REQUEST} = "RINV_RESPONSE";
            $status_info{RINV_RESPONSE}{argv} = "$subcommand";
        }
    }

    if ($command eq "rsetboot") {
        if (defined($$subcommands[0])) {
            $subcommand = $$subcommands[0];
        } else {
            $subcommand = "stat";
        }
        if ($subcommand =~ /^hd$|^net$|^cd$|^default$|^def$/) {
            $next_status{LOGIN_RESPONSE} = "RSETBOOT_SET_REQUEST";
            $next_status{RSETBOOT_SET_REQUEST} = "RSETBOOT_SET_RESPONSE";
            if ($subcommand eq "net") {
                $status_info{RSETBOOT_SET_REQUEST}{data} .= "Network";
            } elsif ($subcommand eq "hd") {
                $status_info{RSETBOOT_SET_REQUEST}{data} .= "Disk";
            } elsif ($subcommand eq "cd") {
                $status_info{RSETBOOT_SET_REQUEST}{data} .= "ExternalMedia";
            } elsif ($subcommand eq "def" or $subcommand eq "default") {
                $status_info{RSETBOOT_SET_REQUEST}{data} .= "Default";
            }
            $next_status{RSETBOOT_SET_RESPONSE} = "RSETBOOT_STATUS_REQUEST";
            $next_status{RSETBOOT_STATUS_REQUEST} = "RSETBOOT_STATUS_RESPONSE";
        } elsif ($subcommand eq "stat") {
            $next_status{LOGIN_RESPONSE} = "RSETBOOT_STATUS_REQUEST";
            $next_status{RSETBOOT_STATUS_REQUEST} = "RSETBOOT_STATUS_RESPONSE";
        }
    }

    if ($command eq "reventlog") {
        my $option_s = 0;
        if ($$subcommands[-1] and $$subcommands[-1] eq "-s") {
            $option_s = 1; 
            pop(@$subcommands);
        }

        if (defined($$subcommands[0])) {
            $subcommand = $$subcommands[0];
        } else {
            $subcommand = "all";
        }

        if ($subcommand eq "clear") {
            $next_status{LOGIN_RESPONSE} = "REVENTLOG_CLEAR_REQUEST";
            $next_status{REVENTLOG_CLEAR_REQUEST} = "REVENTLOG_CLEAR_RESPONSE";
            xCAT::SvrUtils::sendmsg("Command $command is not available now!", $callback);
            return 1;
        } else {
            $next_status{LOGIN_RESPONSE} = "REVENTLOG_REQUEST";
            $next_status{REVENTLOG_REQUEST} = "REVENTLOG_RESPONSE";
            $status_info{REVENTLOG_RESPONSE}{argv} = "$subcommand";
            $status_info{REVENTLOG_RESPONSE}{argv} .= ",s" if ($option_s);
        }
    }

    if ($command eq "rspconfig") {
        my @options = ();
        foreach $subcommand (@$subcommands) {
            if ($subcommand =~ /^ip$|^netmask$|^gateway$|^hostname$|^vlan$/) {
                $next_status{LOGIN_RESPONSE} = "RSPCONFIG_GET_REQUEST";
                $next_status{RSPCONFIG_GET_REQUEST} = "RSPCONFIG_GET_RESPONSE";
                push @options, $subcommand;
            } elsif ($subcommand =~ /^sshcfg$/) {
                # Special processing to copy ssh keys, currently there is no REST API to do this.
                # Instead, copy ssh key file to the BMC in function specified by RSPCONFIG_SSHCFG_RESPONSE
                $next_status{LOGIN_RESPONSE} = "RSPCONFIG_SSHCFG_REQUEST";
                $next_status{RSPCONFIG_SSHCFG_REQUEST} = "RSPCONFIG_SSHCFG_RESPONSE";
                push @options, $subcommand;
                return 0;
            } elsif ($subcommand =~ /^(\w+)=(.+)/) {
                my $key   = $1;
                my $value = $2;
                if ($key eq "ip" and $value eq "dhcp") {
                    $next_status{LOGIN_RESPONSE} = "RSPCONFIG_DHCP_REQUEST";
                    $next_status{RSPCONFIG_DHCP_REQUEST} = "RSPCONFIG_DHCP_RESPONSE";
                    $next_status{RSPCONFIG_DHCP_RESPONSE} = "RPOWER_BMCREBOOT_REQUEST";
                    $next_status{RPOWER_BMCREBOOT_REQUEST} = "RPOWER_RESET_RESPONSE";
                    $status_info{RPOWER_RESET_RESPONSE}{argv} = "bmcreboot";
                } elsif ($key =~ /^hostname$/) {
                    $next_status{LOGIN_RESPONSE} = "RSPCONFIG_SET_REQUEST";
                    $next_status{RSPCONFIG_SET_REQUEST} = "RSPCONFIG_SET_RESPONSE";
                    $next_status{RSPCONFIG_SET_RESPONSE} = "RSPCONFIG_GET_REQUEST";
                    $next_status{RSPCONFIG_GET_REQUEST} = "RSPCONFIG_GET_RESPONSE";

                    $status_info{RSPCONFIG_SET_REQUEST}{data} = "$value"; 
                    $status_info{RSPCONFIG_SET_REQUEST}{init_url} .= "/config/attr/HostName";
                    push @options, $key;
                    
                } else {
                    $next_status{LOGIN_RESPONSE} = "RSPCONFIG_SET_REQUEST";
                    $next_status{RSPCONFIG_SET_REQUEST} = "RSPCONFIG_SET_RESPONSE";
                    $next_status{RSPCONFIG_SET_RESPONSE} = "RSPCONFIG_GET_REQUEST";
                    $next_status{RSPCONFIG_GET_REQUEST} = "RSPCONFIG_GET_RESPONSE";
                    if ($key eq "ip") {
                        $status_info{RSPCONFIG_SET_RESPONSE}{ip}  = $value;
                    }
                    $status_info{RSPCONFIG_SET_REQUEST}{data} = ""; # wait for interface, ip/netmask/gateway is $value
                    push @options, $key;
                }
            }
        }
        $status_info{RSPCONFIG_GET_RESPONSE}{argv} = join(",", @options);
    }

    if ($command eq "rvitals") {
        if (defined($$subcommands[0])) {
            $subcommand = $$subcommands[0];
        } else {
            $subcommand = "all";
        }

        $next_status{LOGIN_RESPONSE} = "RVITALS_REQUEST";
        $next_status{RVITALS_REQUEST} = "RVITALS_RESPONSE";
        $status_info{RVITALS_RESPONSE}{argv} = "$subcommand";
    }

    if ($command eq "rflash") {
        my $check_version = 0;
        my $list = 0;
        my $delete = 0;
        my $upload = 0;
        my $activate = 0;
        my $update_file;
        my $upload_and_activate = 0;

        foreach $subcommand (@$subcommands) {
            if ($subcommand =~ /-c|--check/) {
                $check_version = 1;
            } elsif ($subcommand =~ /-l|--list/) {
                $list = 1;
            } elsif ($subcommand =~ /-d|--delete/) {
                $delete = 1;
            } elsif ($subcommand =~ /-u|--upload/) {
                $upload = 1;
            } elsif ($subcommand =~ /-a|--activate/) {
                $activate = 1;
            } else {
                $update_file = $subcommand;
            }
        }

        my $file_id = undef;
        my $grep_cmd = "/usr/bin/grep -a";
        my $version_tag = '"^version="';
        my $purpose_tag = '"purpose="';
        my $purpose_value;
        my $version_value;
        if (defined $update_file) {
            # Filename or file id was specified 
            if ($update_file =~ /.*\.tar$/) {
                # Filename ending on .tar was specified
                if (File::Spec->file_name_is_absolute($update_file)) {
                    $::UPLOAD_FILE = $update_file;
                }
                else {
                    # If relative file path was given, convert it to absolute
                    $::UPLOAD_FILE = xCAT::Utils->full_path($update_file, $::cwd);
                }
                # Verify file exists and is readable
                unless (-r $::UPLOAD_FILE) {
                    xCAT::SvrUtils::sendmsg([1,"Cannot access $::UPLOAD_FILE"], $callback);
                    return 1;
                }
                if ($activate) {
                    # Activate flag was specified together with a update file. We want to
                    # upload the file and activate it.
                    $upload_and_activate = 1;
                    $activate = 0;
                }

                if ($check_version | $upload_and_activate) {
                    # Extract Host version for the update file
                    my $firmware_version_in_file = `$grep_cmd $version_tag $::UPLOAD_FILE`;
                    my $purpose_version_in_file = `$grep_cmd $purpose_tag $::UPLOAD_FILE`;
                    chomp($firmware_version_in_file);
                    chomp($purpose_version_in_file);
                    (my $purpose_string,$purpose_value) = split("=", $purpose_version_in_file); 
                    (my $version_string,$version_value) = split("=", $firmware_version_in_file); 
                    if ($purpose_value =~ /host/) {
                        $purpose_value = "Host";
                    } 
                    $::UPLOAD_FILE_VERSION = $version_value;
                }

                if ($check_version) {
                    # Display firmware version of the specified .tar file
                    xCAT::SvrUtils::sendmsg("TAR $purpose_value Firmware Product Version\: $version_value", $callback);
                }
            }
            else {
                # Check if hex number for the updateid is passed
                if ($update_file =~ /^[[:xdigit:]]+$/i) {
                    # Update init_url to include the id of the update
                    $status_info{RFLASH_UPDATE_ACTIVATE_REQUEST}{init_url}    .= "/$update_file/attr/RequestedActivation";
                    $status_info{RFLASH_SET_PRIORITY_REQUEST}{init_url}       .= "/$update_file/attr/Priority";
                    $status_info{RFLASH_UPDATE_CHECK_STATE_REQUEST}{init_url} .= "/$update_file";
                    $status_info{RFLASH_DELETE_IMAGE_REQUEST}{init_url}       .= "/$update_file/action/Delete";
                }
            }
        }
        if ($check_version) {
            # Display firmware version on BMC
            $next_status{LOGIN_RESPONSE} = "RINV_FIRM_REQUEST";
            $next_status{RINV_FIRM_REQUEST} = "RINV_FIRM_RESPONSE";
        }
        if ($list) {
            # Display firmware update files uploaded to BMC
            $next_status{LOGIN_RESPONSE} = "RFLASH_LIST_REQUEST";
            $next_status{RFLASH_LIST_REQUEST} = "RFLASH_LIST_RESPONSE";
        }
        if ($delete) {
            # Delete uploaded image from BMC
            $next_status{LOGIN_RESPONSE} = "RFLASH_DELETE_IMAGE_REQUEST";
            $next_status{RFLASH_DELETE_IMAGE_REQUEST} = "RFLASH_DELETE_IMAGE_RESPONSE";
        }
        if ($upload) {
            # Upload specified update file to BMC
            $next_status{LOGIN_RESPONSE} = "RFLASH_FILE_UPLOAD_REQUEST";
            $next_status{"RFLASH_FILE_UPLOAD_REQUEST"} = "RFLASH_FILE_UPLOAD_RESPONSE";
        }
        if ($activate) {
            # Activation of an update was requested.
            # First we query the update image for its Activation state. If image is in "Ready" we
            # need to set "RequestedActivation" attribute to "Active". If image is in "Active" we
            # need to set "Priority" to 0.
            $next_status{LOGIN_RESPONSE} = "RFLASH_UPDATE_ACTIVATE_REQUEST";
            $next_status{"RFLASH_UPDATE_ACTIVATE_REQUEST"} = "RFLASH_UPDATE_ACTIVATE_RESPONSE";
            $next_status{"RFLASH_UPDATE_ACTIVATE_RESPONSE"} = "RFLASH_UPDATE_CHECK_STATE_REQUEST";
            $next_status{"RFLASH_UPDATE_CHECK_STATE_REQUEST"} = "RFLASH_UPDATE_CHECK_STATE_RESPONSE";

            $next_status{"RFLASH_SET_PRIORITY_REQUEST"} = "RFLASH_SET_PRIORITY_RESPONSE";
            $next_status{"RFLASH_SET_PRIORITY_RESPONSE"} = "RFLASH_UPDATE_CHECK_STATE_REQUEST";
        }
        if ($upload_and_activate) {
            # Upload specified update file to BMC
            $next_status{LOGIN_RESPONSE} = "RFLASH_FILE_UPLOAD_REQUEST";
            $next_status{"RFLASH_FILE_UPLOAD_REQUEST"} = "RFLASH_FILE_UPLOAD_RESPONSE";
            $next_status{"RFLASH_FILE_UPLOAD_RESPONSE"} = "RFLASH_UPDATE_CHECK_ID_REQUEST";
            $next_status{"RFLASH_UPDATE_CHECK_ID_REQUEST"} = "RFLASH_UPDATE_CHECK_ID_RESPONSE";
        }
    }

    return;
}

#-------------------------------------------------------

=head3  parse_node_info

  Parse the node information: bmc, username, password

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
            } else {
                xCAT::SvrUtils::sendmsg("Error: Unable to get attribute bmc", $callback, $node);
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

            $node_info{$node}{cur_status} = "LOGIN_REQUEST";
        } else {
            xCAT::SvrUtils::sendmsg("Error: Unable to get information from openbmc table", $callback, $node);
            $rst = 1;
            next;
        }
    }

    return $rst;
}

#-------------------------------------------------------

=head3  gen_send_request

  Generate request's information
      If the node has method itself, use it as request's method.
      If not, use method %status_info defined.
      If the node has cur_url, check whether also has sub_urls. 
      If has, request's url is join cur_url and one in sub_urls(use one at once to check which is needed).
      If not, use method %status_info defined.
      use xCAT::OPENBMC->send_request send request
      store handle_id and mapping node
  Input:
      $node: nodename of current node

=cut

#-------------------------------------------------------
sub gen_send_request {
    my $node = shift;
    my $method;
    my $request_url;
    my $content;

    if ($node_info{$node}{method}) {
        $method = $node_info{$node}{method};
    } else {
        $method = $status_info{ $node_info{$node}{cur_status} }{method};
    }

    if ($status_info{ $node_info{$node}{cur_status} }{data}) {
        # Handle boolean values by create the json objects without wrapping with quotes
        if ($status_info{ $node_info{$node}{cur_status} }{data} =~ /^1$|^true$|^True$|^0$|^false$|^False$/) {
            $content = '{"data":' . $status_info{ $node_info{$node}{cur_status} }{data} . '}';
        } elsif ($status_info{ $node_info{$node}{cur_status} }{data} =~ /^\[\]$/) {
            # Special handling of empty data list
            $content = '{"data":[]}';
        } else {
            $content = '{"data":"' . $status_info{ $node_info{$node}{cur_status} }{data} . '"}';
        }
    }

    if ($node_info{$node}{cur_url}) {
        $request_url = $node_info{$node}{cur_url};
    } else {
        $request_url = $status_info{ $node_info{$node}{cur_status} }{init_url};
    }
    $request_url = "$http_protocol://" . $node_info{$node}{bmc} . $request_url;

    my $handle_id = xCAT::OPENBMC->send_request($async, $method, $request_url, $content);
    $handle_id_node{$handle_id} = $node;
    $node_info{$node}{cur_status} = $next_status{ $node_info{$node}{cur_status} };

    if ($xcatdebugmode) {
        my $debug_info;
        if ($method eq "GET") {
            $debug_info = "curl -k -b cjar -X $method -H \"Content-Type: application/json\" $request_url";
        } else {
            if ($::UPLOAD_FILE) {
                # Slightly different debug message when doing a file upload
                $debug_info = "curl -k -b cjar -X $method -H \"Content-Type: application/json\" -T $::UPLOAD_FILE $request_url";
            } else {
                $debug_info = "curl -k -b cjar -X $method -H \"Content-Type: application/json\" -d '$content' $request_url";
            }
        }
        process_debug_info($node, $debug_info);
    }

    return;
}

#-------------------------------------------------------

=head3  deal_with_response

  Check response's status_line and 
  Input:
        $handle_id: Async return ID with response
        $response: Async return response

=cut

#-------------------------------------------------------
sub deal_with_response {
    my $handle_id = shift;
    my $response = shift;
    my $node = $handle_id_node{$handle_id};

    delete $handle_id_node{$handle_id};

    if ($xcatdebugmode) {
        my $debug_info = lc ($node_info{$node}{cur_status}) . " " . $response->status_line;
        process_debug_info($node, $debug_info);
    }

    if ($response->status_line ne $::RESPONSE_OK) {
        my $error;
        if ($response->status_line eq $::RESPONSE_SERVICE_UNAVAILABLE) {
            $error = $::RESPONSE_SERVICE_UNAVAILABLE;
        } elsif ($response->status_line eq $::RESPONSE_METHOD_NOT_ALLOWED) {
            # Special processing for file upload. At this point we do not know how to
            # form a proper file upload request. It always fails with "Method not allowed" error.
            # If that happens, just assume it worked. 
            # TODO remove this block when proper request can be generated
            $status_info{ $node_info{$node}{cur_status} }->{process}->($node, $response); 

            return;
        } elsif ($response->status_line eq $::RESPONSE_SERVICE_TIMEOUT) {
            $error = $::RESPONSE_SERVICE_TIMEOUT;
        } else {
            my $response_info = decode_json $response->content;
            if ($response->status_line eq $::RESPONSE_SERVER_ERROR) {
                $error = $response_info->{'data'}->{'exception'};
            } elsif ($response->status_line eq $::RESPONSE_FORBIDDEN) {
                $error = "$::RESPONSE_FORBIDDEN - This function is not yet available in OpenBMC firmware.";
            } elsif ($response_info->{'data'}->{'description'} =~ /path or object not found: (.+)/) {
                $error = "path or object not found $1";
            } else {
                $error = $response_info->{'data'}->{'description'};
            }
        }
        xCAT::SvrUtils::sendmsg([1, $error], $callback, $node);
        $wait_node_num--;
        return;    
    }

    $status_info{ $node_info{$node}{cur_status} }->{process}->($node, $response); 

    return;
}

#-------------------------------------------------------

=head3  process_debug_info

  print debug info and add to log
  Input:
        $node: nodename which want to process ingo
        $debug_msg: Info for debug

=cut

#-------------------------------------------------------
sub process_debug_info {
    my $node = shift;
    my $debug_msg = shift;

    xCAT::SvrUtils::sendmsg("$flag_debug $debug_msg", $callback, $node);
    xCAT::MsgUtils->trace(0, "D", "$flag_debug $node $debug_msg"); 
}

#-------------------------------------------------------

=head3  login_response

  Deal with response of login
  Input:
        $node: nodename of current response
        $response: Async return response

=cut

#-------------------------------------------------------
sub login_response {
    my $node = shift;
    my $response = shift;

    if ($next_status{ $node_info{$node}{cur_status} }) {
        $node_info{$node}{cur_status} = $next_status{ $node_info{$node}{cur_status} };
        gen_send_request($node);
    }

    return;
}

#-------------------------------------------------------

=head3  rpower_response

  Deal with response of rpower command
  Input:
        $node: nodename of current response
        $response: Async return response

=cut

#-------------------------------------------------------
sub rpower_response {
    my $node = shift;
    my $response = shift;
    my %new_status = ();

    my $response_info = decode_json $response->content;


    if ($node_info{$node}{cur_status} eq "RPOWER_ON_RESPONSE") {
        if ($response_info->{'message'} eq $::RESPONSE_OK) {
            xCAT::SvrUtils::sendmsg("$::POWER_STATE_ON", $callback, $node);
            $new_status{$::STATUS_POWERING_ON} = [$node];
        }
    } 

    if ($node_info{$node}{cur_status} eq "RPOWER_OFF_RESPONSE") {
        if ($response_info->{'message'} eq $::RESPONSE_OK) {
            xCAT::SvrUtils::sendmsg("$::POWER_STATE_OFF", $callback, $node);
            $new_status{$::STATUS_POWERING_OFF} = [$node];
        }
    }

    if ($node_info{$node}{cur_status} eq "RPOWER_RESET_RESPONSE") {
        if ($response_info->{'message'} eq $::RESPONSE_OK) {
            if (defined $status_info{RPOWER_RESET_RESPONSE}{argv} and $status_info{RPOWER_RESET_RESPONSE}{argv} =~ /bmcreboot$/) {
                xCAT::SvrUtils::sendmsg("BMC $::POWER_STATE_REBOOT", $callback, $node);
            } else {
                xCAT::SvrUtils::sendmsg("$::POWER_STATE_RESET", $callback, $node);
            }
            $new_status{$::STATUS_POWERING_ON} = [$node];
        }
    }

    xCAT_monitoring::monitorctrl::setNodeStatusAttributes(\%new_status, 1) if (%new_status);

    if ($node_info{$node}{cur_status} eq "RPOWER_STATUS_RESPONSE" and !$next_status{ $node_info{$node}{cur_status} }) { 
        my $bmc_state = "";
        my $bmc_transition_state = "";
        my $chassis_state = "";
        my $chassis_transition_state = "";
        my $host_state = "";
        my $host_transition_state = "";
        foreach my $type (keys %{$response_info->{data}}) {
            if ($type =~ /bmc0/) {
                $bmc_state = $response_info->{'data'}->{$type}->{CurrentBMCState};
                $bmc_transition_state = $response_info->{'data'}->{$type}->{RequestedBMCTransition};
            }
            if ($type =~ /chassis0/) { 
                $chassis_state = $response_info->{'data'}->{$type}->{CurrentPowerState};
                $chassis_transition_state = $response_info->{'data'}->{$type}->{RequestedPowerTransition};
            }
            if ($type =~ /host0/) {
                $host_state = $response_info->{'data'}->{$type}->{CurrentHostState};
                $host_transition_state = $response_info->{'data'}->{$type}->{RequestedHostTransition};
            }
        }

        if (defined $status_info{RPOWER_STATUS_RESPONSE}{argv} and $status_info{RPOWER_STATUS_RESPONSE}{argv} =~ /bmcstate$/) { 
            my $bmc_short_state = (split(/\./, $bmc_state))[-1];
            xCAT::SvrUtils::sendmsg("BMC $bmc_short_state", $callback, $node);
        } else {
            if ($chassis_state =~ /Off$/) {
                xCAT::SvrUtils::sendmsg("$::POWER_STATE_OFF", $callback, $node);
            } elsif ($chassis_state =~ /On$/) { 
                if ($host_state =~ /Off$/) {
                    # State is off, but check if it is transitioning
                    if ($host_transition_state =~ /On$/) {
                        #xCAT::SvrUtils::sendmsg("$::POWER_STATE_POWERING_ON", $callback, $node);
                        # ignore transition state until get stable firmware
                        xCAT::SvrUtils::sendmsg("$::POWER_STATE_OFF", $callback, $node);
                    } else {
                        xCAT::SvrUtils::sendmsg("$::POWER_STATE_OFF", $callback, $node);
                    }
                } elsif ($host_state =~ /Quiesced$/) {
                    xCAT::SvrUtils::sendmsg("$::POWER_STATE_QUIESCED", $callback, $node);
                } elsif ($host_state =~ /Running$/) {
                    # State is on, but check if it is transitioning
                    if ($host_transition_state =~ /Off$/) {
                        #xCAT::SvrUtils::sendmsg("$::POWER_STATE_POWERING_OFF", $callback, $node);
                        # ignore transition state until get stable firmware
                        xCAT::SvrUtils::sendmsg("$::POWER_STATE_ON", $callback, $node);
                    } else {
                        xCAT::SvrUtils::sendmsg("$::POWER_STATE_ON", $callback, $node);
                    }
                } else {
                    xCAT::SvrUtils::sendmsg("Unexpected host state=$host_state", $callback, $node);
                }
            } else {
                xCAT::SvrUtils::sendmsg("Unexpected chassis state=$chassis_state", $callback, $node);
            }
        }
    }

    if ($next_status{ $node_info{$node}{cur_status} }) {
        if ($node_info{$node}{cur_status} eq "RPOWER_STATUS_RESPONSE") {
            if ($response_info->{'data'}->{CurrentHostState} =~ /Off$/) {
                $node_info{$node}{cur_status} = $next_status{ $node_info{$node}{cur_status} }{OFF};
            } else {
                $node_info{$node}{cur_status} = $next_status{ $node_info{$node}{cur_status} }{ON};
            }
        } else {
            $node_info{$node}{cur_status} = $next_status{ $node_info{$node}{cur_status} };
        } 
        gen_send_request($node);
    } else {
        $wait_node_num--;
    }

    return;
}

#-------------------------------------------------------

=head3  rinv_response

  Deal with response of rinv command
  Input:
        $node: nodename of current response
        $response: Async return response

=cut

#-------------------------------------------------------
sub rinv_response {
    my $node = shift;
    my $response = shift;

    my $response_info = decode_json $response->content;

    my $grep_string;
    if ($node_info{$node}{cur_status} eq "RINV_FIRM_RESPONSE") {
        $grep_string = "firm";
    } else {
        $grep_string = $status_info{RINV_RESPONSE}{argv};
    }

    my $src;
    my $content_info;
    my @sorted_output;

    foreach my $key_url (keys %{$response_info->{data}}) {
        my %content = %{ ${ $response_info->{data} }{$key_url} };

        if ($grep_string eq "firm") {
            # This handles the data from the /xyz/openbmc_project/Software endpoint.
            my $sw_id = (split(/\//, $key_url))[-1];
            if (defined($content{Version}) and $content{Version}) {
                my $purpose_value = uc ((split(/\./, $content{Purpose}))[-1]);
                $purpose_value = "[$sw_id]$purpose_value";
                my $activation_value = (split(/\./, $content{Activation}))[-1];
                my $priority_value = -1;
                if (defined($content{Priority})) {
                    $priority_value = $content{Priority};
                }
                #
                # For 'rinv firm', only print Active software, unless verbose is specified
                #
                if (($activation_value =~ "Active" and $priority_value == 0) or $::VERBOSE) {
                    #
                    # The space below between "Firmware Product Version:" and $content{Version} is intentional
                    # to cause the sorting of this line before any additional info lines 
                    #
                    $content_info = "$purpose_value Firmware Product:   $content{Version} ($activation_value)";
                    if ($priority_value == 0) {
                        # For now, indicate priority 0 software levels with an '*'
                        $content_info .= "*";
                    }
                    push (@sorted_output, $content_info); 
    
                    if (defined($content{ExtendedVersion}) and $content{ExtendedVersion} ne "") { 
                        # ExtendedVersion is going to be a comma separated list of additional software
                        my @versions = split(',', $content{ExtendedVersion});
                        foreach my $ver (@versions) { 
                            $content_info = "$purpose_value Firmware Product: -- additional info: $ver";
                            push (@sorted_output, $content_info);
                        }
                    }
                    next;
                }
            }
        } else {
            if (! defined $content{Present}) {
                # If the Present field is not part of the attribute, then it's most likely a callout
                # Do not print as part of the inventory response
                next; 
            }

            # SPECIAL CASE: If 'serial' or 'model' is specified, only return the system level information
            if ($grep_string eq "serial" or $grep_string eq "model") {
                if ($key_url ne "$openbmc_project_url/inventory/system") {
                    next;
                }
            }

            if ($key_url =~ /\/(cpu\d*)\/(\w+)/) {
                $src = "$1 $2";
            } else {
                $src = basename $key_url;
            }

            foreach my $key (keys %content) {
                # If not all options is specified, check whether the key string contains
                # the keyword option.  If so, add it to the return data
                if ($grep_string ne "all" and ((lc($key) !~ m/$grep_string/i) and ($key_url !~ m/$grep_string/i)) ) {
                    next;
                }
                $content_info = uc ($src) . " " . $key . " : " . $content{$key};
                push (@sorted_output, $content_info); #Save output in array
            }
        }
    }
    # If sorted array has any contents, sort it and print it
    if (scalar @sorted_output > 0) {
        # sort alpha, then numeric 
        my @sorted_output = grep {s/(^|\D)0+(\d)/$1$2/g,1} sort 
            grep {s/(\d+)/sprintf"%06.6d",$1/ge,1} @sorted_output;
        foreach (@sorted_output) { 
            #
            # The firmware output requires the ID to be part of the string to sort correctly.
            # Remove this ID from the output to the user
            #
            $_ =~ s/\[.*?\]//;
            xCAT::SvrUtils::sendmsg("$_", $callback, $node);
        }
    } else {
        xCAT::SvrUtils::sendmsg("$::NO_ATTRIBUTES_RETURNED", $callback, $node);
    }

    if ($next_status{ $node_info{$node}{cur_status} }) {
        $node_info{$node}{cur_status} = $next_status{ $node_info{$node}{cur_status} };
        gen_send_request($node);
    } else {
        $wait_node_num--;
    }

    return;
}

#-------------------------------------------------------

=head3  getopenbmccons

    Process getopenbmccons

=cut

#-------------------------------------------------------
sub getopenbmccons {
    my $argr = shift;

    #$argr is [$node,$bmcip,$nodeuser,$nodepass];
    my $callback = shift;

    my $rsp;
    my $node=$argr->[0];
    my $output = "openbmc, getopenbmccoms";
    xCAT::SvrUtils::sendmsg($output, $callback, $argr->[0], %allerrornodes);

    $rsp = { node => [ { name => [ $argr->[0] ] } ] };
    $rsp->{node}->[0]->{bmcip}->[0]    = $argr->[1];
    $rsp->{node}->[0]->{username}->[0]    = $argr->[2];
    $rsp->{node}->[0]->{passwd}->[0]  = $argr->[3];
    $callback->($rsp);
    return $rsp;
}

#-------------------------------------------------------

=head3  rsetboot_response

  Deal with response of rsetboot command
  Input:
        $node: nodename of current response
        $response: Async return response

=cut

#-------------------------------------------------------
sub rsetboot_response {
    my $node = shift;
    my $response = shift;

    my $response_info = decode_json $response->content;    

    if ($node_info{$node}{cur_status} eq "RSETBOOT_STATUS_RESPONSE") {
        if ($response_info->{'data'}->{BootSource} =~ /Disk$/) {
            xCAT::SvrUtils::sendmsg("Hard Drive", $callback, $node);
        } elsif ($response_info->{'data'}->{BootSource} =~ /Network$/) {
            xCAT::SvrUtils::sendmsg("Network", $callback, $node);
        } elsif ($response_info->{'data'}->{BootSource} =~ /ExternalMedia$/) {
            xCAT::SvrUtils::sendmsg("CD/DVD", $callback, $node);
        } elsif ($response_info->{'data'}->{BootSource} =~ /Default$/) {
            xCAT::SvrUtils::sendmsg("Default", $callback, $node);
        } else {
            my $error_msg = "Can not get valid rsetboot status, the data is " . $response_info->{'data'}->{BootSource};
            xCAT::SvrUtils::sendmsg("$error_msg", $callback, $node);
        }
    }

    if ($next_status{ $node_info{$node}{cur_status} }) {
        $node_info{$node}{cur_status} = $next_status{ $node_info{$node}{cur_status} };
        gen_send_request($node);
    } else {
        $wait_node_num--;
    }

    return;
}

#-------------------------------------------------------

=head3  rbeacon_response

  Deal with response of rbeacon command
  Input:
        $node: nodename of current response
        $response: Async return response

=cut

#-------------------------------------------------------
sub rbeacon_response {
    my $node = shift;
    my $response = shift;

    my $response_info = decode_json $response->content;

    if ($node_info{$node}{cur_status} eq "RBEACON_ON_RESPONSE") {
        if ($response_info->{'message'} eq $::RESPONSE_OK) {
            xCAT::SvrUtils::sendmsg("$::BEACON_STATE_ON", $callback, $node);
        }
    } 

    if ($node_info{$node}{cur_status} eq "RBEACON_OFF_RESPONSE") {
        if ($response_info->{'message'} eq $::RESPONSE_OK) {
            xCAT::SvrUtils::sendmsg("$::BEACON_STATE_OFF", $callback, $node);
        }
    }

    if ($next_status{ $node_info{$node}{cur_status} }) {
        $node_info{$node}{cur_status} = $next_status{ $node_info{$node}{cur_status} };
        gen_send_request($node);
    } else {
        $wait_node_num--;
    }
}


#-------------------------------------------------------

=head3  reventlog_response

  Deal with response of reventlog command
  Input:
        $node: nodename of current response
        $response: Async return response

=cut

#-------------------------------------------------------
sub reventlog_response {
    my $node = shift;
    my $response = shift;

    my $response_info = decode_json $response->content;

    if ($node_info{$node}{cur_status} eq "REVENTLOG_CLEAR_RESPONSE") {
        if ($response_info->{'message'} eq $::RESPONSE_OK) {
            xCAT::SvrUtils::sendmsg("clear", $callback, $node);
        }
    } else {
        my ($entry_string, $option_s) = split(",", $status_info{REVENTLOG_RESPONSE}{argv});
        my $content_info; 
        my %output = ();
        my $entry_num = 0;
        $entry_string = "all" if ($entry_string eq "0");
        $entry_num = 0 + $entry_string if ($entry_string ne "all");

        foreach my $key_url (keys %{$response_info->{data}}) {
            my %content = %{ ${ $response_info->{data} }{$key_url} };
            my $timestamp = $content{Timestamp};
            my $id_num = 0 + $content{Id} if ($content{Id});
            if ($content{Message}) {
                my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime($content{Timestamp}/1000);
                $mon += 1;
                $year += 1900;
                my $UTC_time = sprintf ("%02d/%02d/%04d %02d:%02d:%02d", $mon, $mday, $year, $hour, $min, $sec); 
                my $content_info = $UTC_time . " [$content{Id}] " . $content{Message};
                $output{$timestamp} = $content_info;
            }
        }

        my $count = 0;
        if ($option_s) {
            foreach my $key ( sort { $b <=> $a } keys %output) {
                xCAT::MsgUtils->message("I", { data => [$output{$key}] }, $callback, $node) if ($output{$key});
                $count++;
                last if ($entry_string ne "all" and $count >= $entry_num); 
            }
        } else {
            foreach my $key (sort keys %output) {
                xCAT::MsgUtils->message("I", { data => [$output{$key}] }, $callback, $node) if ($output{$key});
                $count++;
                last if ($entry_string ne "all" and $count >= $entry_num);
            }
        }
    }

    if ($next_status{ $node_info{$node}{cur_status} }) {
        $node_info{$node}{cur_status} = $next_status{ $node_info{$node}{cur_status} };
        gen_send_request($node);
    } else {
        $wait_node_num--;
    }
}

#-------------------------------------------------------

=head3  rspconfig_response

  Deal with response of rspconfig command
  Input:
        $node: nodename of current response
        $response: Async return response

=cut

#-------------------------------------------------------
sub rspconfig_response {
    my $node = shift;
    my $response = shift;

    my $response_info = decode_json $response->content; 

    if ($node_info{$node}{cur_status} eq "RSPCONFIG_GET_RESPONSE") {
        my $address         = "n/a";
        my $gateway         = "n/a";
        my $prefix          = "n/a";
        my $vlan            = "n/a";
        my $hostname        = "";
        my $default_gateway = "n/a";
        my $adapter_id      = "n/a";
        my $error;
        my $path;
        my @output;
        my $grep_string = $status_info{RSPCONFIG_GET_RESPONSE}{argv};
        foreach my $key_url (keys %{$response_info->{data}}) {
            my %content = %{ ${ $response_info->{data} }{$key_url} };

            if ($key_url =~ /network\/config/) {
                if (defined($content{DefaultGateway}) and $content{DefaultGateway}) {
                    $default_gateway = $content{DefaultGateway};
                }
                if (defined($content{HostName}) and $content{HostName}) {
                    $hostname = $content{HostName};
                }
            }


            ($path, $adapter_id) = (split(/ipv4\//, $key_url));

            if ($adapter_id) {
                if (defined($content{Address}) and $content{Address}) {
                    unless ($address =~ /n\/a/) {
                        # We have already processed an entry with adapter information.
                        # This must be a second entry. Display an error. Currently only supporting
                        # an adapter with a single IP address set.
                        $error = "Interfaces with multiple IP addresses are not supported";
                        last;
                    }
                    $address = $content{Address};
                }
                if (defined($content{Gateway}) and $content{Gateway}) {
                    $gateway = $content{Gateway};
                }
                if (defined($content{PrefixLength}) and $content{PrefixLength}) {
                    $prefix = $content{PrefixLength};
                }
            }
        }
        if ($error) {
            # Display error message once, regardless of how many subcommands were specified
            push @output, $error;
        }
        else {
            if ($grep_string =~ "ip") {
                push @output, "BMC IP: $address"; 
            } 
            if ($grep_string =~ "netmask") {
                if ($address) {
                    my $decimal_mask = (2 ** $prefix - 1) << (32 - $prefix);
                    my $netmask = join('.', unpack("C4", pack("N", $decimal_mask)));
                    push @output, "BMC Netmask: " . $netmask; 
                }
            } 
            if ($grep_string =~ "gateway") {
                push @output, "BMC Gateway: $gateway (default: $default_gateway)";
            }  
            if ($grep_string =~ "vlan") {
                push @output, "BMC VLAN ID enabled: $vlan";
            }
            if ($grep_string =~ "hostname") {
                push @output, "BMC Hostname: $hostname";
            }
        }

        xCAT::SvrUtils::sendmsg("$_", $callback, $node) foreach (@output);
    }

    if ($node_info{$node}{cur_status} eq "RSPCONFIG_SET_RESPONSE") {
        if ($response_info->{'message'} eq $::RESPONSE_OK) {
            xCAT::SvrUtils::sendmsg("BMC Setting Hostname (requires bmcreboot to take effect)...", $callback, $node);
        }
    }
    if ($node_info{$node}{cur_status} eq "RSPCONFIG_DHCP_RESPONSE") {
        if ($response_info->{'message'} eq $::RESPONSE_OK) {
            xCAT::SvrUtils::sendmsg("BMC Setting IP to DHCP...", $callback, $node);
        }
    }

    if ($next_status{ $node_info{$node}{cur_status} }) {
        $node_info{$node}{cur_status} = $next_status{ $node_info{$node}{cur_status} };
        gen_send_request($node);
    } else {
        $wait_node_num--;
    } 
}

#-------------------------------------------------------

=head3  rspconfig_sshcfg_response

  Deal with response of rspconfig command for sscfg subcommand.
  Append contents of id_rsa.pub file from management node to
  the authorized_keys file on BMC
  Input:
        $node: nodename of current response
        $response: Async return response

=cut

#-------------------------------------------------------
sub rspconfig_sshcfg_response {
    my $node = shift;
    my $response = shift;

    my $response_info = decode_json $response->content; 

    use xCAT::RShellAPI;
    if ($node_info{$node}{cur_status} eq "RSPCONFIG_SSHCFG_RESPONSE") {
        my $bmcip = $node_info{$node}{bmc};
        my $userid = $node_info{$node}{username}; 
        my $userpw = $node_info{$node}{password};
        my $filename = "/root/.ssh/id_rsa.pub";

        # Read in contents of the id_rsa.pub file
        open my $fh, '<', $filename or die "Error opening $filename: $!";
        my $id_rsa_pub_contents = do { local $/; <$fh> };

        # Login and append content of the read in id_rsa.pub file to the authorized_keys file on BMC
        my $output = xCAT::RShellAPI::run_remote_shell_api($bmcip, $userid, $userpw, 0, 0, "mkdir -p ~/.ssh; echo \"$id_rsa_pub_contents\" >> ~/.ssh/authorized_keys");

        # If error was returned from executing command above. Display it to the user.
        # output[0] contains 1 is error, output[1] contains error messages
        if (@$output[0] == 1) {
            xCAT::SvrUtils::sendmsg("Error copying ssh keys to $bmcip:\n" . @$output[1], $callback, $node);
        }
        # For unknown reason, "echo" command above can fail (1 in 5), but return code 0 still returned.
        # There is nothing we can do but to just test if authorized_keys file was not created 
        # and ask the user to rerun the command
        my $file_test_output = xCAT::RShellAPI::run_remote_shell_api($bmcip, $userid, $userpw, 0, 0, "[ ! -f ~/.ssh/authorized_keys ] && uptime");
        if (@$file_test_output[1] =~ "load average") {
            # If file was not there, we run "uptime" command and then look for "load average" in the output.
            # If file was there, "uptime" command is not executed
            xCAT::SvrUtils::sendmsg("Error copying ssh keys to $bmcip Rerun rspconfig command.", $callback, $node);
        }
        else {
            xCAT::SvrUtils::sendmsg("ssh keys copied to $bmcip", $callback, $node);
        }
    }
    if ($next_status{ $node_info{$node}{cur_status} }) {
        $node_info{$node}{cur_status} = $next_status{ $node_info{$node}{cur_status} };
        gen_send_request($node);
    } else {
        $wait_node_num--;
    } 
}
#-------------------------------------------------------

=head3  rvitals_response

  Deal with response of rvitals command
  Input:
        $node: nodename of current response
        $response: Async return response

=cut

#-------------------------------------------------------
sub rvitals_response {
    my $node = shift;
    my $response = shift;

    my $response_info = decode_json $response->content;

    my $grep_string = $status_info{RVITALS_RESPONSE}{argv};
    my $src;
    my $content_info;
    my @sorted_output;

    foreach my $key_url (keys %{$response_info->{data}}) {
        my %content = %{ ${ $response_info->{data} }{$key_url} };

        #
        # Skip over attributes that are not asked to be printed
        #
        if ($grep_string =~ "temp") {
            unless ( $content{Unit} =~ "DegreesC") { next; } 
        } 
        if ($grep_string =~ "voltage") {
            unless ( $content{Unit} =~ "Volts") { next; } 
        } 
        if ($grep_string =~ "wattage") {
            unless ( $content{Unit} =~ "Watts") { next; } 
        } 
        if ($grep_string =~ "fanspeed") {
            unless ( $content{Unit} =~ "RPMS") { next; } 
        } 
        if ($grep_string =~ "power") {
            unless ( $content{Unit} =~ "Amperes" || $content{Unit} =~ "Joules" || $content{Unit} =~ "Watts" ) { next; } 
        } 
        if ($grep_string =~ "altitude") {
            unless ( $content{Unit} =~ "Meters" ) { next; }
        } 

        my $label = (split(/\//, $key_url))[ -1 ];

        # replace underscore with space, uppercase the first letter 
        $label =~ s/_/ /g;
        $label =~ s/\b(\w)/\U$1/g;

        #
        # Calculate the adjusted value based on the scale attribute
        #  
        my $calc_value = $content{Value};
        if ( $content{Scale} != 0 ) { 
            $calc_value = ($content{Value} * (10 ** $content{Scale}));
        } 

        $content_info = $label . ": " . $calc_value . " " . $sensor_units{ $content{Unit} };
        push (@sorted_output, $content_info); #Save output in array
    }
    # If sorted array has any contents, sort it and print it
    if (scalar @sorted_output > 0) {
        # Sort the output, alpha, then numeric
        my @sorted_output = grep {s/(^|\D)0+(\d)/$1$2/g,1} sort 
            grep {s/(\d+)/sprintf"%06.6d",$1/ge,1} @sorted_output;
        xCAT::SvrUtils::sendmsg("$_", $callback, $node) foreach (@sorted_output);
    } else {
        xCAT::SvrUtils::sendmsg("$::NO_ATTRIBUTES_RETURNED", $callback, $node);
    }

    if ($next_status{ $node_info{$node}{cur_status} }) {
        $node_info{$node}{cur_status} = $next_status{ $node_info{$node}{cur_status} };
        gen_send_request($node);
    } else {
        $wait_node_num--;
    }

    return;
}

#-------------------------------------------------------

=head3  rflash_response

  Deal with response of rflash command
  Input:
        $node: nodename of current response
        $response: Async return response

=cut

#-------------------------------------------------------
sub rflash_response {
    my $node = shift;
    my $response = shift;

    my $response_info = decode_json $response->content;

    my $update_id;
    my $update_activation = "Unknown";
    my $update_purpose;
    my $update_version;
    my $update_priority = -1;

    if ($node_info{$node}{cur_status} eq "RFLASH_LIST_RESPONSE") {
        # Display "list" option header and data
        xCAT::SvrUtils::sendmsg("ID       Purpose State      Version", $callback, $node);
        xCAT::SvrUtils::sendmsg("-" x 55, $callback, $node);

        foreach my $key_url (keys %{$response_info->{data}}) {
            my %content = %{ ${ $response_info->{data} }{$key_url} };

            $update_id = (split(/\//, $key_url))[ -1 ];
            if (defined($content{Version}) and $content{Version}) {
                $update_version = $content{Version};
            }
            else {
                # Entry has no Version attribute, skip listing it
                next;
            }
            if (defined($content{Activation}) and $content{Activation}) {
                $update_activation = (split(/\./, $content{Activation}))[ -1 ];
            }
            if (defined($content{Purpose}) and $content{Purpose}) {
                $update_purpose = (split(/\./, $content{Purpose}))[ -1 ];
            }
            if (defined($content{Priority}))  {
                $update_priority = (split(/\./, $content{Priority}))[ -1 ];
            }
            # Priority attribute of 0 indicates the "really" active update image
            if ($update_priority == 0) {
                $update_activation = $update_activation . "(*)";
                $update_priority = -1; # Reset update priority for next loop iteration
            }
            xCAT::SvrUtils::sendmsg(sprintf("%-8s %-7s %-10s %s", $update_id, $update_purpose, $update_activation, $update_version), $callback, $node);
        }
        xCAT::SvrUtils::sendmsg("", $callback, $node); #Separate output in case more than 1 endpoint
    }
    if ($node_info{$node}{cur_status} eq "RFLASH_FILE_UPLOAD_RESPONSE") {
        # Special processing for file upload. At this point we do not know how to
        # form a proper file upload request. It always fails with "Method not allowed" error.
        # If that happens, just call the curl commands for now. 
        # TODO remove this block when proper request can be generated
        if ($::UPLOAD_FILE) {
            my $request_url = "$http_protocol://" . $node_info{$node}{bmc};
            my $content_login = '{ "data": [ "' . $node_info{$node}{username} .'", "' . $node_info{$node}{password} . '" ] }';
            my $content_logout = '{ "data": [ ] }';

            # curl commands
            my $curl_login_cmd  = "curl -c cjar -k -H 'Content-Type: application/json' -X POST $request_url/login -d '" . $content_login . "'";
            my $curl_logout_cmd = "curl -b cjar -k -H 'Content-Type: application/json' -X POST $request_url/logout -d '" . $content_logout . "'";
            my $curl_upload_cmd = "curl -b cjar -k -H 'Content-Type: application/octet-stream' -X PUT -T " . $::UPLOAD_FILE . " $request_url/upload/image/";

            # Try to login
            my $curl_login_result = `$curl_login_cmd`;
            my $h = from_json($curl_login_result); # convert command output to hash
            if ($h->{message} eq $::RESPONSE_OK) {
                # Login successfull, upload the file
                xCAT::SvrUtils::sendmsg("Uploading $::UPLOAD_FILE ...", $callback, $node);
                my $curl_upload_result = `$curl_upload_cmd`;
                $h = from_json($curl_upload_result); # convert command output to hash
                if ($h->{message} eq $::RESPONSE_OK) {
                    # Upload successfull
                    xCAT::SvrUtils::sendmsg("Successful, use -l option to list.", $callback, $node);
                    # Try to logoff, no need to check result, as there is nothing else to do if failure
                    my $curl_logout_result = `$curl_logout_cmd`;
                }
                else {
                    xCAT::SvrUtils::sendmsg("Failed to upload update file $::UPLOAD_FILE :" . $h->{message} . " - " . $h->{data}->{description}, $callback, $node);
                }
            }
            else {
                xCAT::SvrUtils::sendmsg("Unable to login :" . $h->{message} . " - " . $h->{data}->{description}, $callback, $node);
            }
        }
    }
    if ($node_info{$node}{cur_status} eq "RFLASH_UPDATE_ACTIVATE_RESPONSE") {
        xCAT::SvrUtils::sendmsg("rflash started, please wait...", $callback, $node);
    }
    if ($node_info{$node}{cur_status} eq "RFLASH_SET_PRIORITY_RESPONSE") {
        print "Update priority has been set";
    }
    if ($node_info{$node}{cur_status} eq "RFLASH_UPDATE_CHECK_STATE_RESPONSE") {
        my $activation_state;
        my $progress_state;
        my $priority_state;
        foreach my $key_url (keys %{$response_info->{data}}) {
            my $content = ${ $response_info->{data} }{$key_url};
            # Get values of some attributes to determine activation status 
            if ($key_url eq "Activation") {
                $activation_state = ${ $response_info->{data} }{$key_url};
            }
            if ($key_url eq "Progress") {
                $progress_state = ${ $response_info->{data} }{$key_url};
            }
            if ($key_url eq "Priority") {
                $priority_state = ${ $response_info->{data} }{$key_url};
            }
        }

        if ($activation_state =~ /Software.Activation.Activations.Failed/) {
            # Activation failed. Report error and exit
            xCAT::SvrUtils::sendmsg([1,"Activation of firmware failed"], $callback, $node);
        } 
        elsif ($activation_state =~ /Software.Activation.Activations.Active/) { 
            if (scalar($priority_state) == 0) {
                # Activation state of active and priority of 0 indicates the activation has been completed
                xCAT::SvrUtils::sendmsg("Firmware update successfully activated", $callback, $node);
                $wait_node_num--;
                return;
            }
            else {
                # Activation state of active and priority of non 0 - need to just set priority to 0 to activate
                print "Update is already active, just need to set priority to 0\n";
                $next_status{ $node_info{$node}{cur_status} } = "RFLASH_SET_PRIORITY_REQUEST";
            }
        }
        elsif ($activation_state =~ /Software.Activation.Activations.Activating/) {
            # Activation still going, sleep for a bit, then print the progress value
            sleep(15);
            xCAT::SvrUtils::sendmsg("Activating firmware update. $progress_state\%", $callback, $node);

            # Set next state to come back here to chect the activation status again.
            $next_status{ $node_info{$node}{cur_status} } = "RFLASH_UPDATE_CHECK_STATE_REQUEST";
        }
       
    }

    if ($node_info{$node}{cur_status} eq "RFLASH_UPDATE_CHECK_ID_RESPONSE") {
        my $activation_state;
        my $progress_state;
        my $priority_state;

        # Look through all the software entries and find the id of the one that matches
        # the version of the uploaded file. Once found, set up request/response hash entries
        # to activate that image.
        foreach my $key_url (keys %{$response_info->{data}}) {
            my %content = %{ ${ $response_info->{data} }{$key_url} };

            $update_id = (split(/\//, $key_url))[ -1 ];
            if (defined($content{Version}) and $content{Version}) {
                $update_version = $content{Version};
            }
            if ($update_version eq $::UPLOAD_FILE_VERSION) {
                # Found a match of uploaded file version with the image in software/enumerate

                # Set the image id for the activation request
                $status_info{RFLASH_UPDATE_ACTIVATE_REQUEST}{init_url}    .= "/$update_id/attr/RequestedActivation";
                $status_info{RFLASH_UPDATE_CHECK_STATE_REQUEST}{init_url} .= "/$update_id";
                $status_info{RFLASH_SET_PRIORITY_REQUEST}{init_url}       .= "/$update_id/attr/Priority";

                # Set next steps to activate the image
                $next_status{ $node_info{$node}{cur_status} } = "RFLASH_UPDATE_ACTIVATE_REQUEST";
                $next_status{"RFLASH_UPDATE_ACTIVATE_REQUEST"} = "RFLASH_UPDATE_ACTIVATE_RESPONSE";
                $next_status{"RFLASH_UPDATE_ACTIVATE_RESPONSE"} = "RFLASH_UPDATE_CHECK_STATE_REQUEST";
                $next_status{"RFLASH_UPDATE_CHECK_STATE_REQUEST"} = "RFLASH_UPDATE_CHECK_STATE_RESPONSE";

                $next_status{"RFLASH_SET_PRIORITY_REQUEST"} = "RFLASH_SET_PRIORITY_RESPONSE";
                $next_status{"RFLASH_SET_PRIORITY_RESPONSE"} = "RFLASH_UPDATE_CHECK_STATE_REQUEST";
                last;
            }
        }
    }

    if ($node_info{$node}{cur_status} eq "RFLASH_DELETE_IMAGE_RESPONSE") {
            xCAT::SvrUtils::sendmsg("Firmware update successfully removed", $callback, $node);
    }

    if ($next_status{ $node_info{$node}{cur_status} }) {
        $node_info{$node}{cur_status} = $next_status{ $node_info{$node}{cur_status} };
        gen_send_request($node);
    } else {
        $wait_node_num--;
    }
    return;
}
1;
