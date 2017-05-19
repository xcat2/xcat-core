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
use Data::Dumper;
use Getopt::Long;
use xCAT::OPENBMC;
use xCAT::Utils;
use xCAT::Table;
use xCAT::Usage;
use xCAT::SvrUtils;
use xCAT::GlobalDef;
use xCAT_monitoring::monitorctrl;

sub unsupported {
    my $callback = shift;
    if (defined($::OPENBMC_DEVEL) && ($::OPENBMC_DEVEL eq "YES")) {
        xCAT::SvrUtils::sendmsg("Warning: Currently running development code, use at your own risk.  Unset XCAT_OPENBMC_DEVEL to disable.",  $callback);
        return;
    } else {
        return ([ 1, "This openbmc related function is unsupported and disabled. To bypass, run the following: \n\texport XCAT_OPENBMC_DEVEL=YES" ]);
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

    REVENTLOG_REQUEST => {
        method         => "GET",
        init_url       => "$openbmc_project_url/logging/enumerate",
    },
    REVENTLOG_RESPONSE => {
        process        => \&reventlog_response,
    },
    REVENTLOG_CLEAR_REQUEST => {
        method         => "POST",
        init_url       => "$openbmc_url/records/events/action/clear",
        data           => "",
    },
    REVENTLOG_CLEAR_RESPONSE => {
        process        => \&reventlog_response,
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
        init_url       => "$openbmc_project_url/state/host0/attr/RequestedHostTransition",
        data           => "xyz.openbmc_project.State.Host.Transition.Off",
    },
    RPOWER_OFF_RESPONSE => {
        process        => \&rpower_response,
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
        init_url       => "$openbmc_project_url/state/host0",
    },
    RPOWER_STATUS_RESPONSE => {
        process        => \&rpower_response,
    },

    RSETBOOT_SET_REQUEST => {
        method         => "PUT",
        init_url       => "",
    },
    RSETBOOT_SET_RESPONSE => {
        process        => \&rsetboot_response,
    },
    RSETBOOT_STATUS_REQUEST  => {
        method         => "GET",
        init_url       => "",
    },
    RSETBOOT_STATUS_RESPONSE => {
        process        => \&rsetboot_response,
    },

    RSPCONFIG_GET_REQUEST => {
        method         => "GET",
        init_url       => "",
    },
    RSPCONFIG_GET_RESPONSE => {
        process        => \&rspconfig_response,
    },
    RSPCONFIG_SET_REQUEST => {
        method         => "POST",
        init_url       => "",
        data           => "",
    },
    RSPCONFIG_SET_RESPONSE => {
        process        => \&rspconfig_response,
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
    my $command   = $request->{command}->[0];
    my $noderange = $request->{node};

    my $check = parse_node_info($noderange);
    my $rst = parse_command_status($command);
    return if ($rst);

    if ($request->{command}->[0] ne "getopenbmccons") {
        $cookie_jar = HTTP::Cookies->new({});
        $async = HTTP::Async->new(
            cookie_jar => $cookie_jar,
            timeout => 10,
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
            print "$node: DEBUG POST $login_url -d $content\n";
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

    $callback->({ errorcode => $check }) if ($check);
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
 
    if (!defined($extrargs) and $command =~ /rpower|rsetboot|rspconfig/) {
        return ([ 1, "No option specified for $command" ]);
    }

    if (scalar(@ARGV) > 1 and ($command =~ /rpower|rinv|rsetboot|rvitals/)) {
        return ([ 1, "Only one option is supported at the same time" ]);
    }

    my $subcommand = $ARGV[0];
    if ($command eq "rpower") {
        #
        # disable function until fully tested
        #
        $check = unsupported($callback); if (ref($check) eq "ARRAY") { return $check; }
        unless ($subcommand =~ /^on$|^off$|^reset$|^boot$|^status$|^stat$|^state$/) {
            return ([ 1, "Unsupported command: $command $subcommand" ]);
        }
    } elsif ($command eq "rinv") {
        #
        # disable function until fully tested
        #
        $check = unsupported($callback); if (ref($check) eq "ARRAY") { return $check; }
        $subcommand = "all" if (!defined($ARGV[0]));
        unless ($subcommand =~ /^cpu$|^dimm$|^model$|^serial$|^firm$|^mac$|^vpd$|^mprom$|^deviceid$|^guid$|^uuid$|^all$/) {
            return ([ 1, "Unsupported command: $command $subcommand" ]);
        }
    } elsif ($command eq "getopenbmccons") {
        #command for openbmc rcons
    } elsif ($command eq "rsetboot") {
        #
        # disable function until fully tested
        #
        $check = unsupported($callback); if (ref($check) eq "ARRAY") { return $check; }
        unless ($subcommand =~ /^net$|^hd$|^cd$|^def$|^default$|^stat$/) {
            return ([ 1, "Unsupported command: $command $subcommand" ]);
        }
    } elsif ($command eq "reventlog") {
        #
        # disable function until fully tested
        #
        $check = unsupported($callback); if (ref($check) eq "ARRAY") { return $check; }
        $subcommand = "all" if (!defined($ARGV[0]));
        unless ($subcommand =~ /^\d$|^\d+$|^all$|^clear$/) {
            return ([ 1, "Unsupported command: $command $subcommand" ]);
        }
    } elsif ($command eq "rspconfig") {
        #
        # disable function until fully tested
        #
        $check = unsupported($callback); if (ref($check) eq "ARRAY") { return $check; }
        my $setorget;
        foreach $subcommand (@ARGV) {
            if ($subcommand =~ /^(\w+)=(.*)/) {
                return ([ 1, "Can not configure and display nodes' value at the same time" ]) if ($setorget and $setorget eq "get");
                my $key = $1;
                my $value = $2;
                return ([ 1, "Unsupported command: $command $key" ]) unless ($key =~ /^ip$|^netmask$|^gateway$|^vlan$/);

                my $nodes_num = @$noderange;
                return ([ 1, "Invalid parameter for option $key" ]) unless ($value);
                return ([ 1, "Invalid parameter for option $key: $value" ]) unless (xCAT::NetworkUtils->isIpaddr($value));
                if ($key eq "ip") {
                    return ([ 1, "Can not configure more than 1 nodes' ip at the same time" ]) if ($nodes_num >= 2);
                }
                $setorget = "set";
            } elsif ($subcommand =~ /^ip$|^netmask$|^gateway$|^vlan$/) {
                return ([ 1, "Can not configure and display nodes' value at the same time" ]) if ($setorget and $setorget eq "set");
                $setorget = "get";
            } else {
                return ([ 1, "Unsupported command: $command $subcommand" ]);
            }
        }  
    } elsif ($command eq "rvitals") {
        $check = unsupported($callback); if (ref($check) eq "ARRAY") { return $check; }
        $subcommand = "all" if (!defined($ARGV[0]));
        unless ($subcommand =~ /^temp$|^voltage$|^wattage$|^fanspeed$|^power$|^leds$|^all$/) {
            return ([ 1, "Unsupported command: $command $subcommand" ]);
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
    my $command  = shift;
    my $subcommand;

    $next_status{LOGIN_REQUEST} = "LOGIN_RESPONSE";

    if ($command eq "rpower") {
        $subcommand = $ARGV[0];

        if ($subcommand eq "on") {
            $next_status{LOGIN_RESPONSE} = "RPOWER_ON_REQUEST";
            $next_status{RPOWER_ON_REQUEST} = "RPOWER_ON_RESPONSE";
        } elsif ($subcommand eq "off") {
            $next_status{LOGIN_RESPONSE} = "RPOWER_OFF_REQUEST";
            $next_status{RPOWER_OFF_REQUEST} = "RPOWER_OFF_RESPONSE";
        } elsif ($subcommand eq "reset") {
            $next_status{LOGIN_RESPONSE} = "RPOWER_RESET_REQUEST";
            $next_status{RPOWER_RESET_REQUEST} = "RPOWER_RESET_RESPONSE";
        } elsif ($subcommand eq "status" or $subcommand eq "state" or $subcommand eq "stat") {
            $next_status{LOGIN_RESPONSE} = "RPOWER_STATUS_REQUEST";
            $next_status{RPOWER_STATUS_REQUEST} = "RPOWER_STATUS_RESPONSE";
        } elsif ($subcommand eq "boot") {
            $next_status{LOGIN_RESPONSE} = "RPOWER_STATUS_REQUEST";
            $next_status{RPOWER_STATUS_REQUEST} = "RPOWER_STATUS_RESPONSE";
            $next_status{RPOWER_STATUS_RESPONSE}{OFF} = "RPOWER_ON_REQUEST";
            $next_status{RPOWER_ON_REQUEST} = "RPOWER_ON_RESPONSE";
            $next_status{RPOWER_STATUS_RESPONSE}{ON} = "RPOWER_RESET_REQUEST";
            $next_status{RPOWER_RESET_REQUEST} = "RPOWER_RESET_RESPONSE";
        }
    } 

    if ($command eq "rinv") {
        if (defined($ARGV[0])) {
            $subcommand = $ARGV[0];
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
        my $persistent = 0;
        unless (GetOptions("p" => \$persistent,)) {
            xCAT::SvrUtils::sendmsg("Error parsing arguments.", $callback);
            return 1;
        }

        $subcommand = $ARGV[0];
        if ($subcommand =~ /^hd$|^net$|^cd$|^default$|^def$/) {
            $next_status{LOGIN_RESPONSE} = "RSETBOOT_SET_REQUEST";
            $next_status{RSETBOOT_SET_REQUEST} = "RSETBOOT_SET_RESPONSE";
            # modify $status_info{RSETBOOT_SET_REQUEST}{data}
            $next_status{RSETBOOT_SET_RESPONSE} = "RSETBOOT_STATUS_REQUEST";
            $next_status{RSETBOOT_STATUS_REQUEST} = "RSETBOOT_STATUS_RESPONSE";
        } elsif ($subcommand eq "stat") {
            $next_status{LOGIN_RESPONSE} = "RSETBOOT_STATUS_REQUEST";
            $next_status{RSETBOOT_STATUS_REQUEST} = "RSETBOOT_STATUS_RESPONSE";
        }
        xCAT::SvrUtils::sendmsg("Command $command is not available now!", $callback);
        return 1;
    }

    if ($command eq "reventlog") {
        my $option_s = 0;
        unless (GetOptions("s" => \$option_s,)) {
            xCAT::SvrUtils::sendmsg("Error parsing arguments.", $callback);
            return 1;
        }

        if (defined($ARGV[0])) {
            $subcommand = $ARGV[0];
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
        foreach $subcommand (@ARGV) {
            if ($subcommand =~ /^ip$|^netmask$|^gateway$|^vlan$/) {
                $next_status{LOGIN_RESPONSE} = "RSPCONFIG_GET_REQUEST";
                $next_status{RSPCONFIG_GET_REQUEST} = "RSPCONFIG_GET_RESPONSE";
                push @options, $subcommand;
            } elsif ($subcommand =~ /^(\w+)=(.+)/) {
                my $key   = $1;
                my $value = $2;
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
        $next_status{RSPCONFIG_GET_RESPONSE}{argv} = join(",", @options);
        xCAT::SvrUtils::sendmsg("Command $command is not available now!", $callback);
        return 1;
    }

    if ($command eq "rvitals") {
        if (defined($ARGV[0])) {
            $subcommand = $ARGV[0];
        } else {
            $subcommand = "all";
        }

        $next_status{LOGIN_RESPONSE} = "RVITALS_REQUEST";
        $next_status{RVITALS_REQUEST} = "RVITALS_RESPONSE";
        $status_info{RVITALS_RESPONSE}{argv} = "$subcommand";
    }

    print Dumper(\%next_status) . "\n";
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
                xCAT::SvrUtils::sendmsg("Unable to get attribute bmc", $callback, $node);
                $rst = 1;
                next;
            }

            if ($openbmc_hash->{$node}->[0]->{'username'}) {
                $node_info{$node}{username} = $openbmc_hash->{$node}->[0]->{'username'};
            } elsif ($passwd_hash and $passwd_hash->{username}) {
                $node_info{$node}{username} = $passwd_hash->{username};
            } else {
                xCAT::SvrUtils::sendmsg("Unable to get attribute username", $callback, $node);
                delete $node_info{$node};
                $rst = 1;
                next;
            }

            if ($openbmc_hash->{$node}->[0]->{'password'}) {
                $node_info{$node}{password} = $openbmc_hash->{$node}->[0]->{'password'};
            } elsif ($passwd_hash and $passwd_hash->{password}) {
                $node_info{$node}{password} = $passwd_hash->{password};
            } else {
                xCAT::SvrUtils::sendmsg("Unable to get attribute password", $callback, $node);
                delete $node_info{$node};
                $rst = 1;
                next;
            }

            $node_info{$node}{cur_status} = "LOGIN_REQUEST";
        } else {
            xCAT::SvrUtils::sendmsg("Unable to get information from openbmc table", $callback, $node);
            $rst = 1;
            next;
        }
    }

    print Dumper(\%node_info) ."\n";

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
        $content = '{"data":"' . $status_info{ $node_info{$node}{cur_status} }{data} . '"}';
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

    my $debug_info;
    if ($method eq "GET") {
        $debug_info = "$node: DEBUG $method $request_url";
    } else {
        $debug_info = "$node: DEBUG $method $request_url -d $content";
    }
    print "$debug_info\n";

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

    print "$node: DEBUG " . lc ($node_info{$node}{cur_status}) . " " . $response->status_line . "\n";

    if ($response->status_line ne $::RESPONSE_OK) {
        my $error;
        if ($response->status_line eq $::RESPONSE_SERVICE_UNAVAILABLE) {
            $error = "Service Unavailable";
        } else {
            my $response_info = decode_json $response->content;
            if ($response->status_line eq $::RESPONSE_SERVER_ERROR) {
                $error = $response_info->{'data'}->{'exception'};
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

    foreach my $key (keys %{$response_info->{data}}) {
        # Debug, print out the Current and Transition States     
        print "$node: DEBUG host_states $key=$response_info->{'data'}->{$key}\n";
    }

    if ($node_info{$node}{cur_status} eq "RPOWER_ON_RESPONSE") {
        if ($response_info->{'message'} eq $::RESPONSE_OK) {
            xCAT::SvrUtils::sendmsg("on", $callback, $node);
            $new_status{$::STATUS_POWERING_ON} = [$node];
        }
    } 

    if ($node_info{$node}{cur_status} eq "RPOWER_OFF_RESPONSE") {
        if ($response_info->{'message'} eq $::RESPONSE_OK) {
            xCAT::SvrUtils::sendmsg("off", $callback, $node);
            $new_status{$::STATUS_POWERING_OFF} = [$node];
        }
    }

    if ($node_info{$node}{cur_status} eq "RPOWER_RESET_RESPONSE") {
        if ($response_info->{'message'} eq $::RESPONSE_OK) {
            xCAT::SvrUtils::sendmsg("reset", $callback, $node);
            $new_status{$::STATUS_POWERING_ON} = [$node];
        }
    }

    xCAT_monitoring::monitorctrl::setNodeStatusAttributes(\%new_status, 1) if (%new_status);

    if ($node_info{$node}{cur_status} eq "RPOWER_STATUS_RESPONSE" and !$next_status{ $node_info{$node}{cur_status} }) { 
        if ($response_info->{'data'}->{CurrentHostState} =~ /Off$/) {
            # State is off, but check if it is transitioning
            if ($response_info->{'data'}->{RequestedHostTransition} =~ /On$/) {
                xCAT::SvrUtils::sendmsg("powering-on", $callback, $node);
            }
            else {
                xCAT::SvrUtils::sendmsg("off", $callback, $node);
            }
        } elsif ($response_info->{'data'}->{CurrentHostState} =~ /Quiesced$/) {
            xCAT::SvrUtils::sendmsg("quiesced", $callback, $node);
        } else {
            # State is on, but check if it is transitioning
            if ($response_info->{'data'}->{RequestedHostTransition} =~ /Off$/) {
                xCAT::SvrUtils::sendmsg("powering-off", $callback, $node);
            }
            else {
                xCAT::SvrUtils::sendmsg("on", $callback, $node);
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
            if (defined($content{Version}) and $content{Version}) {
                my $firm_ver = "System Firmware Product Version: " . "$content{Version}";
                xCAT::SvrUtils::sendmsg("$firm_ver", $callback, $node);
                next;
            }
        }

        if (($grep_string eq "vpd" or $grep_string eq "model") and $key_url =~ /\/motherboard$/) {
            my $partnumber = "BOARD Part Number: " . "$content{PartNumber}";
            xCAT::SvrUtils::sendmsg("$partnumber", $callback, $node);
            next if ($grep_string eq "model");
        } 

        if (($grep_string eq "vpd" or $grep_string eq "serial") and $key_url =~ /\/motherboard$/) {
            my $serialnumber = "BOARD Serial Number: " . "$content{SerialNumber}";
            xCAT::SvrUtils::sendmsg("$serialnumber", $callback, $node);
            next if ($grep_string eq "serial");
        } 

        if (($grep_string eq "vpd" or $grep_string eq "mprom") and $key_url =~ /\/motherboard$/) {
            xCAT::SvrUtils::sendmsg("No mprom information is available", $callback, $node);
            next if ($grep_string eq "mprom");
        } 

        if (($grep_string eq "vpd" or $grep_string eq "deviceid") and $key_url =~ /\/motherboard$/) {
            xCAT::SvrUtils::sendmsg("No deviceid information is available", $callback, $node);
            next if ($grep_string eq "deviceid");
        } 

        if ($grep_string eq "uuid") {
            xCAT::SvrUtils::sendmsg("No uuid information is available", $callback, $node);
            last;
        } 

        if ($grep_string eq "guid") {
            xCAT::SvrUtils::sendmsg("No guid information is available", $callback, $node);
            last;
        } 

        if ($grep_string eq "mac" and $key_url =~ /\/ethernet/) {
            my $macaddress = "MAC: " . $content{MACAddress};
            xCAT::SvrUtils::sendmsg("$macaddress", $callback, $node);
            next;
        } 

        if ($grep_string eq "all" or $key_url =~ /\/$grep_string/) {
            if ($key_url =~ /\/(cpu\d*)\/(\w+)/) {
                $src = "$1 $2";
            } else {
                $src = basename $key_url;
            }

            foreach my $key (keys %content) {
                $content_info = uc ($src) . " " . $key . " : " . $content{$key};
                push (@sorted_output, $node . ": ". $content_info); #Save output in array
            }
        }
     }
     # If sorted array has any contents, sort it and print it
     if (scalar @sorted_output > 0) {
         @sorted_output = sort @sorted_output; #Sort all output
         my $result = join "\n", @sorted_output; #Join into a single string for easier display
         xCAT::SvrUtils::sendmsg("$result", $callback);
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

    if ($node_info{$node}{cur_status} eq "RSETBOOT_GET_RESPONSE") {
        xCAT::SvrUtils::sendmsg("Hard Drive", $callback, $node); #if response data is hd
        xCAT::SvrUtils::sendmsg("Network", $callback, $node); #if response data is net
        xCAT::SvrUtils::sendmsg("CD/DVD", $callback, $node); #if response data is net
        xCAT::SvrUtils::sendmsg("boot override inactive", $callback, $node); #if response data is def
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
        my %output_s = () if ($option_s);
        my $entry_num = 0;
        $entry_string = "all" if ($entry_string eq "0");
        $entry_num = 0 + $entry_string if ($entry_string ne "all");

        foreach my $key_url (keys %{$response_info->{data}}) {
            my %content = %{ ${ $response_info->{data} }{$key_url} };
            my $id_num = 0 + $content{Id} if ($content{Id});
            if (($entry_string eq "all" or ($id_num and ($entry_num ge $id_num))) and $content{Message}) {
                my $content_info = $content{Timestamp} . " " . $content{Message}; 
                if ($option_s) {
                    $output_s{$id_num} = $content_info;
                    $entry_num = $id_num if ($entry_num < $id_num);
                } else {
                    xCAT::SvrUtils::sendmsg("$content_info", $callback, $node);
                }
            }
        }

        if (%output_s) {
            for (my $key = $entry_num; $key >= 1; $key--) {
                xCAT::SvrUtils::sendmsg("$output_s{$key}", $callback, $node) if ($output_s{$key});
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
        my $grep_string = $status_info{RSPCONFIG_GET_RESPONSE}{argv};
        my $data;
        my @output;
        if ($grep_string =~ "ip") {
            $data = ""; # got data from response
            push @output, "BMC IP: $data";
        } 
        if ($grep_string =~ "netmask") {
            $data = ""; # got data from response
            push @output, "BMC Netmask: $data"; 
        } 
        if ($grep_string =~ "gateway") {
            $data = ""; # got data from response
            push @output, "BMC Gateway: $data";
        }
        if ($grep_string =~ "vlan") {
            $data = ""; # got data from response
            push @output, "BMC VLAN ID enabled: $data";
        }

        xCAT::SvrUtils::sendmsg("$_", $callback, $node) foreach (@output);
    }

    if ($node_info{$node}{cur_status} eq "RSPCONFIG_SET_RESPONSE" and $response_info->{'message'} eq $::RESPONSE_OK) {
        if ($status_info{RSPCONFIG_SET_RESPONSE}{ip}) {
            $node_info{$node}{bmc} = $status_info{RSPCONFIG_SET_RESPONSE}{ip};
            print "$node: DEBUG BMC IP is $node_info{$node}{bmc}\n";
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
    my $sensor_value;
    
    print "$node DEBUG Processing command: rvitals $grep_string \n";
    print Dumper(%{$response_info->{data}}) . "\n";

    foreach my $key_url (keys %{$response_info->{data}}) {
        my %content = %{ ${ $response_info->{data} }{$key_url} };
        print Dumper(%content) . "\n";
        # $key_url is "/xyz/openbmc_project/sensors/xxx/yyy
        # For now display xxx/yyy as a label
        my ($junk, $label) = split("/sensors/", $key_url);
        $sensor_value = $label . " " . $content{Value};
        xCAT::SvrUtils::sendmsg("$sensor_value", $callback, $node);
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
