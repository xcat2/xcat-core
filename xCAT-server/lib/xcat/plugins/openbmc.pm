#!/usr/bin/perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head1
  xCAT plugin package to handle openbmc 

   Supported command:
       getopenbmccons

=cut

#-------------------------------------------------------
package xCAT_plugin::openbmc;

BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : -d '/opt/xcat' ? '/opt/xcat' : '/usr';
}
use lib "$::XCATROOT/lib/perl";
use strict;
use warnings "all";

use HTTP::Async;
use HTTP::Cookies;
use xCAT::OPENBMC;
use xCAT::Utils;
use xCAT::Table;
use xCAT::Usage;
use xCAT::SvrUtils;
use File::Basename;
use Data::Dumper;
use JSON;
use Getopt::Long;
use File::Path;
use Term::ANSIColor;
use Time::Local;
use strict;
use Class::Struct;
use XML::Simple;
use Storable qw(dclone);
use SNMP;
use xCAT::PasswordUtils;

$::OPENBMC_DEVEL = $ENV{'OPENBMC_DEVEL'};

my $VERBOSE = 0;
my %allerrornodes = ();
my $callback;

#-------------------------------------------------------

=head3  handled_commands

  Return list of commands handled by this plugin

=cut

#-------------------------------------------------------
sub handled_commands {
    return {
        rpower => 'nodehm:mgt',
        rinv   => 'nodehm:mgt',
        getopenbmccons => 'nodehm:cons',
    };
}

my $pre_url = "/org/openbmc";
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

    RPOWER_ON_REQUEST  => {
        method         => "PUT",
        init_url       => "/xyz/openbmc_project/state/host0/attr/RequestedHostTransition",
        data           => "xyz.openbmc_project.State.Host.Transition.On",
    },
    RPOWER_ON_RESPONSE => {
        process        => \&rpower_response,
    },
    RPOWER_OFF_REQUEST  => {
        method         => "PUT",
        init_url       => "/xyz/openbmc_project/state/host0/attr/RequestedHostTransition",
        data           => "xyz.openbmc_project.State.Host.Transition.Off",
    },
    RPOWER_OFF_RESPONSE => {
        process        => \&rpower_response,
    },
    RPOWER_RESET_REQUEST  => {
        method         => "PUT",
        init_url       => "/xyz/openbmc_project/state/host0/attr/RequestedHostTransition",
        data           => "xyz.openbmc_project.State.Host.Transition.Reboot",
    },
    RPOWER_RESET_RESPONSE => {
        process        => \&rpower_response,
    },
    RPOWER_STATUS_REQUEST  => {
        method         => "GET",
        init_url       => "/xyz/openbmc_project/state/host0",
    },
    RPOWER_STATUS_RESPONSE => {
        process        => \&rpower_response,
    },

    RINV_REQUEST => {
        method         => "GET",
        init_url       => "$pre_url/inventory/enumerate",
    },
    RINV_RESPONSE => {
        process        => \&rinv_response,
    },
);


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
          back_urls  => (),
      },
  );

  'cur_url', 'method', 'back_urls' used for path has a trailing-slash

=cut

#-----------------------------
my %node_info = ();

my %next_status = ();

my %handle_id_node = ();

my $wait_node_num;

my $async;

my $cookie_jar;

