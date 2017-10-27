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
use File::Copy qw/copy cp mv move/;
use File::Path;
use Data::Dumper;
use Getopt::Long;
use xCAT::OPENBMC;
use xCAT::RemoteShellExp;
use xCAT::Utils;
use xCAT::Table;
use xCAT::Usage;
use xCAT::SvrUtils;
use xCAT::GlobalDef;
use xCAT_monitoring::monitorctrl;
use POSIX qw(WNOHANG);

$::VERBOSE                  = 0;
# String constants for rbeacon states
$::BEACON_STATE_OFF         = "off";
$::BEACON_STATE_ON          = "on";
# String constants for rpower states
$::POWER_STATE_OFF          = "off";
$::POWER_STATE_ON           = "on";
$::POWER_STATE_ON_HOSTOFF   = "on (Chassis)";
$::POWER_STATE_POWERING_OFF = "powering-off";
$::POWER_STATE_POWERING_ON  = "powering-on";
$::POWER_STATE_QUIESCED     = "quiesced";
$::POWER_STATE_RESET        = "reset";
$::POWER_STATE_REBOOT       = "reboot";
$::UPLOAD_FILE              = "";
$::UPLOAD_FILE_VERSION      = "";
$::RSETBOOT_URL_PATH        = "boot";
# To improve the output to users, store this value as a global
$::UPLOAD_AND_ACTIVATE      = 0;

$::NO_ATTRIBUTES_RETURNED   = "No attributes returned from the BMC.";

$::UPLOAD_WAIT_ATTEMPT      = 6;
$::UPLOAD_WAIT_INTERVAL     = 10;
$::UPLOAD_WAIT_TOTALTIME    = int($::UPLOAD_WAIT_ATTEMPT*$::UPLOAD_WAIT_INTERVAL);

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
my %child_node_map;   # pid => node

