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
use LWP::UserAgent;
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
use xCAT::Utils qw/natural_sort_cmp/;

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
$::UPLOAD_PNOR              = "";
$::UPLOAD_PNOR_VERSION      = "";
$::UPLOAD_FILE_HASH_ID      = "";
$::UPLOAD_PNOR_HASH_ID      = "";
$::RSETBOOT_URL_PATH        = "boot";
# To improve the output to users, store this value as a global
$::UPLOAD_AND_ACTIVATE      = 0;
$::UPLOAD_ACTIVATE_STREAM   = 0;
$::RFLASH_STREAM_NO_HOST_REBOOT = 0;
$::TAR_FILE_PATH = "";
$::NO_ATTRIBUTES_RETURNED   = "No attributes returned from the BMC.";

$::UPLOAD_WAIT_ATTEMPT      = 6;
$::UPLOAD_WAIT_INTERVAL     = 10;
$::UPLOAD_WAIT_TOTALTIME    = int($::UPLOAD_WAIT_ATTEMPT*$::UPLOAD_WAIT_INTERVAL);

$::RPOWER_CHECK_INTERVAL    = 2;
$::RPOWER_MAX_RETRY         = 30;

$::BMC_MAX_RETRY = 20;
$::BMC_CHECK_INTERVAL = 15;

$::RSPCONFIG_DUMP_INTERVAL  = 15;
$::RSPCONFIG_DUMP_MAX_RETRY = 20;
$::RSPCONFIG_DUMP_WAIT_TOTALTIME = int($::RSPCONFIG_DUMP_INTERVAL*$::RSPCONFIG_DUMP_MAX_RETRY);
$::RSPCONFIG_WAIT_VLAN_DONE = 15;
$::RSPCONFIG_WAIT_IP_DONE   = 3;
$::RSPCONFIG_DUMP_CMD_TIME  = 0;
$::RSPCONFIG_CONFIGURED_API_KEY  = -1;

$::XCAT_LOG_DIR             = "/var/log/xcat";
$::RAS_POLICY_TABLE         = "/opt/ibm/ras/lib/policyTable.json";
$::XCAT_LOG_RFLASH_DIR      = $::XCAT_LOG_DIR . "/rflash/";
$::XCAT_LOG_DUMP_DIR        = $::XCAT_LOG_DIR . "/dump/";