my $callback;

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

    my $parse_result = parse_args($command, $extrargs);
    if (ref($parse_result) eq 'ARRAY') {
        $callback->({ error => $parse_result->[1], errorcode => $parse_result->[0] });
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

    parse_node_info($noderange);
    parse_command_status($command);

    $cookie_jar = HTTP::Cookies->new({});
    $async = HTTP::Async->new(
        cookie_jar => $cookie_jar,
        ssl_options => {
            SSL_verify_mode => 0,
        },
    );    

    my $bmcip;
    my $login_url;
    my $handle_id;
    my $content;
    $wait_node_num = keys %node_info;

    foreach my $node (keys %node_info) {
        $bmcip = $node_info{$node}{bmc};
        $login_url = "https://$bmcip/login";
        $content = '{"data": [ "' . $node_info{$node}{username} .'", "' . $node_info{$node}{password} . '" ] }';
        $handle_id = xCAT::OPENBMC->new($async, $login_url, $content); 
        $handle_id_node{$handle_id} = $node;
        $node_info{$node}{cur_status} = $next_status{ $node_info{$node}{cur_status} };
        print "$node: DEBUG POST $login_url -d $content\n";
    }  

    while (1) { 
        last unless ($wait_node_num);
        while (my ($response, $handle_id) = $async->wait_for_next_response) {
            deal_with_response($handle_id, $response);
        }
    } 


    my $ipmitab     = xCAT::Table->new('ipmi');
    my $ipmihash = $ipmitab->getNodesAttribs($noderange, [ 'bmc', 'username', 'password' ]);
    my $authdata = xCAT::PasswordUtils::getIPMIAuth(noderange => $noderange, ipmihash => $ipmihash);

    foreach (@$noderange) {
        my $node     = $_;
        my $nodeip = $node;
        my $nodeuser = $authdata->{$node}->{username};
        my $nodepass = $authdata->{$node}->{password};
        my $nodeip   = $node;
        my $ent;
        if (defined($ipmitab)) {
            $ent = $ipmihash->{$node}->[0];
            if (ref($ent) and defined $ent->{bmc}) { $nodeip = $ent->{bmc}; }
        }
        push @donargs, [ $node,$nodeip,$nodeuser, $nodepass];
        my $output = "openbmc, get $username and $password from ipmi table for $nodeip";
        xCAT::SvrUtils::sendmsg($output, $callback, $node, %allerrornodes);
    }


    if ($request->{command}->[0] eq "getopenbmccons") {
        foreach (@donargs) {
            getopenbmccons($_, $callback);
        }
        return;
    }
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

    my $check = unsupported($callback);
    if (ref($check) eq "ARRAY") {
        return $check;
    }

    if (!defined($extrargs)) {
        return ([ 1, "No option specified for rpower" ]);
    }

    if (scalar(@ARGV) > 1) {
        return ([ 1, "Only one option is supportted at the same time" ]);
    }

    my $subcommand = $ARGV[0];
    if ($command eq "rpower") {
        if ($subcommand ne "on" and $subcommand ne "off" and $subcommand ne "reset" and $subcommand ne "status" and $subcommand ne "state" and $subcommand ne "stat" and $subcommand ne "boot") {
            return ([ 1, "$subcommand is not supported for rpower" ]);
        }
    }

    if ($command eq "rinv") {
        if ($subcommand ne "cpu" and $subcommand ne "dimm" and $subcommand ne "bios" and $subcommand ne "all") {
            return ([ 1, "Only 'cpu','dimm', 'bios','all' are supportted currently" ]);
        }
    }

    return;
}


sub unsupported {
    my $callback = shift;
    if ($::OPENBMC_DEVEL ne "YES") {
        return ([ 1, "This function is currently not supported" ]);
    } else {
        xCAT::SvrUtils::sendmsg("Warning: Currently running development code, use at your own risk\n",  $callback);
        return;
    }
}

#-------------------------------------------------------

=head3  parse_command_status

  Parse the command to init status machine

=cut

#-------------------------------------------------------
sub parse_command_status {
    my $command  = shift;

    $next_status{LOGIN_REQUEST} = "LOGIN_RESPONSE";

    if ($command eq "rpower") {
        my $subcommand = $ARGV[0];

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
        my $subcommand = $ARGV[0];

        if ($subcommand eq "cpu" or $subcommand eq "dimm" or $subcommand eq "bios" or $subcommand eq "all") {
            $next_status{LOGIN_RESPONSE} = "RINV_REQUEST";
            $next_status{RINV_REQUEST} = "RINV_RESPONSE";
            $status_info{RINV_RESPONSE}{argv} = "$subcommand";
        }
    }

    print Dumper(\%next_status) . "\n";
}

#-------------------------------------------------------

=head3  parse_node_info

  Parse the node information: bmc, username, password

=cut