my $http_protocol="https";
my $openbmc_url = "/org/openbmc";
my $openbmc_project_url = "/xyz/openbmc_project";
$::SOFTWARE_URL = "$openbmc_project_url/software";
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
        init_url       => "$openbmc_project_url/logging/action/deleteAll",
        data           => "[]",
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
        process        => \&rflash_response,
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
    RPOWER_SOFTOFF_RESPONSE => {
        process        => \&rpower_response,
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

    RSETBOOT_ENABLE_REQUEST => {
        method         => "PUT",
        init_url       => "$openbmc_project_url/control/host0/boot/one_time/attr/Enabled",
        data           => '1',
    },
    RSETBOOT_ENABLE_RESPONSE => {
        process        => \&rsetboot_response,
    },
    RSETBOOT_SET_REQUEST => {
        method         => "PUT",
        init_url       => "$openbmc_project_url/control/host0/boot/one_time/attr/BootSource",
        data           => "xyz.openbmc_project.Control.Boot.Source.Sources.",
    },
    RSETBOOT_SET_RESPONSE => {
        process        => \&rsetboot_response,
    },
    RSETBOOT_STATUS_REQUEST  => {
        method         => "GET",
        init_url       => "$openbmc_project_url/control/host0/enumerate",
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
        process        => \&rspconfig_sshcfg_response,
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

# Store the value format like '<node> => <time>' to manage the green sleep time, used
# by retry_after and the main loop in process_request only.
my %node_wait = ();

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
    if (defined $request->{_xcat_ignore_flag}->[0] and $request->{_xcat_ignore_flag}->[0] eq 'openbmc') {
        return [];#workaround the bug 3026, to ignore it for openbmc
    }
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

    if (ref($request->{environment}) eq 'ARRAY' and ref($request->{environment}->[0]->{XCAT_OPENBMC_FIRMWARE}) eq 'ARRAY') {
        $::OPENBMC_FW = $request->{environment}->[0]->{XCAT_OPENBMC_FIRMWARE}->[0];
    } elsif (ref($request->{environment}) eq 'ARRAY') {
        $::OPENBMC_FW = $request->{environment}->[0]->{XCAT_OPENBMC_FIRMWARE};
    } else {
        $::OPENBMC_FW = $request->{environment}->{XCAT_OPENBMC_FIRMWARE};
    }

    # Provide a way to turn on and off transition state processing, default to off
    if (ref($request->{environment}) eq 'ARRAY' and ref($request->{environment}->[0]->{XCAT_OPENBMC_POWER_TRANSITION}) eq 'ARRAY') {
        $::OPENBMC_PWR = $request->{environment}->[0]->{XCAT_OPENBMC_POWER_TRANSITION}->[0];
    } elsif (ref($request->{environment}) eq 'ARRAY') {
        $::OPENBMC_PWR = $request->{environment}->[0]->{XCAT_OPENBMC_POWER_TRANSITION};
    } else {
        $::OPENBMC_PWR = $request->{environment}->{XCAT_OPENBMC_POWER_TRANSITION};
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

=head3  retry_after

    The request will be delayed for the given time and then
    send the reqeust based on the status in the main loop.

=cut

#-------------------------------------------------------
sub retry_after {
    my ($node, $request_status, $timeout) = @_;
    $node_info{$node}{cur_status} = $request_status;
    $node_wait{$node} = time() + $timeout;
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

    if ($next_status{LOGIN_RESPONSE} eq "RSPCONFIG_SSHCFG_REQUEST") {
        my $home = xCAT::Utils->getHomeDir("root");
        open(FILE, ">$home/.ssh/copy.sh")
          or die "cannot open file $home/.ssh/copy.sh\n";
        print FILE "#!/bin/sh
umask 0077
userid=\$1
home=`egrep \"^\$userid:\" /etc/passwd | cut -f6 -d :`
if [ -n \"\$home\" ]; then
  dest_dir=\"\$home/.ssh\"
else
  home=`su - root -c pwd`
  dest_dir=\"\$home/.ssh\"
fi
mkdir -p \$dest_dir
cat /tmp/\$userid/.ssh/id_rsa.pub >> \$home/.ssh/authorized_keys 2>&1
rm -f /tmp/\$userid/.ssh/* 2>&1
rmdir \"/tmp/\$userid/.ssh\"
rmdir \"/tmp/\$userid\" \n";
        close FILE;
        chmod 0700, "$home/.ssh/copy.sh";

        mkdir "$home/.ssh/tmp";
        # create authorized_keys file to be appended to target
        if (-f "/etc/xCATMN") {    # if on Management Node
            copy("$home/.ssh/id_rsa.pub","$home/.ssh/tmp/authorized_keys");
        } else {
            copy("$home/.ssh/authorized_keys","$home/.ssh/tmp/authorized_keys");
        }
    }

    while (1) { 
        unless ($wait_node_num) {
            if ($next_status{LOGIN_RESPONSE} eq "RSPCONFIG_SSHCFG_REQUEST") {
                my $home = xCAT::Utils->getHomeDir("root");
                unlink "$home/.ssh/copy.sh";
                File::Path->remove_tree("$home/.ssh/tmp/");
            }
            last;
        }
        while (my ($response, $handle_id) = $async->wait_for_next_response) {
            deal_with_response($handle_id, $response);
        }
        while ((my $cpid = waitpid(-1, WNOHANG)) > 0) {
            if ($child_node_map{$cpid}) {
                my $node = $child_node_map{$cpid};
                my $rc = $? >> 8;
                if ($rc != 0) {
                    $wait_node_num--;
                } else {
                    if ($status_info{ $node_info{$node}{cur_status} }->{process}) {
                        $status_info{ $node_info{$node}{cur_status} }->{process}->($node, undef);
                    } else {
                        xCAT::SvrUtils::sendmsg([1,"Internal error, plase the check the process handler for current status "
                                    .$node_info{$node}{cur_status}."."], $callback, $node);
                        $wait_node_num--;
                    }

                }
                delete $child_node_map{$cpid};
            }
        }
        my @del;
        while (my ($k, $v) = each %node_wait) {
            if (time() >= $v) {
                if ($node_info{$k}{method} || $status_info{ $node_info{$k}{cur_status} }{method}) {
                    gen_send_request($k);
                } else {
                    xCAT::SvrUtils::sendmsg([1,"Internal error, plase the check the rest handler for current status "
                                .$node_info{$k}{cur_status}."."], $callback, $k);
                    $wait_node_num--;
                }
                push(@del, $k);
            }
        }
        foreach my $d (@del) {
            delete $node_wait{$d};
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

    if (scalar(@ARGV) >= 2 and ($command =~ /rpower|rinv|rvitals/)) {
        return ([ 1, "Only one option is supported at the same time for $command" ]);
    } elsif (scalar(@ARGV) == 0 and $command =~ /rpower|rspconfig|rflash/) {
        return ([ 1, "No option specified for $command" ]);
    } else { 
        $subcommand = $ARGV[0];
    }

    if ($command eq "rbeacon") { 
        unless ($subcommand =~ /^on$|^off$/) {
	    return ([ 1, "Only 'on' or 'off' is supported for OpenBMC managed nodes."]);
        }
    } elsif ($command eq "rpower") {
        unless ($subcommand =~ /^on$|^off$|^softoff$|^reset$|^boot$|^bmcreboot$|^bmcstate$|^status$|^stat$|^state$/) {
            return ([ 1, "Unsupported command: $command $subcommand" ]);
        }
        if ($subcommand =~ /^reset$|^boot$/) {
            $check = unsupported($callback); 
            if (ref($check) eq "ARRAY") { 
                @$check[1] = "Command $command $subcommand is not supported now.\nPlease run 'rpower <node> off' and then 'rpower <node> on' instead.";
                return $check;
            }
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
                return ([ 1, "Changing ipsrc value is currently not supported." ]) if ($key eq "ipsrc");
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
            } elsif ($subcommand =~ /^ip$|^netmask$|^gateway$|^hostname$|^vlan$|^ipsrc$/) {
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

    return if ($command eq "getopenbmccons");

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
            $next_status{RPOWER_SOFTOFF_REQUEST} = "RPOWER_SOFTOFF_RESPONSE";
        } elsif ($subcommand eq "reset") {
            $next_status{LOGIN_RESPONSE} = "RPOWER_STATUS_REQUEST";
            $next_status{RPOWER_STATUS_REQUEST} = "RPOWER_STATUS_RESPONSE";
            $next_status{RPOWER_STATUS_RESPONSE}{OFF} = "DO_NOTHING";
            $next_status{RPOWER_STATUS_RESPONSE}{ON} = "RPOWER_OFF_REQUEST";
            $next_status{RPOWER_OFF_REQUEST} = "RPOWER_OFF_RESPONSE";
            $next_status{RPOWER_OFF_RESPONSE} = "RPOWER_ON_REQUEST";
            $next_status{RPOWER_ON_REQUEST} = "RPOWER_ON_RESPONSE";
            $status_info{RPOWER_ON_RESPONSE}{argv} = "$subcommand";
        } elsif ($subcommand =~ /^bmcstate$|^status$|^state$|^stat$/) {
            $next_status{LOGIN_RESPONSE} = "RPOWER_STATUS_REQUEST";
            $next_status{RPOWER_STATUS_REQUEST} = "RPOWER_STATUS_RESPONSE";
            $status_info{RPOWER_STATUS_RESPONSE}{argv} = "$subcommand";
        } elsif ($subcommand eq "boot") {
            $next_status{LOGIN_RESPONSE} = "RPOWER_OFF_REQUEST";
            $next_status{RPOWER_OFF_REQUEST} = "RPOWER_OFF_RESPONSE";
            $next_status{RPOWER_OFF_RESPONSE} = "RPOWER_ON_REQUEST";
            $next_status{RPOWER_ON_REQUEST} = "RPOWER_ON_RESPONSE";
            $status_info{RPOWER_ON_RESPONSE}{argv} = "$subcommand";
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
        if ($$subcommands[-1] and $$subcommands[-1] eq "-p") {
            pop(@$subcommands);
            $status_info{RSETBOOT_ENABLE_REQUEST}{data} = '0';
            $status_info{RSETBOOT_SET_REQUEST}{init_url} = "$openbmc_project_url/control/host0/boot/attr/BootSource";
        }

        if (defined($$subcommands[0])) {
            $subcommand = $$subcommands[0];
        } else {
            $subcommand = "stat";
        }
        if ($subcommand =~ /^hd$|^net$|^cd$|^default$|^def$/) {
            if (defined($::OPENBMC_FW) && ($::OPENBMC_FW < 1738)) {
                #
                # In 1738, the endpount URL changed.  In order to support the older URL as a work around, allow for a environment
                # variable to change this value. 
                #
                $::RSETBOOT_URL_PATH = "boot_source";
                $status_info{RSETBOOT_SET_REQUEST}{init_url} = "$openbmc_project_url/control/host0/$::RSETBOOT_URL_PATH/attr/BootSource";
                $status_info{RSETBOOT_STATUS_REQUEST}{init_url} = "$openbmc_project_url/control/host0/$::RSETBOOT_URL_PATH";
                $next_status{LOGIN_RESPONSE} = "RSETBOOT_SET_REQUEST";
            } else {
                $next_status{LOGIN_RESPONSE} = "RSETBOOT_ENABLE_REQUEST";
                $next_status{RSETBOOT_ENABLE_REQUEST} = "RSETBOOT_ENABLE_RESPONSE";
                $next_status{RSETBOOT_ENABLE_RESPONSE} = "RSETBOOT_SET_REQUEST";
            }
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
            if ($subcommand =~ /^ip$|^netmask$|^gateway$|^hostname$|^vlan$|^ipsrc$/) {
                $next_status{LOGIN_RESPONSE} = "RSPCONFIG_GET_REQUEST";
                $next_status{RSPCONFIG_GET_REQUEST} = "RSPCONFIG_GET_RESPONSE";
                push @options, $subcommand;
            } elsif ($subcommand =~ /^sshcfg$/) {
                # Special processing to copy ssh keys, currently there is no REST API to do this.
                $next_status{LOGIN_RESPONSE} = "RSPCONFIG_SSHCFG_REQUEST";
                $next_status{RSPCONFIG_SSHCFG_REQUEST} = "RSPCONFIG_SSHCFG_RESPONSE";
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
        my @flash_arguments;

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
                push (@flash_arguments, $subcommand); 
            }
        }

        if (scalar @flash_arguments > 1) {
            my $flag = "";
            if ($delete) { $flag = "to delete"; }
            if ($activate) { $flag = "to activate"; }
            xCAT::SvrUtils::sendmsg([1, "More than one firmware specified $flag is currently not supported."], $callback);
            return 1;
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
                    $::UPLOAD_AND_ACTIVATE = 1;
                    $activate = 0;
                }

                if ($check_version | $::UPLOAD_AND_ACTIVATE) {
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
        if ($::UPLOAD_AND_ACTIVATE) {
            # Upload specified update file to BMC
            $next_status{LOGIN_RESPONSE} = "RFLASH_FILE_UPLOAD_REQUEST";
            $next_status{"RFLASH_FILE_UPLOAD_REQUEST"} = "RFLASH_FILE_UPLOAD_RESPONSE";
            $next_status{"RFLASH_FILE_UPLOAD_RESPONSE"} = "RFLASH_UPDATE_CHECK_ID_REQUEST";
            $next_status{"RFLASH_UPDATE_CHECK_ID_REQUEST"} = "RFLASH_UPDATE_CHECK_ID_RESPONSE";
            # 
            # This code is different from the "activate" flow above because the CHECK_ID_RESPONSE contains
            # the activation flow after we successfully obtain the ID for the firmware piece that was uploaded.  
            #
        }
    }

    return;
}

#-------------------------------------------------------
#
#=head3  get_functional_software_ids
#
#  Checks if the FW response data contains "functional" which 
#  indicates the actual software version currently running on 
#  the Server.  
#
#  Returns: reference to hash
#
#  =cut
#
#-------------------------------------------------------
sub get_functional_software_ids {
    my $response = shift;
    my %functional;

    #
    # Get the functional IDs to accurately mark the active running FW
    #
    if (${ $response->{data} }{'/xyz/openbmc_project/software/functional'} ) { 
        my %func_data = %{ ${ $response->{data} }{'/xyz/openbmc_project/software/functional'} };
        foreach ( @{$func_data{endpoints}} ) {
            my $fw_id = (split '/', $_)[-1];
            $functional{$fw_id} = 1;
        }
    }

    return \%functional;
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
    if (defined($status_info{ $node_info{$node}{cur_status} }{data})) {
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
        if (defined $status_info{RPOWER_STATUS_RESPONSE}{argv} and $status_info{RPOWER_STATUS_RESPONSE}{argv} =~ /bmcstate$/) {
            # Handle the special case to return "NotReady" if the BMC does not return a success response.
            # If the REST service is not up, it can't return "NotReady" itself, during reboot.:w
            $error = "BMC NotReady";
            xCAT::SvrUtils::sendmsg($error, $callback, $node);
            $wait_node_num--;
            return;    
        }
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
                #
                # For any invalid data that we can detect, provide a better response message
                #
                if ($node_info{$node}{cur_status} eq "RFLASH_UPDATE_ACTIVATE_RESPONSE") {
                    # If 403 is received for an activation, that means the activation ID is incorrect
                    $error = "Invalid ID provided to activate. Use the -l option to view valid firmware IDs.";
                } else {
                    $error = "$::RESPONSE_FORBIDDEN - This function is not yet available in OpenBMC firmware.";
                }
            } elsif ($response_info->{'data'}->{'description'} =~ /path or object not found: (.+)/) {
                #
                # For any invalid data that we can detect, provide a better response message
                #
                if ($node_info{$node}{cur_status} eq "RFLASH_DELETE_IMAGE_RESPONSE") { 
                    $error = "Invalid ID provided to delete.  Use the -l option to view valid firmware IDs.";
                } else {
                    $error = "Path or object not found: $1";
                }
            } else {
                $error = $response_info->{'data'}->{'description'};
            }
        }
        xCAT::SvrUtils::sendmsg([1, $error], $callback, $node);
        $wait_node_num--;
        return;    
    }

    if ($status_info{ $node_info{$node}{cur_status} }->{process}) {
        $status_info{ $node_info{$node}{cur_status} }->{process}->($node, $response);
    } else {
        xCAT::SvrUtils::sendmsg([1,"Internal error, check the process handler for current status $node_info{$node}{cur_status}"]);
        $wait_node_num--;
    }

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
        if ($node_info{$node}{method} || $status_info{ $node_info{$node}{cur_status} }{method}) {
            gen_send_request($node);
        } elsif ($status_info{ $node_info{$node}{cur_status} }->{process}) {
            $status_info{ $node_info{$node}{cur_status} }->{process}->($node, undef);
        }
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
            if ($status_info{RPOWER_ON_RESPONSE}{argv}) {
                xCAT::SvrUtils::sendmsg("$::POWER_STATE_RESET", $callback, $node);
            } else {
                if (defined($::OPENBMC_PWR) and ($::OPENBMC_PWR eq "YES")) {
                    xCAT::SvrUtils::sendmsg("$::STATUS_POWERING_ON", $callback, $node);
                } else {
                    xCAT::SvrUtils::sendmsg("$::POWER_STATE_ON", $callback, $node);
                }
            }
            $new_status{$::STATUS_POWERING_ON} = [$node];
        }
    } 

    if ($node_info{$node}{cur_status} =~ /^RPOWER_OFF_RESPONSE$|^RPOWER_SOFTOFF_RESPONSE$/) {
        if ($response_info->{'message'} eq $::RESPONSE_OK) {
            my $power_state = "$::POWER_STATE_OFF";
            if ($node_info{$node}{cur_status} eq "RPOWER_SOFTOFF_RESPONSE") {
                $power_state = "$::POWER_STATE_POWERING_OFF";
            }
            xCAT::SvrUtils::sendmsg("$power_state", $callback, $node) if (!$next_status{ $node_info{$node}{cur_status} });
            $new_status{$::STATUS_POWERING_OFF} = [$node];
        }
    }

    if ($node_info{$node}{cur_status} eq "RPOWER_RESET_RESPONSE") {
        if ($response_info->{'message'} eq $::RESPONSE_OK) {
            if (defined $status_info{RPOWER_RESET_RESPONSE}{argv} and $status_info{RPOWER_RESET_RESPONSE}{argv} =~ /bmcreboot$/) {
                xCAT::SvrUtils::sendmsg("BMC $::POWER_STATE_REBOOT", $callback, $node);
            }
            $new_status{$::STATUS_POWERING_ON} = [$node];
        }
    }

    xCAT_monitoring::monitorctrl::setNodeStatusAttributes(\%new_status, 1) if (%new_status);

    my $all_status;
    if ($node_info{$node}{cur_status} eq "RPOWER_STATUS_RESPONSE") { 
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

        if (defined($::OPENBMC_PWR) and ($::OPENBMC_PWR eq "YES")) {
            # Print this debug only if testing transition states 
            print "$node: DEBUG State CurrentBMCState=$bmc_state\n";
            print "$node: DEBUG State RequestedBMCTransition=$bmc_transition_state\n";
            print "$node: DEBUG State CurrentPowerState=$chassis_state\n";
            print "$node: DEBUG State RequestedPowerTransition=$chassis_transition_state\n";
            print "$node: DEBUG State CurrentHostState=$host_state\n";
            print "$node: DEBUG State RequestedHostTransition=$host_transition_state\n";
        }

        if (defined $status_info{RPOWER_STATUS_RESPONSE}{argv} and $status_info{RPOWER_STATUS_RESPONSE}{argv} =~ /bmcstate$/) { 
            my $bmc_short_state = (split(/\./, $bmc_state))[-1];
            xCAT::SvrUtils::sendmsg("BMC $bmc_short_state", $callback, $node);
        } else {
            if ($chassis_state =~ /Off$/) {
                # Chassis state is Off, but check if we can detect transition states
                if ((defined($::OPENBMC_PWR) and ($::OPENBMC_PWR eq "YES")) and
                        $host_state =~ /Off$/ and $host_transition_state =~ /On$/) {
                    xCAT::SvrUtils::sendmsg("$::POWER_STATE_POWERING_ON", $callback, $node);
                } else {
                    xCAT::SvrUtils::sendmsg("$::POWER_STATE_OFF", $callback, $node) if (!$next_status{ $node_info{$node}{cur_status} });
                }
                $all_status = $::POWER_STATE_OFF;
            } elsif ($chassis_state =~ /On$/) { 
                if ($host_state =~ /Off$/) {
                    # This is a debug scenario where the chassis is powered on but hostboot is not
                    xCAT::SvrUtils::sendmsg("$::POWER_STATE_ON_HOSTOFF", $callback, $node) if (!$next_status{ $node_info{$node}{cur_status} });
                    $all_status = $::POWER_STATE_ON_HOSTOFF;
                } elsif ($host_state =~ /Quiesced$/) {
                    xCAT::SvrUtils::sendmsg("$::POWER_STATE_QUIESCED", $callback, $node) if (!$next_status{ $node_info{$node}{cur_status} });
                    $all_status = $::POWER_STATE_ON;
                } elsif ($host_state =~ /Running$/) {
                    # Host State is Running (On), but if requested, check transition states 
                    if ((defined($::OPENBMC_PWR) and ($::OPENBMC_PWR eq "YES")) and
                           $host_transition_state =~ /Off$/ and $chassis_state =~ /On$/) {
                        xCAT::SvrUtils::sendmsg("$::POWER_STATE_POWERING_OFF", $callback, $node);
                        $all_status = $::POWER_STATE_POWERING_OFF;
                    } else {
                        xCAT::SvrUtils::sendmsg("$::POWER_STATE_ON", $callback, $node) if (!$next_status{ $node_info{$node}{cur_status} });
                        $all_status = $::POWER_STATE_ON;
                    }
                } else {
                    xCAT::SvrUtils::sendmsg("Unexpected host state=$host_state", $callback, $node) if (!$next_status{ $node_info{$node}{cur_status} });
                    $all_status = $::POWER_STATE_ON;
                }
            } else {
                xCAT::SvrUtils::sendmsg("Unexpected chassis state=$chassis_state", $callback, $node) if (!$next_status{ $node_info{$node}{cur_status} });
                $all_status = $::POWER_STATE_ON;
            }
        }
    }

    if ($next_status{ $node_info{$node}{cur_status} }) {
        if ($node_info{$node}{cur_status} eq "RPOWER_STATUS_RESPONSE") {
            if ($all_status eq "$::POWER_STATE_OFF") {
                if ($next_status{ $node_info{$node}{cur_status} }{OFF} eq "DO_NOTHING") {
                    xCAT::SvrUtils::sendmsg("$::POWER_STATE_RESET", $callback, $node);
                    $node_info{$node}{cur_status} = "";
                    $wait_node_num--;
                    return;
                } else {
                    $node_info{$node}{cur_status} = $next_status{ $node_info{$node}{cur_status} }{OFF};
                }            
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

    # Get the functional IDs to accurately mark the active running FW
    my $functional = get_functional_software_ids($response_info);

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
                if ( (%{$functional} and exists($functional->{$sw_id}) ) or 
                     (!%{$functional} and $activation_value =~ "Active" and $priority_value == 0) or 
                      $::VERBOSE ) {
                    #
                    # The space below between "Firmware Product Version:" and $content{Version} is intentional
                    # to cause the sorting of this line before any additional info lines 
                    #
                    $content_info = "$purpose_value Firmware Product:   $content{Version} ($activation_value)";
                    my $indicator = "*";
                    if ($priority_value == 0 and %{$functional} and !exists($functional->{$sw_id})) {
                        # indicate that a reboot is needed if priority = 0 and it's not in the functional list
                        $indicator = "+";
                    }
                    $content_info .= $indicator;
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
        my $one_time_enabled;
        my $bootsource;
        if (defined($::OPENBMC_FW) && ($::OPENBMC_FW < 1738)) {
            $bootsource = $response_info->{'data'}->{BootSource};
        } else {
            foreach my $key_url (keys %{$response_info->{data}}) {
                my %content = %{ ${ $response_info->{data} }{$key_url} };
                if ($key_url =~ /boot\/one_time/) {
                    $one_time_enabled = $content{Enabled};
                    $bootsource = $content{BootSource} if ($one_time_enabled);
                } elsif ($key_url =~ /\/boot$/) {
                    $bootsource = $content{BootSource} unless ($one_time_enabled);
                }
            }
        }

        if ($bootsource =~ /Disk$/) {
            xCAT::SvrUtils::sendmsg("Hard Drive", $callback, $node);
        } elsif ($bootsource =~ /Network$/) {
            xCAT::SvrUtils::sendmsg("Network", $callback, $node);
        } elsif ($bootsource =~ /ExternalMedia$/) {
            xCAT::SvrUtils::sendmsg("CD/DVD", $callback, $node);
        } elsif ($bootsource =~ /Default$/) {
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
            xCAT::SvrUtils::sendmsg("$::NO_ATTRIBUTES_RETURNED", $callback, $node) if (!%output);
            foreach my $key ( sort { $b <=> $a } keys %output) {
                xCAT::MsgUtils->message("I", { data => ["$node: $output{$key}"] }, $callback) if ($output{$key});
                $count++;
                last if ($entry_string ne "all" and $count >= $entry_num); 
            }
        } else {
            xCAT::SvrUtils::sendmsg("$::NO_ATTRIBUTES_RETURNED", $callback, $node) if (!%output);
            foreach my $key (sort keys %output) {
                xCAT::MsgUtils->message("I", { data => ["$node: $output{$key}"] }, $callback) if ($output{$key});
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
        my $vlan            = 0;
        my $hostname        = "";
        my $default_gateway = "n/a";
        my $adapter_id      = "n/a";
        my $ipsrc           = "n/a";
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


            ($path, $adapter_id) = (split(/\/ipv4\//, $key_url));
            
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
                if (defined($content{Origin})) {
                    $ipsrc = $content{Origin};
                    $ipsrc =~ s/^.*\.(\w+)/$1/;
                }
                 
                if (defined($response_info->{data}->{$path}->{Id})) {
                    $vlan = $response_info->{data}->{$path}->{Id};
                }
            }
        }
        if ($error) {
            # Display error message once, regardless of how many subcommands were specified
            push @output, $error;
        }
        else {
            foreach my $opt (split /,/,$grep_string) {
                if ($opt eq "ip") {
                    push @output, "BMC IP: $address"; 
                } elsif ($opt eq "ipsrc") {
                    push @output, "BMC IP Source: $ipsrc";
                } elsif ($opt eq "netmask") {
                    if ($address) {
                        my $decimal_mask = (2 ** $prefix - 1) << (32 - $prefix);
                        my $netmask = join('.', unpack("C4", pack("N", $decimal_mask)));
                        push @output, "BMC Netmask: " . $netmask; 
                    }
                } elsif ($opt eq "gateway") {
                    push @output, "BMC Gateway: $gateway (default: $default_gateway)";
                } elsif ($opt eq "vlan") {
                    if ($vlan) { 
                        push @output, "BMC VLAN ID: $vlan";
                    } else {
                        push @output, "BMC VLAN ID: Disabled";
                    }
                } elsif ($opt eq "hostname") {
                    push @output, "BMC Hostname: $hostname";
                }
            }
        }

        xCAT::SvrUtils::sendmsg("$_", $callback, $node) foreach (@output);
    }

    if ($node_info{$node}{cur_status} eq "RSPCONFIG_SET_RESPONSE") {
        if ($response_info->{'message'} eq $::RESPONSE_OK) {
            xCAT::SvrUtils::sendmsg("BMC Setting Hostname...", $callback, $node);
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

  Deal with request and response of rspconfig command for sscfg subcommand.
  Input:
        $node: nodename of current response
        $response: Async return response

=cut

#-------------------------------------------------------
sub rspconfig_sshcfg_response {
    my $node = shift;
    my $response = shift;

    if ($node_info{$node}{cur_status} eq "RSPCONFIG_SSHCFG_REQUEST") {
        my $child = xCAT::Utils->xfork;
        if (!defined($child)) {
            xCAT::SvrUtils::sendmsg("Failed to fork child process for rspconfig sshcfg.", $callback, $node);
            sleep(1)
        } elsif ($child == 0) {
            exit(sshcfg_process($node))
        } else {
            $child_node_map{$child} = $node;
        }
    }

    if ($next_status{ $node_info{$node}{cur_status} }) {
        $node_info{$node}{cur_status} = $next_status{ $node_info{$node}{cur_status} };
        if ($node_info{$node}{method} || $status_info{ $node_info{$node}{cur_status} }{method}) {
            gen_send_request($node);
        }
    } else {
        $wait_node_num--;
    }
}

#-------------------------------------------------------

=head3  rspconfig_process

  Append contents of id_rsa.pub file from management node to
  the authorized_keys file on BMC
  Input:
        $node: nodename of current response

=cut

#-------------------------------------------------------
sub sshcfg_process {
    my $node = shift;

    my $bmcip = $node_info{$node}{bmc};
    my $userid = $node_info{$node}{username};
    my $userpw = $node_info{$node}{password};

    #backup the previous $ENV{DSH_REMOTE_PASSWORD},$ENV{'DSH_FROM_USERID'}
    my $bak_DSH_REMOTE_PASSWORD=$ENV{'DSH_REMOTE_PASSWORD'};
    my $bak_DSH_FROM_USERID=$ENV{'DSH_FROM_USERID'};

    #xCAT::RemoteShellExp->remoteshellexp dependes on environment
    #variables $ENV{DSH_REMOTE_PASSWORD},$ENV{'DSH_FROM_USERID'}
    $ENV{'DSH_REMOTE_PASSWORD'}=$userpw;
    $ENV{'DSH_FROM_USERID'}=$userid;

    #send ssh public key from MN to bmc
    my $rc=xCAT::RemoteShellExp->remoteshellexp("s",$callback,"/usr/bin/ssh",$bmcip,10);
    if ($rc) {
        xCAT::SvrUtils::sendmsg("Error copying ssh keys to $bmcip\n", $callback, $node);
    }else{
        #check whether the ssh keys has been sent successfully
        $rc=xCAT::RemoteShellExp->remoteshellexp("t",$callback,"/usr/bin/ssh",$bmcip,10);
        if ($rc) {
            xCAT::SvrUtils::sendmsg("Testing the ssh connection to $bmcip failed. Please rerun rspconfig command.", $callback, $node);
        }
        else {
            xCAT::SvrUtils::sendmsg("ssh keys copied to $bmcip", $callback, $node);
        }
    }

    #restore env variables
    $ENV{'DSH_REMOTE_PASSWORD'}=$bak_DSH_REMOTE_PASSWORD;
    $ENV{'DSH_FROM_USERID'}=$bak_DSH_FROM_USERID;

    return $rc;
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
    my $response_info;
    if (defined($response)) {
        $response_info = decode_json $response->content;
    }
    my $update_id;
    my $update_activation = "Unknown";
    my $update_purpose;
    my $update_version;
    my $update_priority = -1;

    if ($node_info{$node}{cur_status} eq "RFLASH_LIST_RESPONSE") {
        # Get the functional IDs to accurately mark the active running FW
        my $functional = get_functional_software_ids($response_info);
        if (!%{$functional}) {
            # Inform users that the older firmware levels does not correctly reflect Active version
            xCAT::SvrUtils::sendmsg("WARNING, The current firmware is unable to detect running firmware version.", $callback, $node);
        }

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
            if (exists($functional->{$update_id}) ) {
                #
                # If the firmware ID exists in the hash, this indicates the really active running FW
                #
                $update_activation = $update_activation . "(*)";
            } elsif ($update_priority == 0) {
                # Priority attribute of 0 indicates the firmware to be activated on next boot 
                my $indicator = "(+)";
                if (!%{$functional}) {
                    # cannot detect, so mark firmware as Active
                    $indicator = "(*)";
                }
                $update_activation = $update_activation . $indicator;
                $update_priority = -1; # Reset update priority for next loop iteration
            }
            xCAT::SvrUtils::sendmsg(sprintf("%-8s %-7s %-10s %s", $update_id, $update_purpose, $update_activation, $update_version), $callback, $node);
        }
        xCAT::SvrUtils::sendmsg("", $callback, $node); #Separate output in case more than 1 endpoint
    }
    if ($node_info{$node}{cur_status} eq "RFLASH_FILE_UPLOAD_REQUEST") {
        #
        # Special processing for file upload
        #
        # Unable to form a proper file upload request to the BMC, it fails with: 405 Method Not Allowed
        # For now, always upload using curl commands.  
        #
        # TODO: Remove this block when proper request can be generated
        #
        if ($::UPLOAD_FILE) {
            my $child = xCAT::Utils->xfork;
            if (!defined($child)) {
                xCAT::SvrUtils::sendmsg("Failed to fork child process to upload firmware image.", $callback, $node);
                sleep(1)
            } elsif ($child == 0) {
                exit(rflash_upload($node, $callback))
            } else {
                $child_node_map{$child} = $node;
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
            xCAT::SvrUtils::sendmsg([1,"Firmware activation Failed."], $callback, $node);
            $wait_node_num--;
            return;
        } 
        elsif ($activation_state =~ /Software.Activation.Activations.Active/) { 
            if (scalar($priority_state) == 0) {
                # Activation state of active and priority of 0 indicates the activation has been completed
                xCAT::SvrUtils::sendmsg("Firmware activation Successful.", $callback, $node);
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
            xCAT::SvrUtils::sendmsg("Activating firmware . . . $progress_state\%", $callback, $node);
            # Activation still going, sleep for a bit, then print the progress value
            # Set next state to come back here to chect the activation status again.
            retry_after($node, "RFLASH_UPDATE_CHECK_STATE_REQUEST", 15);
            return;
        }
    }

    if ($node_info{$node}{cur_status} eq "RFLASH_UPDATE_CHECK_ID_RESPONSE") {
        my $activation_state;
        my $progress_state;
        my $priority_state;
        my $found_match = 0;
        my $debugmsg;

        if ($xcatdebugmode) {
            $debugmsg = "CHECK_ID_RESPONSE: Looking for software ID: $::UPLOAD_FILE_VERSION...";
            process_debug_info($node, $debugmsg);
        }
        # Look through all the software entries and find the id of the one that matches
        # the version of the uploaded file. Once found, set up request/response hash entries
        # to activate that image.
        foreach my $key_url (keys %{$response_info->{data}}) {
            my %content = %{ ${ $response_info->{data} }{$key_url} };

            $update_id = (split(/\//, $key_url))[ -1 ];
            if (defined($content{Version}) and $content{Version}) {
                $update_version = $content{Version};
                if ($xcatdebugmode) {
                    $debugmsg = "CHECK_ID_RESPONSE: key_url=$key_url version=$update_version";
                    process_debug_info($node, $debugmsg);
                }
                if ($update_version eq $::UPLOAD_FILE_VERSION) {
                    $found_match = 1;
                    # Found a match of uploaded file version with the image in software/enumerate

                    # Set the image id for the activation request
                    $status_info{RFLASH_UPDATE_ACTIVATE_REQUEST}{init_url} =
                       $::SOFTWARE_URL . "/$update_id/attr/RequestedActivation";
                    $status_info{RFLASH_UPDATE_CHECK_STATE_REQUEST}{init_url} =
                       $::SOFTWARE_URL . "/$update_id";
                    $status_info{RFLASH_SET_PRIORITY_REQUEST}{init_url} =
                       $::SOFTWARE_URL . "/$update_id/attr/Priority";

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
        if (!$found_match) {
            if (!exists($node_info{node}{upload_wait_attemp})) {
                $node_info{node}{upload_wait_attemp} = $::UPLOAD_WAIT_ATTEMPT;
            }
            if($node_info{node}{upload_wait_attemp} > 0) {
                $node_info{node}{upload_wait_attemp} --;
                xCAT::SvrUtils::sendmsg("Could not find ID for firmware $::UPLOAD_FILE_VERSION to activate, waiting $::UPLOAD_WAIT_INTERVAL seconds and retry...", $callback, $node);
                retry_after($node, "RFLASH_UPDATE_CHECK_ID_REQUEST", $::UPLOAD_WAIT_INTERVAL);
                return;
            } else {
                xCAT::SvrUtils::sendmsg([1,"Could not find firmware $::UPLOAD_FILE_VERSION after waiting $::UPLOAD_WAIT_TOTALTIME seconds."], $callback, $node);
                $wait_node_num--;
                return;
            }
        }
    }

    if ($node_info{$node}{cur_status} eq "RFLASH_DELETE_IMAGE_RESPONSE") {
            xCAT::SvrUtils::sendmsg("Firmware removed", $callback, $node);
    }

    if ($next_status{ $node_info{$node}{cur_status} }) {
        $node_info{$node}{cur_status} = $next_status{ $node_info{$node}{cur_status} };
        if ($node_info{$node}{method} || $status_info{ $node_info{$node}{cur_status} }{method}) {
            gen_send_request($node);
        }
    } else {
        $wait_node_num--;
    }
    return;
}

sub rflash_upload {
    my ($node, $callback) = @_;
    my $request_url = "$http_protocol://" . $node_info{$node}{bmc};
    my $content_login = '{ "data": [ "' . $node_info{$node}{username} .'", "' . $node_info{$node}{password} . '" ] }';
    my $content_logout = '{ "data": [ ] }';
    my $cjar_id = "/tmp/_xcat_cjar.$node";
    # curl commands
    my $curl_login_cmd  = "curl -c $cjar_id -k -H 'Content-Type: application/json' -X POST $request_url/login -d '" . $content_login . "'";
    my $curl_logout_cmd = "curl -b $cjar_id -k -H 'Content-Type: application/json' -X POST $request_url/logout -d '" . $content_logout . "'";
    my $curl_upload_cmd = "curl -b $cjar_id -k -H 'Content-Type: application/octet-stream' -X PUT -T " . $::UPLOAD_FILE . " $request_url/upload/image/";

    # Try to login
    my $curl_login_result = `$curl_login_cmd`;
    my $h = from_json($curl_login_result); # convert command output to hash
    if ($h->{message} eq $::RESPONSE_OK) {
        # Login successfull, upload the file
        xCAT::SvrUtils::sendmsg("Uploading $::UPLOAD_FILE ...", $callback, $node);
        if ($xcatdebugmode) {
            my $debugmsg = "RFLASH_FILE_UPLOAD_RESPONSE: CMD: $curl_upload_cmd";
            process_debug_info($node, $debugmsg);
        }
        my $curl_upload_result = `$curl_upload_cmd`;
        $h = from_json($curl_upload_result); # convert command output to hash
        if ($h->{message} eq $::RESPONSE_OK) {
            # Upload successful, display message
            if ($::UPLOAD_AND_ACTIVATE) {
                xCAT::SvrUtils::sendmsg("Firmware upload successful. Attempting to activate firmware: $::UPLOAD_FILE_VERSION", $callback, $node);
            } else {
                xCAT::SvrUtils::sendmsg("Firmware upload successful. Use -l option to list.", $callback, $node);
            }
            # Try to logoff, no need to check result, as there is nothing else to do if failure
            my $curl_logout_result = `$curl_logout_cmd`;
        }
        else {
            xCAT::SvrUtils::sendmsg("Failed to upload update file $::UPLOAD_FILE :" . $h->{message} . " - " . $h->{data}->{description}, $callback, $node);
            return 1;
        }
    }
    else {
        xCAT::SvrUtils::sendmsg("Unable to login :" . $h->{message} . " - " . $h->{data}->{description}, $callback, $node);
        return 1;
    }
    return 0;
}
1;