unless (-d $::XCAT_LOG_RFLASH_DIR) {
    mkpath($::XCAT_LOG_RFLASH_DIR);
}
unless (-d $::XCAT_LOG_DUMP_DIR) {
    mkpath($::XCAT_LOG_DUMP_DIR);
}

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
my %fw_tar_files;
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
    LOGIN_REQUEST_GENERAL  => {
        method         => "POST",
        init_url       => "/login",
    },
    LOGIN_RESPONSE     => {
        process        => \&login_response,
    },
    LOGIN_RESPONSE_GENERAL => {
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
    RFLASH_UPDATE_HOST_ACTIVATE_REQUEST  => {
        method         => "PUT",
        init_url       => "$openbmc_project_url/software",
        data           => "xyz.openbmc_project.Software.Activation.RequestedActivations.Active",
    },
    RFLASH_UPDATE_ACTIVATE_RESPONSE => {
        process        => \&rflash_response,
    },
    RFLASH_UPDATE_HOST_ACTIVATE_RESPONSE => {
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
    RPOWER_CHECK_REQUEST  => {
        method         => "GET",
        init_url       => "$openbmc_project_url/state/enumerate",
    },
    RPOWER_BMC_STATUS_REQUEST  => {
        method         => "GET",
        init_url       => "$openbmc_project_url/state/enumerate",
    },
    RPOWER_BMC_CHECK_REQUEST  => {
        method         => "GET",
        init_url       => "$openbmc_project_url/state/enumerate",
    },
    RPOWER_BMC_STATUS_RESPONSE => {
        process        => \&rpower_response,
    }, 
    RPOWER_BMC_CHECK_RESPONSE => {
        process        => \&rpower_response,
    },
    RPOWER_CHECK_RESPONSE => {
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
    RSPCONFIG_GET_NIC_REQUEST => {
        method         => "GET",
        init_url       => "$openbmc_project_url/network/enumerate",
    },
    RSPCONFIG_GET_NIC_RESPONSE => {
        process        => \&rspconfig_response,
    },
    RSPCONFIG_SET_PASSWD_REQUEST => {
        method         => "POST",
        init_url       => "/xyz/openbmc_project/user/root/action/SetPassword",
        data           => "",
    },
    "RSPCONFIG_PASSWD_VERIFY" => {
        process        => \&rspconfig_response,
    },
    RSPCONFIG_SET_HOSTNAME_REQUEST => {
        method         => "PUT",
        init_url       => "$openbmc_project_url/network/config/attr/HostName",
        data           => "[]",
    },
    RSPCONFIG_SET_NTPSERVERS_REQUEST => {
        method         => "PUT",
        init_url       => "$openbmc_project_url/network/#NIC#/attr/NTPServers",
        data           => "[]",
    },
    RSPCONFIG_SET_RESPONSE => {
        process        => \&rspconfig_response,
    },
    RSPCONFIG_IPOBJECT_REQUEST => {
        method         => "POST",
        init_url       => "$openbmc_project_url/network/#NIC#/action/IP",
        data           => "",
    },
    RSPCONFIG_IPOBJECT_RESPONSE => {
        process        => \&rspconfig_response,
    },
    RSPCONFIG_VLAN_REQUEST  => {
        method         => "POST",
        init_url       => "$openbmc_project_url/network/action/VLAN",
        data           => "",
    },
    RSPCONFIG_VLAN_RESPONSE => {
        process        => \&rspconfig_response,
    },
    RSPCONFIG_CHECK_REQUEST  => {
        method         => "GET",
        init_url       => "$openbmc_project_url/network/enumerate",
    },
    RSPCONFIG_CHECK_RESPONSE => {
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
    RSPCONFIG_DHCPDIS_REQUEST => {
        method         => "PUT",
        init_url       => "$openbmc_project_url/network/#NIC#/attr/DHCPEnabled",
        data           => 0,
    },
    RSPCONFIG_DHCPDIS_RESPONSE => {
        process        => \&rspconfig_response,
    },
    RSPCONFIG_DELETE_REQUEST => {
        method         => "DELETE",
        init_url       => "",
    },
    RSPCONFIG_DELETE_RESPONSE => {
        process        => \&rspconfig_response,
    },
    RSPCONFIG_PRINT_BMCINFO => {
        process        => \&rspconfig_response,
    },
    RSPCONFIG_SSHCFG_REQUEST => {
        process        => \&rspconfig_sshcfg_response,
    },
    RSPCONFIG_SSHCFG_RESPONSE => {
        process        => \&rspconfig_sshcfg_response,
    },
    RSPCONFIG_CLEAR_GARD_REQUEST => {
        method         => "POST",
        init_url       => "/org/open_power/control/gard/action/Reset",
        data           => "[]", 
    }, 
    RSPCONFIG_CLEAR_GARD_RESPONSE => {
        process        => \&rspconfig_response,
    },
    RSPCONFIG_DUMP_LIST_REQUEST => {
        method         => "GET",
        init_url       => "$openbmc_project_url/dump/enumerate",
    },
    RSPCONFIG_DUMP_LIST_RESPONSE => {
        process        => \&rspconfig_dump_response,
    },
    RSPCONFIG_DUMP_CHECK_RESPONSE => {
        process        => \&rspconfig_dump_response,
    },
    RSPCONFIG_DUMP_CREATE_REQUEST => {
        method         => "POST",
        init_url       => "$openbmc_project_url/dump/action/CreateDump",
        data           => "[]",
    },
    RSPCONFIG_DUMP_CREATE_RESPONSE => {
        process        => \&rspconfig_dump_response,
    },
    RSPCONFIG_DUMP_CLEAR_REQUEST => {
        method         => "POST",
        init_url       => "$openbmc_project_url/dump/entry/#ID#/action/Delete",
        data           => "[]",
    },
    RSPCONFIG_DUMP_CLEAR_ALL_REQUEST => {
        method         => "POST",
        init_url       => "$openbmc_project_url/dump/action/DeleteAll",
        data           => "[]",
    },
    RSPCONFIG_DUMP_CLEAR_RESPONSE => {
        process        => \&rspconfig_dump_response,
    },
    RSPCONFIG_DUMP_DOWNLOAD_REQUEST => {
        init_url       => "download/dump/#ID#",
        process        => \&rspconfig_dump_response,
    },
    RSPCONFIG_DUMP_DOWNLOAD_RESPONSE => {
        process        => \&rspconfig_dump_response,
    },
    RVITALS_REQUEST => {
        method         => "GET",
        init_url       => "$openbmc_project_url/sensors/enumerate",
    },
    RVITALS_RESPONSE => {
        process        => \&rvitals_response,
    },
    RVITALS_LEDS_REQUEST => {
        method         => "GET",
        init_url       => "$openbmc_project_url/led/physical/enumerate",
    },
    RVITALS_LEDS_RESPONSE => {
        process        => \&rvitals_response,
    },
    RSPCONFIG_API_CONFIG_ON_REQUEST  => {
        method         => "PUT",
        init_url       => "$openbmc_project_url", 
        data           => "true",
    },
    RSPCONFIG_API_CONFIG_ON_RESPONSE => {
        process        => \&rspconfig_api_config_response,
    },
    RSPCONFIG_API_CONFIG_OFF_REQUEST  => {
        method         => "PUT",
        init_url       => "$openbmc_project_url",
        data           => "false",
    },
    RSPCONFIG_API_CONFIG_OFF_RESPONSE => {
        process        => \&rspconfig_api_config_response,
    },
    RSPCONFIG_API_CONFIG_QUERY_REQUEST  => {
        method         => "GET",
        init_url       => "$openbmc_project_url",
    },
    RSPCONFIG_API_CONFIG_QUERY_RESPONSE => {
        process        => \&rspconfig_api_config_response,
    },
);

# Setup configured subcommand. Currently only rspconfig is supported and only for boolean commands.
# For example: rspconfig <subcommand>
#              rspconfig <subcommand>=0
#              rspconfig <subcommand>=1
#
#
my %api_config_info = (
    RSPCONFIG_AUTO_REBOOT => {
        command      => "rspconfig",
        url          => "/control/host0/auto_reboot",
        attr_url     => "AutoReboot",
        display_name => "AutoReboot",
        type         => "boolean",
        subcommand   => "autoreboot",
    },
    RSPCONFIG_POWERSUPPLY_REDUNDENCY => {
        command      => "rspconfig",
        url          => "/sensors/chassis/PowerSupplyRedundancy",
        attr_url     => "PowerSupplyRedundency",
        display_name => "PowerSupplyRedundency",
        type         => "boolean",
        subcommand   => "powersupplyredundency",
    },
);

$::RESPONSE_OK                  = "200 OK";
$::RESPONSE_SERVER_ERROR        = "500 Internal Server Error";
$::RESPONSE_SERVICE_UNAVAILABLE = "503 Service Unavailable";
$::RESPONSE_FORBIDDEN           = "403 Forbidden";
$::RESPONSE_NOT_FOUND           = "404 Not Found";
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

my %login_pid_node; # used in process_request, record login fork pid map

my $event_mapping = "";

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

    # Provide a way to change to python code before formal release
    if (ref($request->{environment}) eq 'ARRAY' and ref($request->{environment}->[0]->{XCAT_OPENBMC_PYTHON}) eq 'ARRAY') {
        $::OPENBMC_PYTHON = $request->{environment}->[0]->{XCAT_OPENBMC_PYTHON}->[0];
    } elsif (ref($request->{environment}) eq 'ARRAY') {
        $::OPENBMC_PYTHON = $request->{environment}->[0]->{XCAT_OPENBMC_PYTHON};
    } else {
        $::OPENBMC_PYTHON = $request->{environment}->{XCAT_OPENBMC_PYTHON};
    }
    ##############################################

    # if env XCAT_OPENBMC_PYTHON is 'YES', run python code
    if (defined($::OPENBMC_PYTHON) and $::OPENBMC_PYTHON eq "YES") {
        $request = {};
        return;
    }

    $callback  = shift;

    if ($::XCATSITEVALS{xcatdebugmode}) { $xcatdebugmode = $::XCATSITEVALS{xcatdebugmode} }

    if ($xcatdebugmode) {
        process_debug_info("OpenBMC");
    }

    my $command   = $request->{command}->[0];
    my $noderange = $request->{node};
    my $extrargs  = $request->{arg};
    my @exargs    = ($request->{arg});
    my @requests;
    $::cwd = $request->{cwd}->[0];
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

=head3  retry_check_times

    The request will be delayed for the given time and then
    send the reqeust based on the BMC status after BMCreboot.

=cut

#-------------------------------------------------------
sub retry_check_times {
    my ($node, $request_status, $check_type, $wait_time, $response_status) = @_;
    if ($node_info{$node}{$check_type} > 0) {
        $node_info{$node}{$check_type}--;
        if ($node_info{$node}{wait_start}) {
            $node_info{$node}{wait_end} = time();
        } else {
            $node_info{$node}{wait_start} = time();
        }
        my $retry_msg = "Retry BMC state, wait for $wait_time seconds ...";
        xCAT::MsgUtils->message("I", { data => ["$node: $retry_msg"] }, $callback);
        if ($response_status ne $::RESPONSE_SERVICE_UNAVAILABLE) {
            my $login_url = "$http_protocol://$node_info{$node}{bmc}/login";
            my $content = '[ "' . $node_info{$node}{username} .'", "' . $node_info{$node}{password} . '" ]';
            $status_info{LOGIN_REQUEST_GENERAL}{data} = $content;
            $node_info{$node}{cur_status} = "LOGIN_REQUEST_GENERAL";
            $node_wait{$node} = time() + $wait_time;
            return;
        }
 
        $node_info{$node}{cur_status} = $request_status;
        $node_wait{$node} = time() + $wait_time;
        return;
   } else {
        my $wait_time_X = $node_info{$node}{wait_end} - $node_info{$node}{wait_start};
        my $msg="Error: Sent bmcreboot but state did not change to BMC Ready after waiting $wait_time_X seconds. (State=BMC NotReady).";
        xCAT::SvrUtils::sendmsg([1, $msg], $callback, $node);
        $node_info{$node}{cur_status} = "";
        $wait_node_num--;
        return;
   }
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

    my $login_url;
    my $handle_id;
    my $content;
    my @nodes_login = keys %node_info;
    $wait_node_num = @nodes_login;
    my $child_num;
    my %valid_nodes = ();

    if ($request->{command}->[0] eq "getopenbmccons") {
        foreach my $node (keys %node_info) {
            my $donargs = [ $node,$node_info{$node}{bmc},$node_info{$node}{username}, $node_info{$node}{password}];
            getopenbmccons($donargs, $callback);
        }
        return;
    }

    my $max_child_num = 64;
    my $for_num = ($wait_node_num < $max_child_num) ? $wait_node_num : $max_child_num;
    for (my $i = 0; $i < $for_num; $i++) {
        my $node = shift @nodes_login;
        my $rst_fork = fork_process_login($node);
        $child_num++ unless($rst_fork);
    }

    while (1) {
        last if ($child_num == 0 and !@nodes_login);
        my $cpid;
        while (($cpid = waitpid(-1, WNOHANG)) > 0) {
            if ($login_pid_node{$cpid}) {
                $child_num--;
                my $node = $login_pid_node{$cpid};
                my $rc = $? >> 8;
                if ($rc == 0) {
                    $valid_nodes{$node} = 1;
                }
                delete $login_pid_node{$cpid};
            }
        }
        if (@nodes_login) {
            if ($child_num < $max_child_num) {
                my $node = shift @nodes_login;
                my $rst_fork = fork_process_login($node);
                $child_num++ unless($rst_fork);
            }
        }
    }

    foreach my $node (keys %node_info) {
        if (!$valid_nodes{$node}) {
            xCAT::SvrUtils::sendmsg([1, "BMC did not respond. Validate BMC configuration and retry the command."], $callback, $node);
            $wait_node_num--;
            next;
        }
        if ($next_status{LOGIN_RESPONSE} eq "RSPCONFIG_SET_HOSTNAME_REQUEST" and $status_info{RSPCONFIG_SET_HOSTNAME_REQUEST}{data} =~ /^\*$/) {
            if ($node_info{$node}{bmc} =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/) {
                my $info_msg = "Invalid OpenBMC Hostname $node_info{$node}{bmc}, can't set to OpenBMC";
                xCAT::SvrUtils::sendmsg($info_msg, $callback, $node);
                $wait_node_num--;
                next; 
            }
        }
      
        $login_url = "$http_protocol://$node_info{$node}{bmc}/login";
        $content = '{ "data": [ "' . $node_info{$node}{username} .'", "' . $node_info{$node}{password} . '" ] }';
        if ($xcatdebugmode) {
            my $debug_info = "curl -k -c cjar -H \"Content-Type: application/json\" -d '{ \"data\": [\"$node_info{$node}{username}\", \"xxxxxx\"] }' $login_url";
            process_debug_info($node, $debug_info);
        }
        $handle_id = xCAT::OPENBMC->new($async, $login_url, $content);
        $handle_id_node{$handle_id} = $node;
        $node_info{$node}{cur_status} = $next_status{ $node_info{$node}{cur_status} };
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
            if ($event_mapping and (ref($event_mapping) ne "HASH")) {
                xCAT::SvrUtils::sendmsg("$event_mapping, install the OpenBMC RAS package to obtain more details logging messages.", $callback);
            }
            if ($next_status{LOGIN_RESPONSE} eq "RSPCONFIG_SSHCFG_REQUEST") {
                my $home = xCAT::Utils->getHomeDir("root");
                unlink "$home/.ssh/copy.sh";
                File::Path->remove_tree("$home/.ssh/tmp/");
            }
            if ($::UPLOAD_AND_ACTIVATE or $next_status{LOGIN_RESPONSE} eq "RFLASH_UPDATE_ACTIVATE_REQUEST") {
                my %rflash_result = ();
                foreach my $node (keys %node_info) {
                    if ($node_info{$node}{rst} =~ /successful/) {
                        push @{ $rflash_result{success} }, $node;
                    } else {
                        $node_info{$node}{rst} = "BMC is not ready" unless ($node_info{$node}{rst});
                        push @{ $rflash_result{fail} }, "$node: $node_info{$node}{rst}";
                    }
                }
                xCAT::MsgUtils->message("I", { data => ["-------------------------------------------------------"] }, $callback);
                my $summary = "Firmware update complete: ";
                my $total = keys %node_info;
                my $success = 0;
                my $fail = 0;
                $success = @{ $rflash_result{success} } if (defined $rflash_result{success} and @{ $rflash_result{success} });
                $fail = @{ $rflash_result{fail} } if (defined $rflash_result{fail} and @{ $rflash_result{fail} });
                $summary .= "Total=$total Success=$success Failed=$fail";
                xCAT::MsgUtils->message("I", { data => ["$summary"] }, $callback);

                if ($rflash_result{fail}) {
                    foreach (@{ $rflash_result{fail} }) {
                        xCAT::MsgUtils->message("I", { data => ["$_"] }, $callback);
                    }
                }
                xCAT::MsgUtils->message("I", { data => ["-------------------------------------------------------"] }, $callback);
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
                        xCAT::SvrUtils::sendmsg([1,"Internal error, check the process handler for current status "
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
                    xCAT::SvrUtils::sendmsg([1,"Internal error, check the REST handler for current status "
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
    } elsif (scalar(@ARGV) >= 2 and $command eq "reventlog") {
        my $option_s;
        GetOptions( 's' => \$option_s ); 
        return ([ 1, "The -s option is not supported for OpenBMC." ]) if ($option_s);
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
        $subcommand = "all" if (!defined($ARGV[0]));
        unless ($subcommand =~ /^\d$|^\d+$|^all$|^clear$/) {
            return ([ 1, "Unsupported command: $command $subcommand" ]);
        }
    } elsif ($command eq "rspconfig") {
        my $num_subcommand = @ARGV;
        my $setorget;
        my $all_subcommand = "";
        foreach $subcommand (@ARGV) {
            $::RSPCONFIG_CONFIGURED_API_KEY = &is_valid_config_api($subcommand, $callback);
            if ($::RSPCONFIG_CONFIGURED_API_KEY != -1) {
                # subcommand defined in the configured API hash, return from here, the RSPCONFIG_CONFIGURED_API_KEY is the key into the hash
                return;
            }
            elsif ($subcommand =~ /^(\w+)=(.*)/) {
                return ([ 1, "Can not set and query OpenBMC information at the same time" ]) if ($setorget and $setorget eq "get");
                my $key = $1;
                my $value = $2;
                return ([ 1, "Changing ipsrc value is currently not supported." ]) if ($key eq "ipsrc");
                return ([ 1, "Unsupported command: $command $key" ]) unless ($key =~ /^ip$|^netmask$|^gateway$|^hostname$|^vlan$|^admin_passwd$|^ntpservers$/);
                return ([ 1, "The option '$key' can not work with other options." ]) if ($key =~ /^hostname$|^admin_passwd$|^ntpservers$/ and $num_subcommand > 1);
                if ($key eq "admin_passwd") {
                    my $comma_num = $value =~ tr/,/,/;
                    return ([ 1, "Invalid parameter for option $key: $value" ]) if ($comma_num != 1);
                    if ($subcommand =~ /^admin_passwd=(.*),(.*)/) {
                        return ([ 1, "Invalid parameter for option $key: $value" ]) if ($1 eq "" or $2 eq "");
                    }
                }

                my $nodes_num = @$noderange;
                return ([ 1, "Invalid parameter for option $key" ]) if (!$value and $key ne ("ntpservers"));
                return ([ 1, "Invalid parameter for option $key: $value" ]) if (($key eq "netmask") and !xCAT::NetworkUtils->isIpaddr($value));
                return ([ 1, "Invalid parameter for option $key: $value" ]) if (($key eq "gateway") and ($value !~ "0.0.0.0" and !xCAT::NetworkUtils->isIpaddr($value)));
                if ($key eq "ip") {
                    return ([ 1, "Can not configure more than 1 nodes' ip at the same time" ]) if ($nodes_num >= 2 and $value ne "dhcp");
                    if ($value ne "dhcp" ) {
                        if (!xCAT::NetworkUtils->isIpaddr($value)) {
                            return ([ 1, "Invalid parameter for option $key: $value" ]);
                        } else {
                            $all_subcommand .= $key . ",";
                        }
                    } else {
                        return ([ 1, "Setting ip=dhcp must be issued without other options." ]) if ($num_subcommand > 1);
                    }
                } elsif ($key =~ /^netmask$|^gateway$|^vlan$/) {
                    $all_subcommand .= $key . ",";
                }
                $setorget = "set";
            } elsif ($subcommand =~ /^ip$|^netmask$|^gateway$|^hostname$|^vlan$|^ipsrc$|^ntpservers$/) {
                return ([ 1, "Can not set and query OpenBMC information at the same time" ]) if ($setorget and $setorget eq "set");
                $setorget = "get";
            } elsif ($subcommand =~ /^sshcfg$/) {
                return ([ 1, "Configure sshcfg must be issued without other options." ]) if ($num_subcommand > 1);
                $setorget = ""; # SSH Keys are copied using a RShellAPI, not REST API
            } elsif ($subcommand eq "gard") {
                my $option = "";
                $option = $ARGV[1] if (defined $ARGV[1]);
                return  ([ 1, "Clear GARD cannot be issued with other options." ]) if ($num_subcommand > 2);
                return ([ 1, "Invalid parameter for $command $subcommand $option" ]) if ($option !~ /^-c$|^--clear$/);
                $setorget = "";
                return;
            } elsif ($subcommand eq "dump") {
                my $option = "";
                $option = $ARGV[1] if (defined $ARGV[1]);
                if ($option =~ /^-d$|^--download$/) {
                    return ([ 1, "No dump file ID specified" ]) unless ($ARGV[2]);
                    return ([ 1, "Invalid parameter for $command $option $ARGV[2]" ]) if ($ARGV[2] !~ /^\d*$/);
                } elsif ($option =~ /^-c$|^--clear$/) {
                    return ([ 1, "No dump file ID specified. To clear all, specify 'all'." ]) unless ($ARGV[2]);
                    return ([ 1, "Invalid parameter for $command $option $ARGV[2]" ]) if ($ARGV[2] !~ /^\d*$/ and $ARGV[2] ne "all");
                } elsif ($option and $option !~ /^-l$|^--list$|^-g$|^--generate$/) {
                    return ([ 1, "Invalid parameter for $command $option" ]);
                }
                return;
            } else {
                return ([ 1, "Unsupported command: $command $subcommand" ]);
            }
        }
        if ($all_subcommand) {
            if ($all_subcommand !~ /ip/ or $all_subcommand !~ /netmask/ or $all_subcommand !~ /gateway/) {
                if ($all_subcommand =~ /vlan/) {
                    return ([ 1, "VLAN must be configured with IP, netmask and gateway" ]);
                } else {
                    return ([ 1, "IP, netmask and gateway must be configured together." ]);
                }
            }
        }
    } elsif ($command eq "rvitals") {
        $subcommand = "all" if (!defined($ARGV[0]));
        unless ($subcommand =~ /^leds$|^temp$|^voltage$|^wattage$|^fanspeed$|^power$|^altitude$|^all$/) {
            return ([ 1, "Unsupported command: $command $subcommand" ]);
        }
    } elsif ($command eq "rflash") {
        my $filename_passed = 0;
        my $updateid_passed = 0;
        my $filepath_passed = 0;
        my $option_flag;

        my @tarball_path;
        my $invalid_options = "";
        my @flash_arguments;

        foreach my $opt (@$extrargs) {
            # Only files ending on .tar are allowed
            if ($opt =~ /.*\.tar$/i) {
                $filename_passed = 1;
                push (@flash_arguments, $opt); 
                next;
            }
            # Check if hex number for the updateid is passed
            elsif ($opt =~ /^[[:xdigit:]]+$/i) {
                $updateid_passed = 1;
                push (@flash_arguments, $opt); 
                next;
            }
            # check if option starting with - was passed
            elsif ($opt =~ /^-/) {
                # do not add verbose option to the $option_flag in order to preserve arg checks below
                if ($opt !~ /^-V$|^--verbose$/) {
                    if ($option_flag) {
                        $option_flag .= " " . $opt;
                    } else {
                        $option_flag .= $opt;
                    }
                }
            }
            elsif ($opt =~ /^\//) {
                $filepath_passed = 1;
                push (@tarball_path, $opt);
            }
            else {
                my $tmppath = xCAT::Utils->full_path($opt, $::cwd);
                if (opendir(TDIR, $tmppath)) {
                    $filepath_passed = 1;
                    push (@tarball_path, $tmppath);
                    close(TDIR);
                } else {
                    push (@flash_arguments, $opt);
                    $invalid_options .= $opt . " ";
                }
            }
        }
        # show options parsed in bypass mode
        print "DEBUG filename=$filename_passed, updateid=$updateid_passed, options=$option_flag, tar_file_path=@tarball_path, invalid=$invalid_options rflash_arguments=@flash_arguments\n";

        if ($option_flag =~ tr{ }{ } > 0) { 
            unless ($verbose or $option_flag =~/^-d --no-host-reboot$/) {
                return ([ 1, "Multiple options are not supported. Options specified: $option_flag"]);
            }
        }
        
        if (scalar @flash_arguments > 1) {
            if (($option_flag =~ /^-a$|^--activate$|^--delete$/) or ($filename_passed and $option_flag !~ /^-d$/)) { 
                # Handles: 
                #   - Multiple options not supported to activate/delete at the same time 
                #   - Filename passed in and option is not -d for directory
                return ([1, "More than one firmware specified is not supported."]);
            } elsif ($option_flag =~ /^-d$/) {
                return ([1, "More than one directory specified is not supported."]);
            } else {
                return ([ 1, "Invalid firmware specified with $option_flag" ]);
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
                if ($option_flag !~ /^--delete$|^-a$|^--activate$/) {
                    my $optional_help_msg = "";
                    if ($option_flag == "-d") {
                        # For this special case, -d was changed to pass in a directory.
                        $optional_help_msg = "Did you mean --delete?"
                    }
                    return ([ 1, "Invalid option specified when an update id is provided: $option_flag. $optional_help_msg" ]);
                }
                my $action = "activate";
                if ($option_flag =~ /^--delete$/) {
                    $action = "delete";
                }
                xCAT::SvrUtils::sendmsg("Attempting to $action ID=$flash_arguments[0], please wait...", $callback);
            } elsif ($filepath_passed) {
                if ($option_flag =~ /^-d|^-d --no-host-reboot$/) {
                    if (scalar @tarball_path > 1) {
                        return ([1, "More than one directory specified is not supported"]);
                    }
                    if ($invalid_options) {
                        return ([ 1, "Invalid option specified $invalid_options"]);
                    }
                    if (!opendir(DIR, $tarball_path[0])) {
                        return ([1, "Can't open directory : $tarball_path[0]"]);
                    } else {
                        $::TAR_FILE_PATH = $tarball_path[0];
                        closedir(DIR);
                    }
                } elsif ($option_flag =~ /^-c$|^--check$|^-u$|^--upload$|^-a$|^--activate$/) {
                    return ([ 1, "Invalid firmware specified with $option_flag" ]);
                } else {
                    return ([ 1, "Invalid option specified" ]);
                }        
            } else {
                # Neither Filename nor updateid was not passed, check flags allowed without file or updateid
                if ($option_flag !~ /^-c$|^--check$|^-l$|^--list$/) {
                    return ([ 1, "Invalid option specified with $option_flag: $invalid_options" ]);
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
            $next_status{RPOWER_STATUS_RESPONSE}{ON} = "RPOWER_OFF_REQUEST";
            $next_status{RPOWER_OFF_REQUEST} = "RPOWER_OFF_RESPONSE";
            $next_status{RPOWER_OFF_RESPONSE} = "RPOWER_CHECK_REQUEST";
            $next_status{RPOWER_CHECK_REQUEST} = "RPOWER_CHECK_RESPONSE";
            $next_status{RPOWER_CHECK_RESPONSE}{ON} = "RPOWER_CHECK_REQUEST";
            $next_status{RPOWER_CHECK_RESPONSE}{OFF} = "RPOWER_ON_REQUEST";
            $next_status{RPOWER_ON_REQUEST} = "RPOWER_ON_RESPONSE";
            $status_info{RPOWER_ON_RESPONSE}{argv} = "$subcommand";
        } elsif ($subcommand =~ /^bmcstate$|^status$|^state$|^stat$/) {
            $next_status{LOGIN_RESPONSE} = "RPOWER_STATUS_REQUEST";
            $next_status{RPOWER_STATUS_REQUEST} = "RPOWER_STATUS_RESPONSE";
            $status_info{RPOWER_STATUS_RESPONSE}{argv} = "$subcommand";
        } elsif ($subcommand eq "boot") {
            $next_status{LOGIN_RESPONSE} = "RPOWER_OFF_REQUEST";
            $next_status{RPOWER_OFF_REQUEST} = "RPOWER_OFF_RESPONSE";
            $next_status{RPOWER_OFF_RESPONSE} = "RPOWER_CHECK_REQUEST";
            $next_status{RPOWER_CHECK_REQUEST} = "RPOWER_CHECK_RESPONSE";
            $next_status{RPOWER_CHECK_RESPONSE}{ON} = "RPOWER_CHECK_REQUEST";
            $next_status{RPOWER_CHECK_RESPONSE}{OFF} = "RPOWER_ON_REQUEST";
            $next_status{RPOWER_ON_REQUEST} = "RPOWER_ON_RESPONSE";
            $status_info{RPOWER_ON_RESPONSE}{argv} = "$subcommand";
        } elsif ($subcommand eq "bmcreboot") {
            $next_status{LOGIN_RESPONSE} = "RINV_FIRM_REQUEST";
            $next_status{RINV_FIRM_REQUEST} = "RINV_FIRM_RESPONSE";
            $next_status{RINV_FIRM_RESPONSE}{PENDING} = "RSPCONFIG_DUMP_CLEAR_ALL_REQUEST";
            $next_status{RSPCONFIG_DUMP_CLEAR_ALL_REQUEST} = "RSPCONFIG_DUMP_CLEAR_RESPONSE";
            $next_status{RSPCONFIG_DUMP_CLEAR_RESPONSE} = "RPOWER_BMCREBOOT_REQUEST";
            $next_status{RINV_FIRM_RESPONSE}{NO_PENDING} = "RPOWER_BMCREBOOT_REQUEST";
            $next_status{RPOWER_BMCREBOOT_REQUEST} = "RPOWER_RESET_RESPONSE";
            $status_info{RPOWER_RESET_RESPONSE}{argv} = "$subcommand";
            $status_info{RINV_FIRM_RESPONSE}{check} = 1;    
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
            if (-e "$::RAS_POLICY_TABLE") {
                my $policy_json = `cat $::RAS_POLICY_TABLE`;
                if ($policy_json) {
                    my $policy_hash = decode_json $policy_json;
                    $event_mapping = $policy_hash->{events};
                } else {
                    $event_mapping = "No data in $::RAS_POLICY_TABLE";
                }
            } else {
                $event_mapping = "Could not find '$::RAS_POLICY_TABLE'";
            }
        }
    }

    if ($command eq "rspconfig") {
        my @options = ();
        my $num_subcommand = @$subcommands;
        #Setup chain to process the configured command
        if ($::RSPCONFIG_CONFIGURED_API_KEY != -1) {
            $subcommand = $$subcommands[0];
            # Check if setting or quering
            if ($subcommand =~ /^(\w+)=(.*)/) {
                # setting
                my $subcommand_key = $1;
                my $subcommand_value = $2;

                if ($subcommand_value eq "1") {
                    # Setup chain for subcommand=1
                    $next_status{LOGIN_RESPONSE} = "RSPCONFIG_API_CONFIG_ON_REQUEST";
                    $status_info{RSPCONFIG_API_CONFIG_ON_REQUEST}{init_url} =  $status_info{RSPCONFIG_API_CONFIG_ON_REQUEST}{init_url} . $api_config_info{$::RSPCONFIG_CONFIGURED_API_KEY}{url} . "/attr/" . $api_config_info{$::RSPCONFIG_CONFIGURED_API_KEY}{attr_url};
                    $next_status{RSPCONFIG_API_CONFIG_ON_REQUEST} = "RSPCONFIG_API_CONFIG_ON_RESPONSE";
                }
                elsif ($subcommand_value eq "0") {
                    # Setup chain for subcommand=0
                    $next_status{LOGIN_RESPONSE} = "RSPCONFIG_API_CONFIG_OFF_REQUEST";
                    $status_info{RSPCONFIG_API_CONFIG_OFF_REQUEST}{init_url} =  $status_info{RSPCONFIG_API_CONFIG_OFF_REQUEST}{init_url} . $api_config_info{$::RSPCONFIG_CONFIGURED_API_KEY}{url} . "/attr/" . $api_config_info{$::RSPCONFIG_CONFIGURED_API_KEY}{attr_url};
                    $next_status{RSPCONFIG_API_CONFIG_OFF_REQUEST} = "RSPCONFIG_API_CONFIG_OFF_RESPONSE";
                }
                else {
                    # Everything else is invalid
                        xCAT::SvrUtils::sendmsg([1, "Invalid value $subcommand_value for 'rspconfig $subcommand_key=$subcommand_value' command"], $callback);
                        return 1;
                }
            }
            else {
                # Setup chain for query subcommand
                $next_status{LOGIN_RESPONSE} = "RSPCONFIG_API_CONFIG_QUERY_REQUEST";
                $status_info{RSPCONFIG_API_CONFIG_QUERY_REQUEST}{init_url} =  $status_info{RSPCONFIG_API_CONFIG_QUERY_REQUEST}{init_url} . $api_config_info{$::RSPCONFIG_CONFIGURED_API_KEY}{url};
                $next_status{RSPCONFIG_API_CONFIG_QUERY_REQUEST} = "RSPCONFIG_API_CONFIG_QUERY_RESPONSE";
            }
            return 0;
        }
        if ($num_subcommand == 1) {
            $subcommand = $$subcommands[0];
            if ($subcommand =~ /^sshcfg$/) {
                # Special processing to copy ssh keys, currently there is no REST API to do this.
                $next_status{LOGIN_RESPONSE} = "RSPCONFIG_SSHCFG_REQUEST";
                $next_status{RSPCONFIG_SSHCFG_REQUEST} = "RSPCONFIG_SSHCFG_RESPONSE";
                return 0;
            }
            if ($subcommand eq "ip=dhcp") {
                $next_status{LOGIN_RESPONSE} = "RSPCONFIG_DHCP_REQUEST";
                $next_status{RSPCONFIG_DHCP_REQUEST} = "RSPCONFIG_DHCP_RESPONSE";
                $next_status{RSPCONFIG_DHCP_RESPONSE} = "RPOWER_BMCREBOOT_REQUEST";
                $next_status{RPOWER_BMCREBOOT_REQUEST} = "RPOWER_RESET_RESPONSE";
                $status_info{RPOWER_RESET_RESPONSE}{argv} = "bmcreboot";
                return 0;
            }
            if ($subcommand =~ /^hostname=(.+)/) {
                $next_status{LOGIN_RESPONSE} = "RSPCONFIG_SET_HOSTNAME_REQUEST";
                $next_status{RSPCONFIG_SET_HOSTNAME_REQUEST} = "RSPCONFIG_SET_RESPONSE";
                $next_status{RSPCONFIG_SET_RESPONSE} = "RSPCONFIG_GET_REQUEST";
                $next_status{RSPCONFIG_GET_REQUEST} = "RSPCONFIG_GET_RESPONSE";

                $status_info{RSPCONFIG_SET_HOSTNAME_REQUEST}{data} = $1;
                $status_info{RSPCONFIG_SET_RESPONSE}{argv} = "Hostname";
                $status_info{RSPCONFIG_GET_RESPONSE}{argv} = "hostname";
                return 0;
            }
            if ($subcommand =~ /^ntpservers=(.*)/) {
                $next_status{LOGIN_RESPONSE} = "RSPCONFIG_GET_NIC_REQUEST";
                $next_status{RSPCONFIG_GET_NIC_REQUEST} = "RSPCONFIG_GET_NIC_RESPONSE";
                $next_status{RSPCONFIG_GET_NIC_RESPONSE} = "RSPCONFIG_SET_NTPSERVERS_REQUEST";
                $next_status{RSPCONFIG_SET_NTPSERVERS_REQUEST} = "RSPCONFIG_SET_RESPONSE";
                $next_status{RSPCONFIG_SET_RESPONSE} = "RSPCONFIG_GET_REQUEST";
                $next_status{RSPCONFIG_GET_REQUEST} = "RSPCONFIG_GET_RESPONSE";

                $status_info{RSPCONFIG_GET_RESPONSE}{argv} = "ntpservers";
                $status_info{RSPCONFIG_SET_RESPONSE}{argv} = "NTPServers";
                $status_info{RSPCONFIG_SET_NTPSERVERS_REQUEST}{data} = "[\"$1\"]";
                return 0;
            }
        }

        $subcommand = $$subcommands[0];
        if ($subcommand eq "dump") {
            my $dump_opt = "";
            $dump_opt = $$subcommands[1] if (defined $$subcommands[1]);
            if ($dump_opt =~ /-l|--list/) {
                $next_status{LOGIN_RESPONSE} = "RSPCONFIG_DUMP_LIST_REQUEST";
                $next_status{RSPCONFIG_DUMP_LIST_REQUEST} = "RSPCONFIG_DUMP_LIST_RESPONSE";
            } elsif ($dump_opt =~ /-g|--generate/) {
                $next_status{LOGIN_RESPONSE} = "RSPCONFIG_DUMP_CREATE_REQUEST";
                $next_status{RSPCONFIG_DUMP_CREATE_REQUEST} = "RSPCONFIG_DUMP_CREATE_RESPONSE";
            } elsif ($dump_opt =~ /-c|--clear/) {
                if ($$subcommands[2] eq "all") {
                    $next_status{LOGIN_RESPONSE} = "RSPCONFIG_DUMP_CLEAR_ALL_REQUEST";
                    $next_status{RSPCONFIG_DUMP_CLEAR_ALL_REQUEST} = "RSPCONFIG_DUMP_CLEAR_RESPONSE";
                } else {
                    $next_status{LOGIN_RESPONSE} = "RSPCONFIG_DUMP_CLEAR_REQUEST";
                    $next_status{RSPCONFIG_DUMP_CLEAR_REQUEST} = "RSPCONFIG_DUMP_CLEAR_RESPONSE";
                    $status_info{RSPCONFIG_DUMP_CLEAR_REQUEST}{init_url} =~ s/#ID#/$$subcommands[2]/g;
                }
                $status_info{RSPCONFIG_DUMP_CLEAR_RESPONSE}{argv} = $$subcommands[2];
            } elsif ($dump_opt =~ /-d|--download/) {
                # Verify directory for download is there
                unless (-d  $::XCAT_LOG_DUMP_DIR) {
                    xCAT::SvrUtils::sendmsg([1, "Unable to create directory " . $::XCAT_LOG_DUMP_DIR . " to download dump file, cannot continue."], $callback);
                    return 1;
                }
                $::RSPCONFIG_DUMP_CMD_TIME = time(); #Save time of rspcommand start to use in the dump filename
                $next_status{LOGIN_RESPONSE} = "RSPCONFIG_DUMP_DOWNLOAD_REQUEST";
                $next_status{RSPCONFIG_DUMP_DOWNLOAD_REQUEST} = "RSPCONFIG_DUMP_DOWNLOAD_RESPONSE";
                $status_info{RSPCONFIG_DUMP_DOWNLOAD_REQUEST}{init_url} =~ s/#ID#/$$subcommands[2]/g; 
                $status_info{RSPCONFIG_DUMP_DOWNLOAD_REQUEST}{argv} = $$subcommands[2];
            } else {
                # this section handles the dump support where no options are given and xCAT will 
                # # handle the creation, waiting, and download of the dump across a given noderange
                # Verify directory for download is there
                unless (-d  $::XCAT_LOG_DUMP_DIR) {
                    xCAT::SvrUtils::sendmsg([1, "Unable to find directory " . $::XCAT_LOG_DUMP_DIR . " to download dump file"], $callback);
                    return 1;
                }
                $::RSPCONFIG_DUMP_CMD_TIME = time(); #Save time of rspcommand start to use in the dump filename
                xCAT::SvrUtils::sendmsg("Capturing BMC Diagnostic information, this will take some time...", $callback);
                $next_status{LOGIN_RESPONSE} = "RSPCONFIG_DUMP_CREATE_REQUEST";
                $next_status{RSPCONFIG_DUMP_CREATE_REQUEST} = "RSPCONFIG_DUMP_CREATE_RESPONSE";
                $next_status{RSPCONFIG_DUMP_CREATE_RESPONSE} = "RSPCONFIG_DUMP_LIST_REQUEST";
                $next_status{RSPCONFIG_DUMP_LIST_REQUEST} = "RSPCONFIG_DUMP_CHECK_RESPONSE";
                $next_status{RSPCONFIG_DUMP_CHECK_RESPONSE} = "RSPCONFIG_DUMP_DOWNLOAD_REQUEST";
                $next_status{RSPCONFIG_DUMP_DOWNLOAD_REQUEST} = "RSPCONFIG_DUMP_DOWNLOAD_RESPONSE";
            }
            return 0;
        } elsif ($subcommand eq "gard") {
            $next_status{LOGIN_RESPONSE} = "RSPCONFIG_CLEAR_GARD_REQUEST";
            $next_status{RSPCONFIG_CLEAR_GARD_REQUEST} = "RSPCONFIG_CLEAR_GARD_RESPONSE";
            return 0;
        }

        if ($subcommand =~ /^admin_passwd=(.+),(.+)/) {
            my $currentpasswd = $1;
            my $newpasswd = $2;
            $next_status{LOGIN_RESPONSE} = "RSPCONFIG_PASSWD_VERIFY";
            $next_status{RSPCONFIG_PASSWD_VERIFY} = "RSPCONFIG_SET_PASSWD_REQUEST";
            $next_status{RSPCONFIG_SET_PASSWD_REQUEST} = "RSPCONFIG_SET_RESPONSE";

            $status_info{RSPCONFIG_PASSWD_VERIFY}{argv} = "$currentpasswd";
            $status_info{RSPCONFIG_SET_PASSWD_REQUEST}{data} = "[\"$newpasswd\"]";
            $status_info{RSPCONFIG_SET_RESPONSE}{argv} = "Password";
            return 0;
        }

        my $type = "obj";
        my %tmp_hash = ();
        foreach $subcommand (@$subcommands) {
            if ($subcommand =~ /^ip$|^netmask$|^gateway$|^hostname$|^vlan$|^ipsrc$|^ntpservers$/) {
                $type = "get";
                push @options, $subcommand;
            } elsif ($subcommand =~ /^(\w+)=(.+)/) {
                my $key   = $1;
                my $value = $2;
                $type = "vlan" if ($key eq "vlan");
                $tmp_hash{$key} = $value;
            }
        }
        if ($type eq "get") {
            $next_status{LOGIN_RESPONSE} = "RSPCONFIG_GET_REQUEST";
            $next_status{RSPCONFIG_GET_REQUEST} = "RSPCONFIG_GET_RESPONSE";
            $status_info{RSPCONFIG_GET_RESPONSE}{argv} = join(",", @options);
        } else {
            $next_status{LOGIN_RESPONSE} = "RSPCONFIG_GET_REQUEST";
            $next_status{RSPCONFIG_GET_REQUEST} = "RSPCONFIG_GET_RESPONSE";
            my $prefix = xCAT::NetworkUtils::formatNetmask($tmp_hash{netmask}, 0, 1);

            if ($type eq "obj") {
                $next_status{RSPCONFIG_GET_RESPONSE} = "RSPCONFIG_IPOBJECT_REQUEST";
                $next_status{RSPCONFIG_IPOBJECT_REQUEST} = "RSPCONFIG_IPOBJECT_RESPONSE";

                $status_info{RSPCONFIG_CHECK_RESPONSE}{argv} = "$tmp_hash{ip}-$prefix-$tmp_hash{gateway}";
                $status_info{RSPCONFIG_PRINT_BMCINFO}{data} = "BMC IP: $tmp_hash{ip},BMC Netmask: $tmp_hash{netmask},BMC Gateway: $tmp_hash{gateway}";
            } elsif ($type eq "vlan") {
                $next_status{RSPCONFIG_GET_RESPONSE} = "RSPCONFIG_VLAN_REQUEST";
                $next_status{RSPCONFIG_VLAN_REQUEST} = "RSPCONFIG_VLAN_RESPONSE";
                $next_status{RSPCONFIG_VLAN_RESPONSE} = "RSPCONFIG_IPOBJECT_REQUEST";
                $next_status{RSPCONFIG_IPOBJECT_REQUEST} = "RSPCONFIG_IPOBJECT_RESPONSE";

                $status_info{RSPCONFIG_VLAN_REQUEST}{data} = "[\"#NIC#\",\"$tmp_hash{vlan}\"]";
                $status_info{RSPCONFIG_IPOBJECT_REQUEST}{init_url} =~ s/#NIC#/#NIC#_$tmp_hash{vlan}/g;
                $status_info{RSPCONFIG_CHECK_RESPONSE}{argv} = "$tmp_hash{vlan}-$tmp_hash{ip}-$prefix-$tmp_hash{gateway}";
                $status_info{RSPCONFIG_PRINT_BMCINFO}{data} = "BMC IP: $tmp_hash{ip},BMC Netmask: $tmp_hash{netmask},BMC Gateway: $tmp_hash{gateway},BMC VLAN ID: $tmp_hash{vlan}";
            }

            $next_status{RSPCONFIG_IPOBJECT_RESPONSE} = "RSPCONFIG_CHECK_REQUEST";
            $next_status{RSPCONFIG_CHECK_REQUEST} = "RSPCONFIG_CHECK_RESPONSE";
            $next_status{RSPCONFIG_CHECK_RESPONSE}{STATIC} = "RSPCONFIG_DELETE_REQUEST";
            $next_status{RSPCONFIG_DELETE_REQUEST} = "RSPCONFIG_DELETE_RESPONSE";
            $next_status{RSPCONFIG_CHECK_RESPONSE}{DHCP} = "RSPCONFIG_DHCPDIS_REQUEST";
            $next_status{RSPCONFIG_DHCPDIS_REQUEST} = "RSPCONFIG_DHCPDIS_RESPONSE";
            $next_status{RSPCONFIG_DELETE_RESPONSE} = "RSPCONFIG_PRINT_BMCINFO";
            $next_status{RSPCONFIG_DHCPDIS_RESPONSE} = "RSPCONFIG_PRINT_BMCINFO";

            $status_info{RSPCONFIG_GET_RESPONSE}{argv} = "all";
            $status_info{RSPCONFIG_IPOBJECT_REQUEST}{data} = "[\"xyz.openbmc_project.Network.IP.Protocol.IPv4\",\"$tmp_hash{ip}\",$prefix,\"$tmp_hash{gateway}\"]";
        }
    }

    if ($command eq "rvitals") {
        if (defined($$subcommands[0])) {
            $subcommand = $$subcommands[0];
        } else {
            $subcommand = "all";
        }

        if ($subcommand eq "leds") {
            $next_status{LOGIN_RESPONSE} = "RVITALS_LEDS_REQUEST";
            $next_status{RVITALS_LEDS_REQUEST} = "RVITALS_LEDS_RESPONSE";
            $status_info{RVITALS_LEDS_RESPONSE}{argv} = "$subcommand";
        } else {
            $next_status{LOGIN_RESPONSE} = "RVITALS_REQUEST";
            $next_status{RVITALS_REQUEST} = "RVITALS_RESPONSE";
            $status_info{RVITALS_RESPONSE}{argv} = "$subcommand";
        }
    }

    if ($command eq "rflash") {
        my $check_version = 0;
        my $list = 0;
        my $delete = 0;
        my $upload = 0;
        my $activate = 0;
        my $update_file;
        my $streamline = 0;
        my $nohost_reboot = 0;

        foreach $subcommand (@$subcommands) {
            if ($subcommand =~ /-c|--check/) {
                $check_version = 1;
            } elsif ($subcommand =~ /-l|--list/) {
                $list = 1;
            } elsif ($subcommand =~ /--delete/) {
                $delete = 1;
            } elsif ($subcommand =~ /-u|--upload/) {
                $upload = 1;
            } elsif ($subcommand =~ /-a|--activate/) {
                $activate = 1;
            } elsif ($subcommand =~ /-d/) {
                my $check = unsupported($callback); if (ref($check) eq "ARRAY") {
                    xCAT::SvrUtils::sendmsg($check, $callback);
                    return 1;
                }
                $streamline = 1;
            } elsif ($subcommand =~ /--no-host-reboot/) {
                $nohost_reboot = 1;
            } else {
                $update_file = $subcommand;
            }
        }

        my $file_id = undef;
        my $grep_cmd = "/usr/bin/grep -a";
        my $tr_cmd = "/usr/bin/tr";
        my $sha512sum_cmd = "/usr/bin/sha512sum";
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
                    xCAT::SvrUtils::sendmsg([1,"Cannot access $::UPLOAD_FILE. Check the management node and/or service nodes."], $callback);
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
                    if (-x $sha512sum_cmd && -x $tr_cmd) {
                        # Save hash id this firmware version should resolve to:
                        # take version string, get rid of newline, run through sha512sum, take first 8 characters
                        $::UPLOAD_FILE_HASH_ID = substr(`echo $::UPLOAD_FILE_VERSION | $tr_cmd -d '\n' | $sha512sum_cmd`, 0,8);
                    }
                    else {
                        if ($::VERBOSE) {
                            xCAT::SvrUtils::sendmsg("WARN: No hashing check being done. ($sha512sum_cmd or $tr_cmd commands not found)
", $callback);
                        }
                    }
                }

                if ($check_version) {
                    # Display firmware version of the specified .tar file
                    xCAT::SvrUtils::sendmsg("TAR $purpose_value Firmware Product Version\: $version_value", $callback);
                }
            } elsif (opendir(DIR, $::TAR_FILE_PATH)) {
                my @tar_files = readdir(DIR);
                foreach my $file (@tar_files) {
                    if ($file !~ /.*\.tar$/) {
                        next;
                    } else {
                        my $full_path_file = $::TAR_FILE_PATH."/".$file;
                        $full_path_file=~s/\/\//\//g;
                        my $firmware_version_in_file = `$grep_cmd $version_tag $full_path_file`;
                        my $purpose_version_in_file = `$grep_cmd $purpose_tag $full_path_file`;
                        chomp($firmware_version_in_file);
                        chomp($purpose_version_in_file);
                        if (defined($firmware_version_in_file) and defined($purpose_version_in_file)) {
                            (my $purpose_string,$purpose_value) = split("=", $purpose_version_in_file);
                            (my $version_string,$version_value) = split("=", $firmware_version_in_file);
                            if ($purpose_value =~ /Purpose.BMC$/ and $version_string =~/version/){
                                $::UPLOAD_FILE = $full_path_file;
                                $::UPLOAD_FILE_VERSION = $version_value;
                            } elsif ($purpose_value =~ /Purpose.Host$/ and $version_value =~ /witherspoon/) {
                                $::UPLOAD_PNOR = $full_path_file;
                                $::UPLOAD_PNOR_VERSION = $version_value;
                            }
                        }
                    }
                }
                my $return_code = 0;
                if (!$::UPLOAD_FILE) {
                    xCAT::SvrUtils::sendmsg([1,"No BMC tar file found in $update_file"], $callback);
                    $return_code = 1;
                }
                if (!$::UPLOAD_PNOR) {
                    xCAT::SvrUtils::sendmsg([1,"No PNOR tar file found in $update_file"], $callback);
                    $return_code = 1;
                }
                if ($return_code) {
                    return 1;
                }
                if ($streamline) {
                    $::UPLOAD_ACTIVATE_STREAM = 1;
                    if ($nohost_reboot) {
                        $::RFLASH_STREAM_NO_HOST_REBOOT = 1; 
                        $nohost_reboot = 0;
                    }
                    $streamline = 0;
                    if (-x $sha512sum_cmd && -x $tr_cmd) {
                        # Save hash id this firmware version should resolve to:
                        $::UPLOAD_FILE_HASH_ID = substr(`echo $::UPLOAD_FILE_VERSION | $tr_cmd -d '\n' | $sha512sum_cmd`, 0,8);
                        $::UPLOAD_PNOR_HASH_ID = substr(`echo $::UPLOAD_PNOR_VERSION | $tr_cmd -d '\n' | $sha512sum_cmd`, 0,8);
                    }
                    else {
                        if ($::VERBOSE) {
                            xCAT::SvrUtils::sendmsg("WARN: No hashing check being done. ($sha512sum_cmd or $tr_cmd commands not found)
", $callback);
                        }
                    }
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
        if ($upload or $::UPLOAD_AND_ACTIVATE) {
            xCAT::SvrUtils::sendmsg("Attempting to upload $::UPLOAD_FILE, please wait...", $callback);
        } elsif ($::UPLOAD_ACTIVATE_STREAM) {
            xCAT::SvrUtils::sendmsg("Attempting to upload $::UPLOAD_FILE and $::UPLOAD_PNOR, please wait...", $callback);
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
            $next_status{"RFLASH_UPDATE_CHECK_ID_RESPONSE"} = "RFLASH_UPDATE_ACTIVATE_REQUEST";
            $next_status{"RFLASH_UPDATE_ACTIVATE_REQUEST"} = "RFLASH_UPDATE_ACTIVATE_RESPONSE";
            $next_status{"RFLASH_UPDATE_ACTIVATE_RESPONSE"} = "RFLASH_UPDATE_CHECK_STATE_REQUEST";
            $next_status{"RFLASH_UPDATE_CHECK_STATE_REQUEST"} = "RFLASH_UPDATE_CHECK_STATE_RESPONSE";
            $next_status{"RFLASH_SET_PRIORITY_REQUEST"} = "RFLASH_SET_PRIORITY_RESPONSE";
            $next_status{"RFLASH_SET_PRIORITY_RESPONSE"} = "RFLASH_UPDATE_CHECK_STATE_REQUEST";
        }
        if ($::UPLOAD_ACTIVATE_STREAM) {
            $next_status{LOGIN_RESPONSE} = "RFLASH_FILE_UPLOAD_REQUEST";
            $next_status{RFLASH_FILE_UPLOAD_REQUEST} = "RFLASH_FILE_UPLOAD_RESPONSE";
            $next_status{RFLASH_FILE_UPLOAD_RESPONSE} = "RFLASH_UPDATE_CHECK_ID_REQUEST";
            $next_status{RFLASH_UPDATE_CHECK_ID_REQUEST} = "RFLASH_UPDATE_CHECK_ID_RESPONSE";
            $next_status{RFLASH_UPDATE_CHECK_ID_RESPONSE} = "RFLASH_UPDATE_ACTIVATE_REQUEST";
            $next_status{RFLASH_UPDATE_ACTIVATE_REQUEST} = "RFLASH_UPDATE_ACTIVATE_RESPONSE";
            $next_status{RFLASH_UPDATE_ACTIVATE_RESPONSE} = "RFLASH_UPDATE_HOST_ACTIVATE_REQUEST";
            $next_status{RFLASH_UPDATE_HOST_ACTIVATE_REQUEST} = "RFLASH_UPDATE_HOST_ACTIVATE_RESPONSE";
            $next_status{RFLASH_UPDATE_HOST_ACTIVATE_RESPONSE} = "RFLASH_UPDATE_CHECK_STATE_REQUEST";
            $next_status{RFLASH_UPDATE_CHECK_STATE_REQUEST} = "RFLASH_UPDATE_CHECK_STATE_RESPONSE";
            $next_status{RFLASH_SET_PRIORITY_REQUEST} = "RFLASH_SET_PRIORITY_RESPONSE";
            $next_status{RFLASH_SET_PRIORITY_RESPONSE} = "RFLASH_UPDATE_CHECK_STATE_REQUEST";
            $next_status{RFLASH_UPDATE_CHECK_STATE_RESPONSE} = "RPOWER_BMCREBOOT_REQUEST";
            $next_status{RPOWER_BMCREBOOT_REQUEST} = "RPOWER_RESET_RESPONSE";
            $status_info{RPOWER_RESET_RESPONSE}{argv} = "bmcreboot";
            $next_status{RPOWER_RESET_RESPONSE} = "RPOWER_BMC_CHECK_REQUEST";
            $next_status{RPOWER_BMC_CHECK_REQUEST} = "RPOWER_BMC_STATUS_RESPONSE";
            $next_status{LOGIN_REQUEST_GENERAL} = "LOGIN_RESPONSE_GENERAL";
            $next_status{LOGIN_RESPONSE_GENERAL} = "RPOWER_BMC_STATUS_REQUEST";
            $next_status{RPOWER_BMC_STATUS_REQUEST} = "RPOWER_BMC_STATUS_RESPONSE";
            $status_info{RPOWER_BMC_STATUS_RESPONSE}{argv} = "bmcstate";
            if (!$::RFLASH_STREAM_NO_HOST_REBOOT) {
               $next_status{RPOWER_BMC_STATUS_RESPONSE} = "RPOWER_OFF_REQUEST";
               $next_status{RPOWER_OFF_REQUEST} = "RPOWER_OFF_RESPONSE";
               $next_status{RPOWER_OFF_RESPONSE} = "RPOWER_CHECK_REQUEST";
               $next_status{RPOWER_CHECK_REQUEST} = "RPOWER_CHECK_RESPONSE";
               $next_status{RPOWER_CHECK_RESPONSE}{ON} = "RPOWER_CHECK_REQUEST";
               $next_status{RPOWER_CHECK_RESPONSE}{OFF} = "RPOWER_ON_REQUEST";
               $next_status{RPOWER_ON_REQUEST} = "RPOWER_ON_RESPONSE";
               $status_info{RPOWER_ON_RESPONSE}{argv} = "boot";
            }
        } 
    }
    return;
}

#-------------------------------------------------------

=head3  fork_process_login

  Fork process to login
  Input:
        $node: nodename

=cut

#-------------------------------------------------------
sub fork_process_login {
    my $node = shift;
    my $rst = 0;

    my $child = xCAT::Utils->xfork;
    if (!defined($child)) {
        xCAT::SvrUtils::sendmsg("Failed to fork child process for login request.", $callback, $node);
        sleep(1);
        $rst = 1;
    } elsif ($child == 0) {
        exit(login_request($node));
    } else {
        $login_pid_node{$child} = $node;
    }

    return $rst;
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

            $node_info{$node}{cur_status} = "LOGIN_REQUEST";
            $node_info{$node}{rpower_check_times} = $::RPOWER_MAX_RETRY;
            $node_info{$node}{bmc_conn_check_times} = $::BMC_MAX_RETRY;
            $node_info{$node}{bmcstate_check_times} = $::BMC_MAX_RETRY;
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
    my $content = "";

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
        } elsif ($status_info{ $node_info{$node}{cur_status} }{data} =~ /^\[.+\]$/) {
            $content = '{"data":' . $status_info{ $node_info{$node}{cur_status} }{data} . '}';
        } elsif (($status_info{ $node_info{$node}{cur_status} }{init_url} =~ /config\/attr\/HostName$/) &&
                 ($status_info{ $node_info{$node}{cur_status} }{data} =~ /^\*$/)) {
            # Special handling for hostname=*
            $content = '{"data":"' . $node_info{$node}{bmc} . '"}';
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

    if ($xcatdebugmode) {
        my $debug_info;
        if ($method eq "GET") {
            $debug_info = "curl -k -b cjar -X $method -H \"Content-Type: application/json\" $request_url";
        } else {
            if ($::UPLOAD_FILE and !$::UPLOAD_ACTIVATE_STREAM) {
                # Slightly different debug message when doing a file upload
                $debug_info = "curl -k -b cjar -X $method -H \"Content-Type: application/json\" -T $::UPLOAD_FILE $request_url";
            } else {
                if ($node_info{$node}{cur_status} eq "LOGIN_REQUEST_GENERAL") {
                    $debug_info = "curl -k -c cjar -H \"Content-Type: application/json\" -d '{ \"data\": [\"$node_info{$node}{username}\", \"xxxxxx\"] }' $request_url";
                } else {
                    $debug_info = "curl -k -b cjar -X $method -H \"Content-Type: application/json\" -d '$content' $request_url";
                }
            }
        }
        process_debug_info($node, $debug_info);
    }
    my $handle_id = xCAT::OPENBMC->send_request($async, $method, $request_url, $content);
    $handle_id_node{$handle_id} = $node;
    $node_info{$node}{cur_status} = $next_status{ $node_info{$node}{cur_status} };

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
            # If the REST service is not up, it can't return "NotReady" itself, during reboot.
            $error = "BMC NotReady";
            xCAT::SvrUtils::sendmsg($error, $callback, $node);
            $wait_node_num--;
            return;    
        }
        if ($node_info{$node}{cur_status} eq "RPOWER_BMC_STATUS_RESPONSE" and defined $status_info{RPOWER_BMC_STATUS_RESPONSE}{argv} and $status_info{RPOWER_BMC_STATUS_RESPONSE}{argv} =~ /bmcstate$/) {
            retry_check_times($node, "RPOWER_BMC_STATUS_REQUEST", "bmc_conn_check_times", $::BMC_CHECK_INTERVAL, $response->status_line);
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
            if ($node_info{$node}{cur_status} eq "RPOWER_RESET_RESPONSE" and defined $status_info{RPOWER_RESET_RESPONSE}{argv} and $status_info{RPOWER_RESET_RESPONSE}{argv} =~ /bmcreboot$/) { 
                my $infomsg = "BMC $::POWER_STATE_REBOOT";
                xCAT::SvrUtils::sendmsg($infomsg, $callback, $node);
                $wait_node_num--;
                return;    
            }
            $error = $::RESPONSE_SERVICE_TIMEOUT;
        } else {
            my $response_info = decode_json $response->content;
            # Handle 500  
            if ($response->status_line eq $::RESPONSE_SERVER_ERROR) {
                $error = "[" . $response->code . "] " . $response_info->{'data'}->{'exception'};
            # Handle 403 
            } elsif ($response->status_line eq $::RESPONSE_FORBIDDEN) {
                #
                # For any invalid data that we can detect, provide a better response message
                #
                if ($node_info{$node}{cur_status} eq "RFLASH_UPDATE_ACTIVATE_RESPONSE" or $node_info{$node}{cur_status} eq "RFLASH_UPDATE_HOST_ACTIVATE_RESPONSE") {
                    # If 403 is received for an activation, that means the activation ID is incorrect
                    $error = "Invalid ID provided to activate. Use the -l option to view valid firmware IDs.";
                } elsif ($node_info{$node}{cur_status} eq "RSETBOOT_ENABLE_RESPONSE" ) {
                    # If 403 is received setting boot method, API endpoint changed in 1738 FW, inform the user of work around.
                    $error = "Invalid endpoint used to set boot method. If running firmware < ibm-v1.99.10-0-r7, 'export XCAT_OPENBMC_FIRMWARE=1736' and retry.";
                } else {
                    $error = "$::RESPONSE_FORBIDDEN - Requested endpoint does not exists and may indicate function is not yet supported by OpenBMC firmware.";
                }
            # Handle 404 
            } elsif ($response->status_line eq $::RESPONSE_NOT_FOUND) {
                #
                # For any invalid data that we can detect, provide a better response message
                #
                if ($node_info{$node}{cur_status} eq "RFLASH_DELETE_IMAGE_RESPONSE") { 
                    $error = "Invalid ID provided to delete.  Use the -l option to view valid firmware IDs.";
                } else {
                    $error = "[" . $response->code . "] " . $response_info->{'data'}->{'description'};
                }
            } else {
                $error = "[" . $response->code . "] " . $response_info->{'data'}->{'description'};
            }
        }
        if (!($node_info{$node}{cur_status} eq "RSPCONFIG_DUMP_CLEAR_RESPONSE" and $next_status{ $node_info{$node}{cur_status} })) {
            xCAT::SvrUtils::sendmsg([1, $error], $callback, $node);
            if ($::UPLOAD_AND_ACTIVATE or $next_status{LOGIN_RESPONSE} eq "RFLASH_UPDATE_ACTIVATE_REQUEST") {
                $node_info{$node}{rst} = $error;
                my $rflash_log_file = xCAT::Utils->full_path($node.".log", $::XCAT_LOG_RFLASH_DIR);
                open (RFLASH_LOG_FILE_HANDLE, ">> $rflash_log_file");
                print RFLASH_LOG_FILE_HANDLE "$error\n";
                close (RFLASH_LOG_FILE_HANDLE);
            }
            $wait_node_num--;
            return;
        }
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
    my $ts_node = localtime() . " " . $node;
    if (!$debug_msg) {
        $debug_msg = "";
    }

    xCAT::SvrUtils::sendmsg("$flag_debug $debug_msg", $callback, $ts_node);
    xCAT::MsgUtils->trace(0, "D", "$flag_debug $node $debug_msg"); 
}

#-------------------------------------------------------

=head3  login_request

  Send login request using curl command
  Input:
        $node: nodename

=cut

#-------------------------------------------------------
sub login_request {
    my $node = shift;

    my $login_url = "$http_protocol://" . $node_info{$node}{bmc} . "/login";
    my $data = '{ "data": [ "' . $node_info{$node}{username} .'", "' . $node_info{$node}{password} . '" ] }';

    my $brower = LWP::UserAgent->new( ssl_opts => { SSL_verify_mode => 0x00, verify_hostname => 0  }, timeout => 20);
    my $cookie_jar = HTTP::Cookies->new();
    my $header = HTTP::Headers->new('Content-Type' => 'application/json');
    $brower->cookie_jar($cookie_jar);

    my $login_request = HTTP::Request->new( 'POST', $login_url, $header, $data );
    my $login_response = $brower->request($login_request);

    # Check the return code
    if ($login_response->code eq 500 or $login_response->code eq 404) { 
        # handle only 404 and 504 in this code, defer to deal_with_response for the rest
        xCAT::SvrUtils::sendmsg([1 ,"[" . $login_response->code . "] Login to BMC failed: " . $login_response->status_line . "."], $callback, $node);
        return 1;
    }

    return 0;
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
                if ($::UPLOAD_ACTIVATE_STREAM) {
                    retry_after($node, "RPOWER_BMC_CHECK_REQUEST", 15);
                    return;
                }
            }
            $new_status{$::STATUS_POWERING_ON} = [$node];
        }
    }

    xCAT_monitoring::monitorctrl::setNodeStatusAttributes(\%new_status, 1) if (%new_status);

    my $all_status;
    if ($node_info{$node}{cur_status} eq "RPOWER_STATUS_RESPONSE" or $node_info{$node}{cur_status} eq "RPOWER_CHECK_RESPONSE" or $node_info{$node}{cur_status} eq "RPOWER_BMC_STATUS_RESPONSE") {
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
        } elsif ($node_info{$node}{cur_status} eq "RPOWER_BMC_STATUS_RESPONSE" and  (defined $status_info{RPOWER_BMC_STATUS_RESPONSE}{argv}) and $status_info{RPOWER_BMC_STATUS_RESPONSE}{argv} =~ /bmcstate$/) {
                my $bmc_short_state = (split(/\./, $bmc_state))[-1];
                if (defined($bmc_state) and $bmc_state !~ /State.BMC.BMCState.Ready$/) {
                    if ($node_info{$node}{bmcstate_check_times} > 0) {
                    $node_info{$node}{bmcstate_check_times}--;
                    if ($node_info{$node}{wait_start}) {
                        $node_info{$node}{wait_end} = time();
                    } else {
                        $node_info{$node}{wait_start} = time();
                    }
                    retry_after($node, "RPOWER_BMC_STATUS_REQUEST", $::BMC_CHECK_INTERVAL);
                    return;
                } else {
                    my $wait_time_X = $node_info{$node}{wait_end} - $node_info{$node}{wait_start};
                    xCAT::SvrUtils::sendmsg([1, "Error: Sent bmcreboot but state did not change to BMC Ready after waiting $wait_time_X seconds. (State=BMC $bmc_short_state)."], $callback, $node);
                    $node_info{$node}{cur_status} = "";
                    $wait_node_num--;
                    return;
                }
                }
                xCAT::SvrUtils::sendmsg("BMC $bmc_short_state", $callback, $node);

        }else {
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
                    $all_status = $::POWER_STATE_OFF;
                } elsif ($host_state =~ /Quiesced$/) {
                    xCAT::SvrUtils::sendmsg("$::POWER_STATE_QUIESCED", $callback, $node) if (!$next_status{ $node_info{$node}{cur_status} });
                    $all_status = $::POWER_STATE_ON;
                } elsif ($host_state =~ /Running$/) {
                    if ((defined($::OPENBMC_PWR) and ($::OPENBMC_PWR eq "YES")) and
                           $host_transition_state =~ /Off$/ and $chassis_state =~ /On$/) {
                        xCAT::SvrUtils::sendmsg("$::POWER_STATE_POWERING_OFF", $callback, $node);
                    } else {
                        xCAT::SvrUtils::sendmsg("$::POWER_STATE_ON", $callback, $node) if (!$next_status{ $node_info{$node}{cur_status} });
                    }
                    $all_status = $::POWER_STATE_ON;
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
        if ($node_info{$node}{cur_status} eq "RPOWER_CHECK_RESPONSE") {
            if ($all_status eq "$::POWER_STATE_OFF") {
                $node_info{$node}{cur_status} = $next_status{ $node_info{$node}{cur_status} }{OFF};
            } else {
                if ($node_info{$node}{rpower_check_times} > 0) {
                    $node_info{$node}{rpower_check_times}--;
                    if ($node_info{$node}{wait_start}) {
                        $node_info{$node}{wait_end} = time();
                    } else {
                        $node_info{$node}{wait_start} = time();
                    }
                    retry_after($node, $next_status{ $node_info{$node}{cur_status} }{ON}, $::RPOWER_CHECK_INTERVAL);
                    return;
                } else {
                    my $wait_time_X = $node_info{$node}{wait_end} - $node_info{$node}{wait_start};
                    xCAT::SvrUtils::sendmsg([1, "Error: Sent power-off command but state did not change to $::POWER_STATE_OFF after waiting $wait_time_X seconds. (State=$all_status)."], $callback, $node);
                    $node_info{$node}{cur_status} = "";
                    $wait_node_num--;
                    return;
                }
            }
        } elsif ($node_info{$node}{cur_status} eq "RPOWER_STATUS_RESPONSE") {
            if ($all_status eq "$::POWER_STATE_OFF") {
                xCAT::SvrUtils::sendmsg("$::POWER_STATE_OFF", $callback, $node);
                $node_info{$node}{cur_status} = "";
                $wait_node_num--;
                return;
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
    my $to_clear_dump = 0;

    # Get the functional IDs to accurately mark the active running FW
    my $functional = get_functional_software_ids($response_info);

    foreach my $key_url (keys %{$response_info->{data}}) {
        my %content = %{ ${ $response_info->{data} }{$key_url} };

        if ($grep_string eq "firm") {
            # This handles the data from the /xyz/openbmc_project/Software endpoint.
            my $sw_id = (split(/\//, $key_url))[-1];
            if (defined($content{Version}) and $content{Version}) {
                my $purpose_value = uc ((split(/\./, $content{Purpose}))[-1]);
                if ($purpose_value =~ /BMC/) {
                    $purpose_value = "[B$sw_id]$purpose_value";
                } else {
                    $purpose_value = "[H$sw_id]$purpose_value";
                }
                my $activation_value = (split(/\./, $content{Activation}))[-1];
                my $priority_value = -1;
                if (defined($content{Priority})) {
                    $priority_value = $content{Priority};
                }

                if ($status_info{RINV_FIRM_RESPONSE}{check}) {
                    if (($purpose_value =~ /BMC/) and
                        ($priority_value == 0 and %{$functional} and !exists($functional->{$sw_id}))) {
                        $to_clear_dump = 1;
                        last;
                    }
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
                    my $indicator = "";
                    if ($priority_value == 0 and %{$functional} and !exists($functional->{$sw_id})) {
                        # indicate that a reboot is needed if priority = 0 and it's not in the functional list
                        $indicator = "+";
                    } elsif (%{$functional} and exists($functional->{$sw_id})) {
                        $indicator = "*";
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
    @sorted_output = () if ($status_info{RINV_FIRM_RESPONSE}{check});
    # If sorted array has any contents, sort it naturally and print it
    if (scalar @sorted_output > 0) {
        # sort alpha, then numeric 
        foreach (sort natural_sort_cmp @sorted_output) {
            #
            # The firmware output requires the ID to be part of the string to sort correctly.
            # Remove this ID from the output to the user
            #
            $_ =~ s/\[.*?\]//;
            xCAT::MsgUtils->message("I", { data => ["$node: $_"] }, $callback);
        }
    } else {
        if ($status_info{RINV_FIRM_RESPONSE}{check}) {
            if ($to_clear_dump) {
                xCAT::MsgUtils->message("I", { data => ["$node: Firmware will be flashed on reboot, deleting all BMC diagnostics..."] }, $callback);
            }
        } else {
            xCAT::MsgUtils->message("I", { data => ["$node: $::NO_ATTRIBUTES_RETURNED"] }, $callback);
        }
    }

    if ($next_status{ $node_info{$node}{cur_status} }) {
        if ($status_info{RINV_FIRM_RESPONSE}{check}) {
            if ($to_clear_dump) {
                $node_info{$node}{cur_status} = $next_status{ $node_info{$node}{cur_status} }{PENDING};
            } else {
                $node_info{$node}{cur_status} = $next_status{ $node_info{$node}{cur_status} }{NO_PENDING}
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
        my $entry_string = $status_info{REVENTLOG_RESPONSE}{argv};
        my $content_info; 
        my %output = ();
        my $entry_num = 0;
        $entry_string = "all" if ($entry_string eq "0");
        $entry_num = 0 + $entry_string if ($entry_string ne "all");
        my $max_entry = 0;

        foreach my $key_url (keys %{$response_info->{data}}) {
            my %content = %{ ${ $response_info->{data} }{$key_url} };
            next unless ($content{Id});
            my $id_num = 0 + $content{Id};
            my $event_msg = parse_event_data(\%content);
            $output{$id_num} = $event_msg if ($event_msg);
            $max_entry = $id_num if ($id_num > $max_entry);
        }

        xCAT::SvrUtils::sendmsg("$::NO_ATTRIBUTES_RETURNED", $callback, $node) if (!%output);
        # If option is "all", print out all sorted msg. If is a num, print out the last <num> msg (sorted)
        foreach my $key ( sort { $a <=> $b } keys %output) {
            xCAT::MsgUtils->message("I", { data => ["$node: $output{$key}"] }, $callback) if ($entry_string eq "all" or $key > ($max_entry - $entry_num));
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

=head3  parse_event_data

  Parse reventlog data
  Input:
        $content: data for single entry

=cut

#-------------------------------------------------------
sub parse_event_data {
    my $content = shift;
    my $content_info = "";

    my $timestamp = $$content{Timestamp};
    my $id_num = $$content{Id};
    if ($$content{Message}) {
        my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime($$content{Timestamp}/1000);
        $mon += 1;
        $year += 1900;
        my $UTC_time = sprintf ("%02d/%02d/%04d %02d:%02d:%02d", $mon, $mday, $year, $hour, $min, $sec);
        my $messgae = $$content{Message};
        my $callout;
        my $msg_pid;
        my $i2c_device;
        my $esel;

        if (defined $$content{AdditionalData} and $$content{AdditionalData}) {
            foreach my $addition (@{ $$content{AdditionalData} }) {
                if ($addition =~ /CALLOUT_INVENTORY_PATH=(.+)/) {
                    $callout = $1;
                }
                if ($addition =~ /CALLOUT_DEVICE_PATH/) {
                    $callout = "I2C";
                    my @info = split("=", $addition);
                    my $tmp = $info[1];
                    my @tmp_data = split("/", $tmp);
                    my $data_num = @tmp_data;
                    $i2c_device = join("/", @tmp_data[($data_num-4)..($data_num-1)])
                }
                if ($addition =~ /ESEL/) {
                    my @info = split("=", $addition);
                    $esel = $info[1];
                    # maybe useful, so leave it here
                }
                if ($addition =~ /GPU/) {
                    my @info = split(" ", $addition);
                    $callout = "/xyz/openbmc_project/inventory/system/chassis/motherboard/gpu" . $info[-1];
                }
                if ($addition =~ /PID=(\d*)/) {
                    $msg_pid = $1;
                }
            }
        }

        $messgae .= "||$callout" if ($callout);

        if (ref($event_mapping) eq "HASH") {
            if ($event_mapping->{$messgae}) {
                my $event_type = $event_mapping->{$messgae}{EventType};
                my $event_message = $event_mapping->{$messgae}{Message};
                my $severity = $event_mapping->{$messgae}{Severity};
                my $affect = $event_mapping->{$messgae}{AffectedSubsystem};
                $content_info = "$UTC_time [$id_num]: $event_type, ($severity) $event_message (AffectedSubsystem: $affect, PID: $msg_pid), Resolved: $$content{Resolved}";
            } else {
                $content_info = "$UTC_time [$id_num]: Not found in policy table: $messgae (PID: $msg_pid), Resolved: $$content{Resolved}";
            }
        } else {
            $content_info = "$UTC_time [$id_num]: $messgae (PID: $msg_pid), Resolved: $$content{Resolved}";
        }
    }

    return $content_info;
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

    my $response_info;
    $response_info = decode_json $response->content if ($response);

    if ($node_info{$node}{cur_status} eq "RSPCONFIG_GET_RESPONSE" or $node_info{$node}{cur_status} eq "RSPCONFIG_GET_NIC_RESPONSE") {
        my $hostname        = "";
        my $default_gateway = "n/a";
        my %nicinfo         = ();
        my $multiple_error = "";
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

            my ($path, $adapter_id) = (split(/\/ipv4\//, $key_url));
            
            if ($adapter_id) {
                if ( (defined($content{Origin}) and $content{Origin} =~ /LinkLocal/) or 
                     (defined($content{Address}) and $content{Address} =~ /^169.254/) ) {
                    # OpenBMC driver has a interim bug where ZeroConfigIP comes up as DHCP instead of LinkLocal.
                    # To protect xCAT while the drivers change, check the 169.254 IP also 
                    if ($xcatdebugmode) {
                        my $debugmsg = "Found LocalLink " . $content{Address} . " for interface " . $key_url . " Ignoring...";
                        process_debug_info($node, $debugmsg);
                    }
                    next;
                }
                my $nic = $path;
                $nic =~ s/(.*\/)//g;
                unless (defined($nicinfo{$nic}{address})) {
                    $nicinfo{$nic}{address} = ();
                    $nicinfo{$nic}{gateway} = ();
                    $nicinfo{$nic}{ipsrc}   = ();
                    $nicinfo{$nic}{netmask} = ();
                    $nicinfo{$nic}{prefix}  = ();
                    $nicinfo{$nic}{vlan}    = "Disable";
                }


                if (defined($content{Address}) and $content{Address}) {
                    if ($content{Address} eq $node_info{$node}{bmcip} and $node_info{$node}{cur_status} eq "RSPCONFIG_GET_NIC_RESPONSE") {
                        $status_info{RSPCONFIG_SET_NTPSERVERS_REQUEST}{init_url} =~ s/#NIC#/$nic/g;
                        if ($next_status{"RSPCONFIG_GET_NIC_RESPONSE"}) {
                            $node_info{$node}{cur_status} = $next_status{"RSPCONFIG_GET_NIC_RESPONSE"};
                            gen_send_request($node);
                            return;
                        }
                    }
                    if ($nicinfo{$nic}{address}) {
                        $multiple_error = "Interfaces with multiple IP addresses are not supported";
                    }
                    push @{ $nicinfo{$nic}{address} }, $content{Address};
                }
                if (defined($content{Gateway}) and $content{Gateway}) {
                    push @{ $nicinfo{$nic}{gateway} }, $content{Gateway};
                }
                if (defined($content{PrefixLength}) and $content{PrefixLength}) {
                    push @{ $nicinfo{$nic}{prefix} }, $content{PrefixLength};
                }
                if (defined($content{Origin})) {
                    my $ipsrc_tmp = $content{Origin};
                    $ipsrc_tmp =~ s/^.*\.(\w+)/$1/;
                    push @{ $nicinfo{$nic}{ipsrc} }, $ipsrc_tmp;
                }

                if (defined($response_info->{data}->{$path}->{Id})) {
                    $nicinfo{$nic}{vlan} = $response_info->{data}->{$path}->{Id};
                }

                if (defined($response_info->{data}->{$path}->{NTPServers})) {
                    $nicinfo{$nic}{ntpservers} = join(",", @{ $response_info->{data}->{$path}->{NTPServers} });
                }
            }
        }

        if (scalar (keys %nicinfo) == 0) {
            my $error = "No valid BMC network information";
            xCAT::SvrUtils::sendmsg([1, "$error"], $callback, $node);
            $node_info{$node}{cur_status} = "";  
        } else {
            my @address = ();
            my @ipsrc = ();
            my @netmask = ();
            my @gateway = ();
            my @vlan = (); 
            my @ntpservers = ();
            my @nics = keys %nicinfo;
            foreach my $nic (@nics) {
                my $addon_info = '';
                if ($#nics > 1) {
                    $addon_info = " for $nic";
                }

                if ($nicinfo{$nic}{ntpservers}) {
                    push @ntpservers, "BMC NTP Servers$addon_info: $nicinfo{$nic}{ntpservers}";
                } else {
                    push @ntpservers, "BMC NTP Servers$addon_info: None";
                }

                next if ($multiple_error);

                push @address, "BMC IP$addon_info: ${ $nicinfo{$nic}{address} }[0]";
                push @ipsrc, "BMC IP Source$addon_info: ${ $nicinfo{$nic}{ipsrc} }[0]";
                if ($nicinfo{$nic}{address}) {
                    my $mask_shift = 32 - ${ $nicinfo{$nic}{prefix} }[0];
                    my $decimal_mask = (2 ** ${ $nicinfo{$nic}{prefix} }[0] - 1) << $mask_shift;
                    push @netmask, "BMC Netmask$addon_info: " . join('.', unpack("C4", pack("N", $decimal_mask)));
                }
                push @gateway, "BMC Gateway$addon_info: ${ $nicinfo{$nic}{gateway} }[0] (default: $default_gateway)";
                push @vlan, "BMC VLAN ID$addon_info: $nicinfo{$nic}{vlan}";
            }
            my $mul_out = 0;
            foreach my $opt (split /,/,$grep_string) {
                if ($opt eq "hostname") {
                    push @output, "BMC Hostname: $hostname";
                } elsif ($opt eq "ntpservers") {
                    push @output, @ntpservers;
                }

                if ($multiple_error and ($opt =~  /^ip$|^ipsrc$|^netmask$|^gateway$|^vlan$/)) {
                    $mul_out = 1;
                    next;
                }
                if ($opt eq "ip") {
                    push @output, @address; 
                } elsif ($opt eq "ipsrc") {
                    push @output, @ipsrc;
                } elsif ($opt eq "netmask") {
                    push @output, @netmask;
                } elsif ($opt eq "gateway") {
                    push @output, @gateway; 
                } elsif ($opt eq "vlan") {
                    push @output, @vlan;
                }
            }
            
            xCAT::SvrUtils::sendmsg("$_", $callback, $node) foreach (@output);
            if ($multiple_error and $mul_out) {
                xCAT::SvrUtils::sendmsg([1, "$multiple_error"], $callback, $node);
                $wait_node_num--;
                return;
            }
            
            if ($grep_string eq "all") {
                # If all current values equal the input, just print out message
                my @checks = split("-", $status_info{RSPCONFIG_CHECK_RESPONSE}{argv});
                my $check_num = @checks;
                my $check_vlan;
                if ($check_num == 4) {
                    $check_vlan = shift @checks;
                }
                my ($check_ip,$check_netmask,$check_gateway) = @checks;
                my $the_nic_to_config = undef;
                foreach my $nic (@nics) {
                    my $address = ${ $nicinfo{$nic}{address} }[0];
                    my $prefix = ${ $nicinfo{$nic}{prefix} }[0];
                    my $gateway = ${ $nicinfo{$nic}{gateway} }[0];
                    if ($check_ip eq $address and $check_netmask eq $prefix and $check_gateway eq $gateway) {
                        if (($check_vlan and $check_vlan eq $nicinfo{$nic}{vlan}) or !$check_vlan) {
                            $next_status{ $node_info{$node}{cur_status} } = "RSPCONFIG_PRINT_BMCINFO";
                            $the_nic_to_config = $nic;
                            last;
                        }
                    }
                    # Only deal with the nic whose IP matching the BMC IP configured for the node
                    if ($address eq $node_info{$node}{bmcip}) {
                        $the_nic_to_config = $nic;
                        last;
                    }
                }
                if (!defined($the_nic_to_config)) {
                    xCAT::SvrUtils::sendmsg("Can not find the correct device to configure", $callback, $node);
                    $wait_node_num--;
                    return;
                } else {
                    my $next_state = $next_status{ $node_info{$node}{cur_status} };
                    # To create an Object with vlan tag, shall be operated to the eth0
                    if ($next_state eq "RSPCONFIG_VLAN_REQUEST") {
                        $the_nic_to_config =~ s/(\_\d*)//g;
                        $status_info{$next_state}{data} =~ s/#NIC#/$the_nic_to_config/g;
                    }
                    $status_info{RSPCONFIG_IPOBJECT_REQUEST}{init_url} =~ s/#NIC#/$the_nic_to_config/g;
                    $node_info{$node}{nic} = $the_nic_to_config;
                }
            }
        }
    }
 
    my $origin_type;
    if ($node_info{$node}{cur_status} eq "RSPCONFIG_CHECK_RESPONSE") {
        my @checks = split("-", $status_info{RSPCONFIG_CHECK_RESPONSE}{argv});
        my $check_num = @checks;
        my $check_vlan;
        if ($check_num == 4) {
            $check_vlan = shift @checks;
        }
        my ($check_ip,$check_netmask,$check_gateway) = @checks;
        my $check_result = 0;
        foreach my $key_url (keys %{$response_info->{data}}) {
            my %content = %{ ${ $response_info->{data} }{$key_url} };
            my ($path, $adapter_id) = (split(/\/ipv4\//, $key_url));
            if ($adapter_id) {
                if (defined($content{Address}) and $content{Address}) {
                    if ($content{Address} eq $node_info{$node}{bmcip}) {
                        if ($content{Origin} =~ /Static/) {
                            $origin_type = "STATIC";
                            $status_info{RSPCONFIG_DELETE_REQUEST}{init_url} = "$key_url";
                        } else {
                            $origin_type = "DHCP";
                            my $nic = $path;
                            $nic =~ s/(.*\/)//g;
                            $status_info{RSPCONFIG_DHCPDIS_REQUEST}{init_url} =~ s/#NIC#/$nic/g
                        }
                    } else {
                        if (($content{Address} eq $check_ip) and
                            ($content{PrefixLength} eq $check_netmask) and
                            ($content{Gateway} eq $check_gateway)) {
                            if ($check_vlan) {
                                if (defined($response_info->{data}->{$path}->{Id}) and $response_info->{data}->{$path}->{Id} eq $check_vlan) {
                                    $check_result = 1;
                                }
                            } else {
                               $check_result = 1;
                            }
                        }
                    }
                }
            }
        }
        if (!$check_result or !$origin_type) {
            xCAT::SvrUtils::sendmsg("Config IP failed", $callback, $node);
            $next_status{ $node_info{$node}{cur_status} } = "";
        }
    }

    if ($node_info{$node}{cur_status} eq "RSPCONFIG_PASSWD_VERIFY") {
        if ($status_info{RSPCONFIG_PASSWD_VERIFY}{argv} ne $node_info{$node}{password}) {
            xCAT::SvrUtils::sendmsg("Current BMC password is incorrect, cannot set the new password.", $callback, $node);
            $wait_node_num--;
            return;
        }
    }

    if ($node_info{$node}{cur_status} eq "RSPCONFIG_SET_RESPONSE") {
        if ($response_info->{'message'} eq $::RESPONSE_OK) {
            if (defined $status_info{RSPCONFIG_SET_RESPONSE}{argv}) {
                xCAT::SvrUtils::sendmsg("BMC Setting $status_info{RSPCONFIG_SET_RESPONSE}{argv}...", $callback, $node);
            }
        }
    }
    if ($node_info{$node}{cur_status} eq "RSPCONFIG_DHCP_RESPONSE") {
        if ($response_info->{'message'} eq $::RESPONSE_OK) {
            xCAT::SvrUtils::sendmsg("BMC Setting IP to DHCP...", $callback, $node);
        }
    }

    if ($node_info{$node}{cur_status} eq "RSPCONFIG_PRINT_BMCINFO") {
        if ($status_info{RSPCONFIG_PRINT_BMCINFO}{data}) {
            my @output = split(",", $status_info{RSPCONFIG_PRINT_BMCINFO}{data});
            xCAT::SvrUtils::sendmsg($_, $callback, $node) foreach (@output);
        }
    }

    if ($node_info{$node}{cur_status} eq "RSPCONFIG_VLAN_RESPONSE") {
        if ($xcatdebugmode) {
             process_debug_info($node, "Wait $::RSPCONFIG_WAIT_VLAN_DONE seconds for interface with VLAN tag be ready");
        }
        retry_after($node, $next_status{ $node_info{$node}{cur_status} }, $::RSPCONFIG_WAIT_VLAN_DONE);
        return;
    }

    if ($node_info{$node}{cur_status} eq "RSPCONFIG_IPOBJECT_RESPONSE") {
        if ($xcatdebugmode) {
             process_debug_info($node, "Wait $::RSPCONFIG_WAIT_IP_DONE seconds for the configuration done");
        }
        retry_after($node, $next_status{ $node_info{$node}{cur_status} }, $::RSPCONFIG_WAIT_IP_DONE);
        return;
    }

    if ($node_info{$node}{cur_status} eq "RSPCONFIG_CLEAR_GARD_RESPONSE") {
        if ($response_info->{'message'} eq $::RESPONSE_OK) {
            xCAT::SvrUtils::sendmsg("GARD cleared", $callback, $node);
        }
    }

    if ($next_status{ $node_info{$node}{cur_status} }) {
        if ($node_info{$node}{cur_status} eq "RSPCONFIG_CHECK_RESPONSE") {
            $node_info{$node}{cur_status} = $next_status{ $node_info{$node}{cur_status} }{$origin_type};
        } else {
            $node_info{$node}{cur_status} = $next_status{ $node_info{$node}{cur_status} };
        }
        if ($node_info{$node}{cur_status} eq "RSPCONFIG_PRINT_BMCINFO") {
            $status_info{ $node_info{$node}{cur_status} }->{process}->($node, "");
        } else {
            gen_send_request($node);
        }
    } else {
        $wait_node_num--;
    } 
}

#-------------------------------------------------------

=head3  rspconfig_api_config_response

  Deal with response of rspconfig command for configured subcommand

  Currently understands only generic boolean setting and query responses
  Input:
        $node: nodename of current response
        $response: Async return response

=cut

#-------------------------------------------------------
sub rspconfig_api_config_response {
    my $node = shift;
    my $response = shift;

    my $response_info;
    my $value = -1;
    $response_info = decode_json $response->content if ($response);


    if ($node_info{$node}{cur_status}) {
        if ($node_info{$node}{cur_status} eq "RSPCONFIG_API_CONFIG_ON_RESPONSE") {
            if ($response_info->{'message'} eq $::RESPONSE_OK) {
                xCAT::SvrUtils::sendmsg("BMC Setting ". $api_config_info{$::RSPCONFIG_CONFIGURED_API_KEY}{display_name} . "...", $callback, $node);
            }
            else {
                xCAT::SvrUtils::sendmsg("Error setting RSPCONFIG_API_CONFIG_ON_RESPONSE", $callback, $node);
            }
        }
        elsif ($node_info{$node}{cur_status} eq "RSPCONFIG_API_CONFIG_OFF_RESPONSE") {
            if ($response_info->{'message'} eq $::RESPONSE_OK) {
                xCAT::SvrUtils::sendmsg("BMC Setting ". $api_config_info{$::RSPCONFIG_CONFIGURED_API_KEY}{display_name} . "...", $callback, $node);
            }
            else {
                xCAT::SvrUtils::sendmsg("Error unsetting RSPCONFIG_API_CONFIG_OFF_RESPONSE", $callback, $node);
            }
        }
        elsif ($node_info{$node}{cur_status} eq "RSPCONFIG_API_CONFIG_QUERY_RESPONSE") {
            if ($response_info->{'message'} eq $::RESPONSE_OK) {
                foreach my $key_url (keys %{$response_info->{data}}) {
                    if ($key_url eq  $api_config_info{$::RSPCONFIG_CONFIGURED_API_KEY}{attr_url}) {
                        #Is this the attribute we are looking for ?
                        $value = $response_info->{data}{$key_url};
                        last;
                    }
                }
                if (scalar($value) >= 0) {
                    xCAT::SvrUtils::sendmsg($api_config_info{$::RSPCONFIG_CONFIGURED_API_KEY}{display_name} . ": $value", $callback, $node);
                }
                else {
                    xCAT::SvrUtils::sendmsg("Unable to query value for " . $api_config_info{$::RSPCONFIG_CONFIGURED_API_KEY}{attr_url}, $callback, $node);
                }
            }
            else {
                xCAT::SvrUtils::sendmsg("Error query RSPCONFIG_API_CONFIG_QUERY_RESPONSE", $callback, $node);
            }
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
            $async->remove_all;
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

=head3  rspconfig_dump_response

  Deal with request and response of rspconfig command for dump subcommand.
  Input:
        $node: nodename of current response
        $response: Async return response

=cut

#-------------------------------------------------------
sub rspconfig_dump_response {
    my $node = shift;
    my $response = shift;

    my $response_info = decode_json $response->content if (defined($response));

    if ($node_info{$node}{cur_status} eq "RSPCONFIG_DUMP_LIST_RESPONSE" or $node_info{$node}{cur_status} eq "RSPCONFIG_DUMP_CHECK_RESPONSE") {
        my %dump_info = ();
        my $gen_check = 0;
        foreach my $key_url (keys %{$response_info->{data}}) {
            my %content = %{ ${ $response_info->{data} }{$key_url} };
            my $id;
            if (defined $content{Elapsed}) {
                $id = $key_url;
                $id =~ s/.*\///g; 

                if ($node_info{$node}{cur_status} eq "RSPCONFIG_DUMP_CHECK_RESPONSE") {
                    if ($id eq $node_info{$node}{dump_id}) {
                        $gen_check = 1;
                        last;
                    }
                    next;
                }

                my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime($content{Elapsed});
                $mon += 1;
                $year += 1900;
                my $UTC_time = sprintf ("%02d/%02d/%04d %02d:%02d:%02d", $mon, $mday, $year, $hour, $min, $sec);
                $dump_info{$id} = "[$id] Generated: $UTC_time, Size: $content{Size}"; 
            }
        }

        xCAT::SvrUtils::sendmsg("$::NO_ATTRIBUTES_RETURNED", $callback, $node) if (!%dump_info and $node_info{$node}{cur_status} eq "RSPCONFIG_DUMP_LIST_RESPONSE");
        foreach my $key ( sort { $a <=> $b } keys %dump_info) {
            xCAT::MsgUtils->message("I", { data => ["$node: $dump_info{$key}"] }, $callback) if ($dump_info{$key});
        }

        if (!$gen_check and $node_info{$node}{cur_status} eq "RSPCONFIG_DUMP_CHECK_RESPONSE") {
            if (!exists($node_info{$node}{dump_wait_attemp})) {
                $node_info{$node}{dump_wait_attemp} = $::RSPCONFIG_DUMP_MAX_RETRY;
            }
            if ( $node_info{$node}{dump_wait_attemp} > 0) {
                $node_info{$node}{dump_wait_attemp} --; 
                retry_after($node, "RSPCONFIG_DUMP_LIST_REQUEST", $::RSPCONFIG_DUMP_INTERVAL);
                unless ($node_info{$node}{dump_wait_attemp} % int(8)) { # display message every 8 iterations of the interval
                    xCAT::SvrUtils::sendmsg("Still waiting for dump $node_info{$node}{dump_id} to be generated...", $callback, $node);
                }
                return;
            } else {
                xCAT::SvrUtils::sendmsg([1,"Could not find dump $node_info{$node}{dump_id} after waiting $::RSPCONFIG_DUMP_WAIT_TOTALTIME seconds."], $callback, $node);
                $wait_node_num--;
                return;
            }
        }
    } 

    if ($node_info{$node}{cur_status} eq "RSPCONFIG_DUMP_DOWNLOAD_REQUEST") {
        my $child = xCAT::Utils->xfork;
        if (!defined($child)) {
            xCAT::SvrUtils::sendmsg("Failed to fork child process for rspconfig dump download.", $callback, $node);
            sleep(1)
        } elsif ($child == 0) {
            $async->remove_all;
            exit(dump_download_process($node))
        } else {
            $child_node_map{$child} = $node;
        }
        $node_info{$node}{cur_status} = $next_status{ $node_info{$node}{cur_status} };
        return;
    }

    if ($node_info{$node}{cur_status} eq "RSPCONFIG_DUMP_CREATE_RESPONSE") {
        if ($response_info->{'message'} eq $::RESPONSE_OK) {
            if ($response_info->{'data'}) {
                my $dump_id = $response_info->{'data'};
                if ($next_status{ $node_info{$node}{cur_status} }) {
                    $node_info{$node}{dump_id} = $dump_id;
                    xCAT::SvrUtils::sendmsg("Dump requested. Target ID is $dump_id, waiting for BMC to generate...", $callback, $node);
                } else {
                    xCAT::SvrUtils::sendmsg("[$dump_id] success", $callback, $node);
                }
            } else {
                xCAT::SvrUtils::sendmsg([1, "BMC returned $::RESPONSE_OK but no ID was returned.  Verify manually on the BMC."], $callback, $node);
                $wait_node_num--;
                return;
            }
        } 
    }

    if ($node_info{$node}{cur_status} eq "RSPCONFIG_DUMP_CLEAR_RESPONSE") {
        if ($response_info->{'message'} eq $::RESPONSE_OK) {
            my $dump_id = $status_info{RSPCONFIG_DUMP_CLEAR_RESPONSE}{argv};
            xCAT::MsgUtils->message("I", { data => ["[$dump_id] clear"] }, $callback) unless ($next_status{ $node_info{$node}{cur_status} });
        } else {
            my $error_msg = "Could not clear BMC diagnostics successfully (". $response_info->{'message'} . "), ignoring...";
            xCAT::MsgUtils->message("W", { data => ["$node: $error_msg"] }, $callback) if ($next_status{ $node_info{$node}{cur_status} });
        }
    } 

    if ($next_status{ $node_info{$node}{cur_status} }) {
        $node_info{$node}{cur_status} = $next_status{ $node_info{$node}{cur_status} };
        if ($node_info{$node}{method} || $status_info{ $node_info{$node}{cur_status} }{method}) {
            gen_send_request($node);
        } elsif ($status_info{ $node_info{$node}{cur_status} }->{process}) {
            $status_info{ $node_info{$node}{cur_status} }->{process}->($node, undef);
        }
    } else {
        $wait_node_num--;
    }
}

#-------------------------------------------------------

=head3  dump_download_process

  Process of download dump tar.xz.
  Input:
        $node: nodename of current response

=cut

#-------------------------------------------------------
sub dump_download_process {
    my $node = shift;

    my $request_url = "$http_protocol://" . $node_info{$node}{bmc};
    my $content_login = '{ "data": [ "' . $node_info{$node}{username} .'", "' . $node_info{$node}{password} . '" ] }';
    my $content_logout = '{ "data": [ ] }';
    my $cjar_id = "/tmp/_xcat_cjar.$node";
    my $dump_id;
    $dump_id  = $status_info{RSPCONFIG_DUMP_DOWNLOAD_REQUEST}{argv} if ($status_info{RSPCONFIG_DUMP_DOWNLOAD_REQUEST}{argv});
    $dump_id = $node_info{$node}{dump_id} if ($node_info{$node}{dump_id});
    my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime($::RSPCONFIG_DUMP_CMD_TIME);
    $mon += 1;
    $year += 1900;
    my $formatted_time = sprintf ("%04d%02d%02d-%02d%02d", $year, $mon, $mday, $hour, $min);
    my $file_name = $::XCAT_LOG_DUMP_DIR . $formatted_time . "_$node" . "_dump_$dump_id.tar.xz";
    my $down_url;
    $down_url = $status_info{RSPCONFIG_DUMP_DOWNLOAD_REQUEST}{init_url};
    $down_url =~ s/#ID#/$dump_id/g;

    my $curl_login_cmd  = "curl -c $cjar_id -k -H 'Content-Type: application/json' -X POST $request_url/login -d '" . $content_login . "'";
    my $curl_logout_cmd = "curl -b $cjar_id -k -H 'Content-Type: application/json' -X POST $request_url/logout -d '" . $content_logout . "'";
    my $curl_dwld_cmd = "curl -J -b $cjar_id -k -H 'Content-Type: application/octet-stream' -X GET $request_url/$down_url -o $file_name";

    my $curl_login_result = `$curl_login_cmd -s`;
    my $h;
    if (!$curl_login_result) {
        xCAT::SvrUtils::sendmsg([1, "Did not receive response from OpenBMC after running command '$curl_login_cmd'"], $callback, $node);
        return 1;
    }
    eval { $h = from_json($curl_login_result) };
    if ($@) {
        xCAT::SvrUtils::sendmsg([1, "Received wrong format response for command '$curl_login_cmd': $curl_login_result)"], $callback, $node);
        return 1;
    }
    if ($h->{message} eq $::RESPONSE_OK) {
        xCAT::SvrUtils::sendmsg("Dump $dump_id generated. Downloading to $file_name", $callback, $node);
        my $curl_dwld_result = `$curl_dwld_cmd -s`;
        if (!$curl_dwld_result) {
            if ($xcatdebugmode) {
                my $debugmsg = "RSPCONFIG_DUMP_DOWNLOAD_REQUEST: CMD: $curl_dwld_cmd";
                process_debug_info($node, $debugmsg);
            }
            `$curl_logout_cmd -s`;
            # Verify the file actually got downloaded
            if (-e $file_name) {
                xCAT::SvrUtils::sendmsg("Downloaded dump $dump_id to $file_name", $callback, $node) if ($::VERBOSE);
            }
            else {
                xCAT::SvrUtils::sendmsg([1, "Failed to download dump $dump_id to $file_name. Verify destination directory exists and has correct access permissions."], $callback, $node);
                return 1;
            }
        } else {
            xCAT::SvrUtils::sendmsg([1, "Failed to download dump $dump_id :" . $h->{message} . " - " . $h->{data}->{description}], $callback, $node);
            return 1;
        }
    } else {
        xCAT::SvrUtils::sendmsg([1, "Unable to login :" . $h->{message} . " - " . $h->{data}->{description}], $callback, $node);
        return 1;
    }
    return 0;
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

    my $grep_string;
    if ($node_info{$node}{cur_status} =~ "RVITALS_LEDS_RESPONSE") {
        $grep_string = $status_info{RVITALS_LEDS_RESPONSE}{argv};
    } else { 
        $grep_string = $status_info{RVITALS_RESPONSE}{argv};
    }
    my $src;
    my $content_info;
    my @sorted_output;

    my %leds = ();

    foreach my $key_url (keys %{$response_info->{data}}) {
        my %content = %{ ${ $response_info->{data} }{$key_url} };

        my $label = (split(/\//, $key_url))[ -1 ];
        # replace underscore with space, uppercase the first letter 
        $label =~ s/_/ /g;
        $label =~ s/\b(\w)/\U$1/g;

        my $calc_value = undef;

        if ($node_info{$node}{cur_status} =~ "RVITALS_LEDS_RESPONSE") {
            # Print out Led info
            $calc_value = (split(/\./, $content{State}))[-1];
            $content_info = $label . ": " . $calc_value ;

            if ($key_url =~ "fan0") { $leds{fan0} = $calc_value; } 
            if ($key_url =~ "fan1") { $leds{fan1} = $calc_value; } 
            if ($key_url =~ "fan2") { $leds{fan2} = $calc_value; } 
            if ($key_url =~ "fan3") { $leds{fan3} = $calc_value; } 
            if ($key_url =~ "front_id") { $leds{front_id} = $calc_value; } 
            if ($key_url =~ "front_fault") { $leds{front_fault} = $calc_value; } 
            if ($key_url =~ "front_power") { $leds{front_power} = $calc_value; } 
            if ($key_url =~ "rear_id") { $leds{rear_id} = $calc_value; } 
            if ($key_url =~ "rear_fault") { $leds{rear_fault} = $calc_value; } 
            if ($key_url =~ "rear_power") { $leds{rear_power} = $calc_value; } 

        } else {
            # print out Sensor info
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

            #
            # Calculate the adjusted value based on the scale attribute
            #  
            $calc_value = $content{Value};
            if ( $content{Scale} != 0 ) { 
                $calc_value = ($content{Value} * (10 ** $content{Scale}));
            } 

            $content_info = $label . ": " . $calc_value . " " . $sensor_units{ $content{Unit} };
            push (@sorted_output, $content_info); #Save output in array
        } 
    }

    if ($node_info{$node}{cur_status} =~ "RVITALS_LEDS_RESPONSE") {
        $content_info = "Front . . . . . : Power:$leds{front_power} Fault:$leds{front_fault} Identify:$leds{front_id}";
        push (@sorted_output, $content_info);
        $content_info = "Rear  . . . . . : Power:$leds{rear_power} Fault:$leds{rear_fault} Identify:$leds{rear_id}";
        push (@sorted_output, $content_info);
        # Fans 
        if ($leds{fan0} =~ "Off" and $leds{fan1} =~ "Off" and $leds{fan2} eq "Off" and $leds{fan3} eq "Off") {
            $content_info = "Front Fans  . . : No LEDs On";
        } else { 
            $content_info = "Front Fans  . . : fan0:$leds{fan0} fan1:$leds{fan1} fan2:$leds{fan2} fan3:$leds{fan3}";
        } 
        push (@sorted_output, $content_info);
    }

    # If sorted array has any contents, sort it and print it
    if (scalar @sorted_output > 0) {
        # Sort the output, alpha, then numeric
        xCAT::MsgUtils->message("I", { data => ["$node: $_"] }, $callback) foreach (sort natural_sort_cmp @sorted_output);
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
    my $rflash_log_file = xCAT::Utils->full_path($node.".log", $::XCAT_LOG_RFLASH_DIR);
    open (RFLASH_LOG_FILE_HANDLE, ">> $rflash_log_file");
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
            # Initialize values to Unknown for each loop, incase they are not defined in the BMC
            $update_activation = "Unknown";
            $update_purpose = "Unknown";
            $update_version = "Unknown";

            my %content = %{ ${ $response_info->{data} }{$key_url} };

            $update_id = (split(/\//, $key_url))[ -1 ];
            if (defined($content{Version}) and $content{Version}) {
                $update_version = $content{Version};
            }
            else {
                # Entry has no Version attribute, skip listing it
                next;
            }
            if ($xcatdebugmode) {
                # Only print if xcatdebugmode is set and XCATBYPASS
                print "\n\n================================= XCATBYPASS DEBUG START =================================\n";
                print "==> KEY_URL=$key_url\n";
                print "==> VERSION=$content{Version}\n";
                print "==> Dump out JSON data:\n";
                print Dumper(%content);
                print "================================= XCATBYPASS DEBUG END   =================================\n";
            }
            if (defined($content{Activation}) and $content{Activation}) {
                $update_activation = (split(/\./, $content{Activation}))[ -1 ];
            }
            if (defined($content{Purpose}) and $content{Purpose}) {
                $update_purpose = (split(/\./, $content{Purpose}))[ -1 ];
            }

            my $update_priority = -1;
            # Just check defined, because priority=0 is a valid value
            if (defined($content{Priority}))  {
                $update_priority = (split(/\./, $content{Priority}))[ -1 ];
            }

            # Add indicators to the active firmware
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
        if ($::UPLOAD_FILE){
            $fw_tar_files{$::UPLOAD_FILE}=$::UPLOAD_FILE_VERSION;
        }
        if ($::UPLOAD_PNOR){
            $fw_tar_files{$::UPLOAD_PNOR}=$::UPLOAD_PNOR_VERSION;
        }
        if (%fw_tar_files) {
            my $child = xCAT::Utils->xfork;
            if (!defined($child)) {
                xCAT::SvrUtils::sendmsg("Failed to fork child process to upload firmware image.", $callback, $node);
                sleep(1)
            } elsif ($child == 0) {
                $async->remove_all;
                exit(rflash_upload($node, $callback))
            } else {
                $child_node_map{$child} = $node;
            }
        }
    }
    if ($node_info{$node}{cur_status} eq "RFLASH_UPDATE_ACTIVATE_RESPONSE") {
        my $flash_started_msg = "rflash $::UPLOAD_FILE_VERSION started, please wait...";
        if ($::VERBOSE) {
            xCAT::SvrUtils::sendmsg("$flash_started_msg", $callback, $node);
        }
        print RFLASH_LOG_FILE_HANDLE "$flash_started_msg\n";
    }
    if ($node_info{$node}{cur_status} eq "RFLASH_UPDATE_HOST_ACTIVATE_RESPONSE") {
        my $flash_started_msg = "rflash $::UPLOAD_PNOR_VERSION started, please wait...";
        if ($::VERBOSE) {
            xCAT::SvrUtils::sendmsg("$flash_started_msg", $callback, $node);
        }
        print RFLASH_LOG_FILE_HANDLE "$flash_started_msg\n";
    }
    if ($node_info{$node}{cur_status} eq "RFLASH_SET_PRIORITY_RESPONSE") {
        print "Update priority has been set";
    }
    if ($node_info{$node}{cur_status} eq "RFLASH_UPDATE_CHECK_STATE_RESPONSE") {
        my %activation_state;
        my %progress_state;
        my %priority_state;
        my %update_ids;
        my $update_res=0;
        my $version;
        foreach my $key_url (keys %{$response_info->{data}}) {
            if ($::UPLOAD_ACTIVATE_STREAM or $::UPLOAD_AND_ACTIVATE) {
                my %content = %{${$response_info->{data}}{$key_url}};
                $version = $content{Version};
                if (defined($version)) {
                    if ($version ne $::UPLOAD_FILE_VERSION and $version ne $::UPLOAD_PNOR_VERSION) {
                        next;
                    }
                    # Get values of some attributes to determine activation status 
                    $activation_state{$version} = $content{Activation};
                    $progress_state{$version} = $content{Progress};
                    $priority_state{$version} = $content{Priority};
                    $update_ids{$version} = (split(/\//, $key_url))[ -1 ];
                }
            } else {
                # This is for -a <ID> option
                $version = "default";
                if ($key_url eq "Activation") {
                    $activation_state{$version} = ${ $response_info->{data} }{$key_url};
                }
                if ($key_url eq "Progress") {
                    $progress_state{$version} = ${ $response_info->{data} }{$key_url};
                }
                if ($key_url eq "Priority") {
                    $priority_state{$version} = ${ $response_info->{data} }{$key_url};
                }
            }
        }
        my $firm_msg;
        my $version_num = 0;
        my $rsp;
        my $length = keys %activation_state;
        foreach my $firm_version (keys %activation_state) {
            if ($firm_version eq "default") {
                $firm_msg = "Firmware";
            } else {
                $firm_msg = "Firmware $firm_version";
            }
            if ($activation_state{$firm_version} =~ /Software.Activation.Activations.Failed/) {
                # Activation failed. Report error and exit
                my $flash_failed_msg = "$firm_msg activation failed.";
                xCAT::SvrUtils::sendmsg([1,"$flash_failed_msg"], $callback, $node);
                $update_res = 1;
                print RFLASH_LOG_FILE_HANDLE "$flash_failed_msg\n";
                close (RFLASH_LOG_FILE_HANDLE);
                $node_info{$node}{rst} = "$flash_failed_msg";
            } elsif ($activation_state{$firm_version} =~ /Software.Activation.Activations.Active/) {
                if (scalar($priority_state{$firm_version}) == 0) {
                    $version_num ++;
                    my $flash_success_msg = "$node: $firm_msg activation successful.";    
                    push @{ $rsp->{data} },$flash_success_msg;
                    # Activation state of active and priority of 0 indicates the activation has been completed
                    if ( $length == $version_num ) { 
                        xCAT::MsgUtils->message("I", $rsp, $callback) if ($rsp); 
                        print RFLASH_LOG_FILE_HANDLE "$flash_success_msg\n";
                        $node_info{$node}{rst} = "$flash_success_msg";
                        if (!$::UPLOAD_ACTIVATE_STREAM) {
                            $wait_node_num--;
                            return;
                        }
                        else{
                            $next_status{ $node_info{$node}{cur_status} } = "RPOWER_BMCREBOOT_REQUEST";
                        }
                    }
                } else {
                    # Activation state of active and priority of non 0 - need to just set priority to 0 to activate
                    print "$firm_version update is already active, just need to set priority to 0\n";
                    if ($::UPLOAD_ACTIVATE_STREAM) {
                         $status_info{RFLASH_SET_PRIORITY_REQUEST}{init_url} =
                             $::SOFTWARE_URL . "/$update_ids{$firm_version}/attr/Priority";   
                    }
                    $next_status{ $node_info{$node}{cur_status} } = "RFLASH_SET_PRIORITY_REQUEST";
                }
            } elsif ($activation_state{$firm_version} =~ /Software.Activation.Activations.Activating/) {
                my $activating_progress_msg = "Activating $firm_msg...  $progress_state{$firm_version}\%";
                if ($::VERBOSE) {
                    xCAT::SvrUtils::sendmsg("$activating_progress_msg", $callback, $node);
                }
                print RFLASH_LOG_FILE_HANDLE "$activating_progress_msg\n";
                close (RFLASH_LOG_FILE_HANDLE);
                # Activation still going, sleep for a bit, then print the progress value
                # Set next state to come back here to chect the activation status again.
                retry_after($node, "RFLASH_UPDATE_CHECK_STATE_REQUEST", 15);
                return;
            }
        }
        if ($update_res) {
            close (RFLASH_LOG_FILE_HANDLE);
            $wait_node_num--;
            return;
        }
    }

    if ($node_info{$node}{cur_status} eq "RFLASH_UPDATE_CHECK_ID_RESPONSE") {
        my $activation_state;
        my $progress_state;
        my $priority_state;
        my $found_match = 0;
        my $found_pnor_match = 0;
        my $debugmsg;

        if ($xcatdebugmode) {
            $debugmsg = "CHECK_ID_RESPONSE: Looking for software ID: $::UPLOAD_FILE_VERSION $::UPLOAD_PNOR_VERSION...";
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

                    # If we have a saved expected hash ID, compare it to the one just found 
                    if ($::UPLOAD_FILE_HASH_ID && ($::UPLOAD_FILE_HASH_ID ne $update_id)) {
                        xCAT::SvrUtils::sendmsg([1,"Firmware uploaded but activation cancelled due to hash ID mismatch. $update_id does not match expected $::UPLOAD_FILE_HASH_ID. Verify BMC firmware is at the latest level."], $callback, $node);
                        $wait_node_num--;
                        return; # Stop processing for this node, do not activate. Firmware shold be left in "Ready" state.
                    }
                    # Set the image id for the activation request
                    $status_info{RFLASH_UPDATE_ACTIVATE_REQUEST}{init_url} =
                       $::SOFTWARE_URL . "/$update_id/attr/RequestedActivation";
                    $status_info{RFLASH_UPDATE_CHECK_STATE_REQUEST}{init_url} =
                       $::SOFTWARE_URL . "/enumerate";
                    $status_info{RFLASH_SET_PRIORITY_REQUEST}{init_url} =
                       $::SOFTWARE_URL . "/$update_id/attr/Priority";

                    my $upload_success_msg = "Firmware upload successful. Attempting to activate firmware: $::UPLOAD_FILE_VERSION (ID: $update_id)";
                    xCAT::SvrUtils::sendmsg("$upload_success_msg", $callback, $node);
                    print RFLASH_LOG_FILE_HANDLE "$upload_success_msg\n";
                } elsif ($update_version eq $::UPLOAD_PNOR_VERSION) {
                    $found_pnor_match = 1;
                    if ($::UPLOAD_PNOR_HASH_ID && ($::UPLOAD_PNOR_HASH_ID ne $update_id)) {
                        xCAT::SvrUtils::sendmsg([1,"Firmware uploaded but activation cancelled due to hash ID mismatch. $update_id does not match expected $::UPLOAD_PNOR_HASH_ID. Verify BMC firmware is at the latest level."], $callback, $node);
                        $wait_node_num--;
                        return;
                    }
                    $status_info{RFLASH_UPDATE_HOST_ACTIVATE_REQUEST}{init_url} =
                       $::SOFTWARE_URL . "/$update_id/attr/RequestedActivation";
                    $status_info{RFLASH_UPDATE_CHECK_STATE_REQUEST}{init_url} =
                       $::SOFTWARE_URL . "/enumerate";
                    $status_info{RFLASH_SET_PRIORITY_REQUEST}{init_url} =
                       $::SOFTWARE_URL . "/$update_id/attr/Priority";
                    my $upload_success_msg = "Firmware upload successful. Attempting to activate firmware: $::UPLOAD_PNOR_VERSION (ID: $update_id)";
                    xCAT::SvrUtils::sendmsg("$upload_success_msg", $callback, $node);
                    print RFLASH_LOG_FILE_HANDLE "$upload_success_msg\n";
                }

            }
        }
        if ($::UPLOAD_ACTIVATE_STREAM and (!$found_match or !$found_pnor_match) or !$found_match) {
            if (!exists($node_info{$node}{upload_wait_attemp})) {
                $node_info{$node}{upload_wait_attemp} = $::UPLOAD_WAIT_ATTEMPT;
            }
            my $upload_file_version = "";
            if (!$found_match) {
                $upload_file_version = $::UPLOAD_FILE_VERSION;
            } else {
                $upload_file_version = $::UPLOAD_PNOR_VERSION;
            }
            if($node_info{$node}{upload_wait_attemp} > 0) {
                $node_info{$node}{upload_wait_attemp} --;
                my $retry_msg = "Could not find ID for firmware $upload_file_version to activate, waiting $::UPLOAD_WAIT_INTERVAL seconds and retry...";
                if ($::VERBOSE) {
                    xCAT::SvrUtils::sendmsg("$retry_msg", $callback, $node);
                }
                print RFLASH_LOG_FILE_HANDLE "$retry_msg\n";
                close (RFLASH_LOG_FILE_HANDLE);
                retry_after($node, "RFLASH_UPDATE_CHECK_ID_REQUEST", $::UPLOAD_WAIT_INTERVAL);
                return;
            } else {
                my $no_firmware_msg = "Could not find firmware $upload_file_version after waiting $::UPLOAD_WAIT_TOTALTIME seconds.";
                xCAT::SvrUtils::sendmsg([1,"$no_firmware_msg"], $callback, $node);
                print RFLASH_LOG_FILE_HANDLE "$no_firmware_msg\n";
                close (RFLASH_LOG_FILE_HANDLE);
                $node_info{$node}{rst} = "$no_firmware_msg";
                $wait_node_num--;
                return;
            }
        }
    }

    if ($node_info{$node}{cur_status} eq "RFLASH_DELETE_IMAGE_RESPONSE") {
        xCAT::SvrUtils::sendmsg("Firmware removed", $callback, $node);
    }

    close (RFLASH_LOG_FILE_HANDLE);

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
    my %curl_upload_cmds;
    # curl commands
    my $curl_login_cmd  = "curl -c $cjar_id -k -H 'Content-Type: application/json' -X POST $request_url/login -d '" . $content_login . "'";
    my $curl_logout_cmd = "curl -b $cjar_id -k -H 'Content-Type: application/json' -X POST $request_url/logout -d '" . $content_logout . "'";

    if (%fw_tar_files) {
        foreach my $key (keys %fw_tar_files) {
            my $curl_upload_cmd = "curl -b $cjar_id -k -H 'Content-Type: application/octet-stream' -X PUT -T " . $key . " $request_url/upload/image/";
            $curl_upload_cmds{$key}=$curl_upload_cmd;
        }
    }

    my $rflash_log_file = xCAT::Utils->full_path($node.".log", $::XCAT_LOG_RFLASH_DIR);
    open (RFLASH_LOG_FILE_HANDLE, ">> $rflash_log_file");

    # Try to login
    my $curl_login_result = `$curl_login_cmd -s`;
    my $h;
    if (!$curl_login_result) {
        my $curl_error = "Did not receive response from OpenBMC after running command '$curl_login_cmd'";
        xCAT::SvrUtils::sendmsg([1, "$curl_error"], $callback, $node);
        print RFLASH_LOG_FILE_HANDLE "$curl_error\n";
        $node_info{$node}{rst} = "$curl_error"; 
        return 1;
    } 
    eval { $h = from_json($curl_login_result) }; # convert command output to hash
    if ($@) {
        my $curl_error = "Received wrong format response for command '$curl_login_cmd': $curl_login_result";
        xCAT::SvrUtils::sendmsg([1, "$curl_error"], $callback, $node);
        print RFLASH_LOG_FILE_HANDLE "$curl_error\n";
        $node_info{$node}{rst} = "$curl_error";
        return 1;
    }
    if ($h->{message} eq $::RESPONSE_OK) {
        if(%curl_upload_cmds){
            while((my $file,my $version)=each(%fw_tar_files)){
                my $uploading_msg = "Uploading $file ...";
                my $upload_cmd = $curl_upload_cmds{$file};
                # Login successfull, upload the file
                if ($::VERBOSE) {
                    xCAT::SvrUtils::sendmsg("$uploading_msg", $callback, $node);
                }
                print RFLASH_LOG_FILE_HANDLE "$uploading_msg\n";

                if ($xcatdebugmode) {
                    my $debugmsg = "RFLASH_FILE_UPLOAD_RESPONSE: CMD: $upload_cmd";
                    process_debug_info($node, $debugmsg);
                }    
                my $curl_upload_result = `$upload_cmd`;
                if (!$curl_upload_result) {
                    my $curl_error = "Did not receive response from OpenBMC after running command '$upload_cmd'";
                    xCAT::SvrUtils::sendmsg([1, "$curl_error"], $callback, $node);
                    print RFLASH_LOG_FILE_HANDLE "$curl_error\n";
                    $node_info{$node}{rst} = "$curl_error";
                    return 1;
                }
                eval { $h = from_json($curl_upload_result) }; # convert command output to hash
                if ($@) {
                    my $curl_error = "Received wrong format response from command '$upload_cmd': $curl_upload_result";
                    xCAT::SvrUtils::sendmsg([1, "$curl_error"], $callback, $node);
                    print RFLASH_LOG_FILE_HANDLE "$curl_error\n";
                    $node_info{$node}{rst} = "$curl_error";
                    return 1;
                }
                if ($h->{message} eq $::RESPONSE_OK) {
                    # Upload successful, display message
                    my $upload_success_msg = "Firmware upload successful. Use -l option to list.";
                    unless ($::UPLOAD_AND_ACTIVATE or $::UPLOAD_ACTIVATE_STREAM) {
                        xCAT::SvrUtils::sendmsg("$upload_success_msg", $callback, $node);
                    }
                    print RFLASH_LOG_FILE_HANDLE "$upload_success_msg\n";
                    # Try to logoff, no need to check result, as there is nothing else to do if failure
                } else {
                    my $upload_fail_msg = "Failed to upload update file $file :" . $h->{message} . " - " . $h->{data}->{description};
                    xCAT::SvrUtils::sendmsg("$upload_fail_msg", $callback, $node);
                    print RFLASH_LOG_FILE_HANDLE "$upload_fail_msg\n";
                    close (RFLASH_LOG_FILE_HANDLE);
                    $node_info{$node}{rst} = "$upload_fail_msg";
                    return 1;
                }
            }
        }
        # Try to logoff, no need to check result, as there is nothing else to do if failure
        my $curl_logout_result = `$curl_logout_cmd -s`;
    }
    else {
        my $unable_login_msg = "Unable to login :" . $h->{message} . " - " . $h->{data}->{description};
        xCAT::SvrUtils::sendmsg("$unable_login_msg", $callback, $node);
        print RFLASH_LOG_FILE_HANDLE "$unable_login_msg\n";
        close (RFLASH_LOG_FILE_HANDLE);
        $node_info{$node}{rst} = "$unable_login_msg";
        return 1;
    }

    close (RFLASH_LOG_FILE_HANDLE);
    return 0;
}

#-------------------------------------------------------

=head3  is_valid_config_api

  Verify passed in subcomaand is defined in the api_config_info
  Input:
        $subcommand: subcommand to verify
        $callback: callback for message display

  Output:
        returns index into the hash of the $subcommand
        returns -1 if no match

=cut

#-------------------------------------------------------
sub is_valid_config_api {
    my ($subcommand, $callback) = @_;

    my $subcommand_key = $subcommand;
    my $subcommand_value;
    if ($subcommand =~ /^(\w+)=(.*)/) {
        $subcommand_key = $1;
        $subcommand_value = $2;
    }
    foreach my $config_subcommand (keys %api_config_info) {
        foreach my $config_attribute (keys %{ $api_config_info{$config_subcommand} }) {
            if ($subcommand_key eq $api_config_info{$config_subcommand}{subcommand}) {
                return $config_subcommand;
            }
        }
    }
    return -1;
}
1;