#-------------------------------------------------------
sub parse_node_info {
    my $noderange = shift;

    my $table = xCAT::Table->new('openbmc');
    my $tablehash = $table->getNodesAttribs(\@$noderange, ['bmc', 'username', 'password']);

    foreach my $node (@$noderange) {
        if (defined($tablehash->{$node}->[0])) {
            if ($tablehash->{$node}->[0]->{'bmc'}) {
                $node_info{$node}{bmc} = $tablehash->{$node}->[0]->{'bmc'};
            } else {
                xCAT::SvrUtils::sendmsg("Unable to get attribute bmc", $callback, $node);
                next;
            }

            if ($tablehash->{$node}->[0]->{'username'}) {
                $node_info{$node}{username} = $tablehash->{$node}->[0]->{'username'};
            } else {
                xCAT::SvrUtils::sendmsg("Unable to get attribute username", $callback, $node);
                delete $node_info{$node};
                next;
            }

            if ($tablehash->{$node}->[0]->{'password'}) {
                $node_info{$node}{password} = $tablehash->{$node}->[0]->{'password'};
            } else {
                xCAT::SvrUtils::sendmsg("Unable to get attribute password", $callback, $node);
                delete $node_info{$node};
                next;
            }

            $node_info{$node}{cur_status} = "LOGIN_REQUEST";
        } else {
            xCAT::SvrUtils::sendmsg("Unable to get information from openbmc table", $callback, $node);
            next;
        }
    }

    print Dumper(\%node_info) ."\n";

    return;
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
    $request_url = "https://" . $node_info{$node}{bmc} . $request_url;

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

    if ($response->status_line ne "200 OK") {
        my $error;
        if ($response->status_line eq "503 Service Unavailable") {
            $error = "Service Unavailable";
        } else {
            my $response_info = decode_json $response->content;
            if ($response->status_line eq "500 Internal Server Error") {
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

    print "$node: DEBUG " . lc ($node_info{$node}{cur_status}) . " " . $response->status_line . "\n";

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

    my $response_info = decode_json $response->content;

    if ($node_info{$node}{cur_status} eq "RPOWER_ON_RESPONSE") {
        if ($response_info->{'message'} eq "200 OK") {
            xCAT::SvrUtils::sendmsg("on", $callback, $node);
        }
    } 

    if ($node_info{$node}{cur_status} eq "RPOWER_OFF_RESPONSE") {
        if ($response_info->{'message'} eq "200 OK") {
            xCAT::SvrUtils::sendmsg("off", $callback, $node);
        }
    }

    if ($node_info{$node}{cur_status} eq "RPOWER_RESET_RESPONSE") {
        if ($response_info->{'message'} eq "200 OK") {
            xCAT::SvrUtils::sendmsg("reset", $callback, $node);
        }
    }

    if ($node_info{$node}{cur_status} eq "RPOWER_STATUS_RESPONSE") { 
        xCAT::SvrUtils::sendmsg($response_info->{'data'}->{CurrentHostState}, $callback, $node);
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

    my $grep_string = $status_info{RINV_RESPONSE}{argv};
    my $src;
    my $content_info;

    foreach my $key_url (keys %{$response_info->{data}}) {
        if ($grep_string eq "all" or $key_url =~ /\/$grep_string/) {
            if ($key_url =~ /\/(cpu\d*)\/(\w+)/) {
                $src = "$1 $2";
            } else {
                $src = basename $key_url;
            }

            my %content = %{ ${ $response_info->{data} }{$key_url} };
            foreach my $key (keys %content) {
                $content_info = uc ($src) . " " . $key . " : " . $content{$key};
                xCAT::SvrUtils::sendmsg("$content_info", $callback, $node);
            }
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


sub getopenbmccons {
    my $argr = shift;

    #$argr is [$node,$nodeuser,$nodepass];
    my $callback = shift;

    my $rsp;
    my $node=$argr->[0];
    my $output = "openbmc, getopenbmccoms";
    xCAT::SvrUtils::sendmsg($output, $callback, $argr->[0], %allerrornodes);

    $rsp = { node => [ { name => [ $argr->[0] ] } ] };
    $rsp->{node}->[0]->{nodeip}->[0]    = $argr->[1];
    $rsp->{node}->[0]->{username}->[0]    = $argr->[2];
    $rsp->{node}->[0]->{passwd}->[0]  = $argr->[3];
    $callback->($rsp);
    return $rsp;
}

1;
