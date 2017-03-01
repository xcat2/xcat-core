#!/usr/bin/perl
## IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT_plugin::openbmc;

BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
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

#-------------------------------------------------------

=head3  handled_commands

  Return list of commands handled by this plugin

=cut

#-------------------------------------------------------
sub handled_commands {
    return {
        rpower => 'nodehm:mgt',
        rinv    => 'nodehm:mgt',
    };
}

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
        method         => "POST",
        init_url       => "/power/on",
    },
    RPOWER_ON_RESPONSE => {
        process        => \&rpower_response,
    },
    RPOWER_OFF_REQUEST  => {
        method         => "POST",
        init_url       => "/power/off",
    },
    RPOWER_OFF_RESPONSE => {
        process        => \&rpower_response,
    },
    RPOWER_RESET_REQUEST  => {
        method         => "POST",
        init_url       => "/power/reset",
    },
    RPOWER_RESET_RESPONSE => {
        process        => \&rpower_response,
    },
    RPOWER_STATUS_REQUEST  => {
        method         => "GET",
        init_url       => "/org/openbmc/settings/host0",
    },
    RPOWER_STATUS_RESPONSE => {
        process        => \&rpower_response,
    },

    RINV_MTHBRD_REQUEST => {
        method         => "GET",
        init_url       => "/org/openbmc/inventory/system/chassis/motherboard",
    },
    RINV_MTHBRD_RESPONSE => {
        process        => \&rinv_response,
    },
    RINV_CPU_REQUEST => {
        method         => "GET",
        init_url       => "/org/openbmc/inventory/system/chassis/motherboard/",
    },
    RINV_CPU_RESPONSE => {
        process        => \&rinv_response,
    },
    RINV_DIMM_REQUEST => {
        method         => "GET",
        init_url       => "/org/openbmc/inventory/system/chassis/motherboard/",
    },
    RINV_DIMM_RESPONSE => {
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
          back_urls   => (),
          $src => "",
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
    my $noderange = $request->{node};        

    parse_node_info($noderange);

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
    }  

    while (1) { 
        last unless ($wait_node_num);
        while (my ($response, $handle_id) = $async->wait_for_next_response) {
            deal_with_response($handle_id, $response);
        }
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

    $next_status{LOGIN_REQUEST} = "LOGIN_RESPONSE";

    if ($command eq "rpower") {
        if (!defined($extrargs)) {
            return ([ 1, "No option specified for rpower" ]);
        }

        if (scalar(@ARGV) > 1) {
            return ([ 1, "Only one option is supportted at the same time" ]);
        } 

        my $subcommand = $ARGV[0];

# now, only support status, delete when other command supported
if ($subcommand ne "status" and $subcommand ne "state" and $subcommand ne "stat") {
    return ([ 1, "Only support status check currently" ])
}
#----------------------------------------------------------------

        if ($subcommand eq "on") {
            $next_status{LOGIN_RESPONSE} = "RPOWER_ON_REQUEST";
            $next_status{RPOWER_ON_REQUEST} = "RPOWER_ON_RESPONSE";
        } elsif ($subcommand eq "off") {
            $next_status{LOGIN_RESPONSE} = "RPOWER_OFF_REQUEST";
            $next_status{RPOWER_OFF_REQUEST} = "RPOWER_OFF_RESPONSE";
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
        } else {
            return ([ 1, "$subcommand is not supported for rpower" ]);
        }
    }

    if ($command eq "rinv") {
        if (!defined($extrargs)) {
            return ([ 1, "No option specified for rpower" ]);
        }

        if (scalar(@ARGV) > 1) {
            return ([ 1, "Only one option is supportted at the same time" ]);
        }

        my $subcommand = $ARGV[0];

        if ($subcommand eq "cpu") {
            $next_status{LOGIN_RESPONSE} = "RINV_CPU_REQUEST";
            $next_status{RINV_CPU_REQUEST} = "RINV_CPU_RESPONSE";
        } elsif ($subcommand eq "dimm") {
            $next_status{LOGIN_RESPONSE} = "RINV_DIMM_REQUEST";
            $next_status{RINV_DIMM_REQUEST} = "RINV_DIMM_RESPONSE";
        } elsif ($subcommand eq "all") {
            $next_status{LOGIN_RESPONSE} = "RINV_MTHBRD_REQUEST";
            $next_status{RINV_MTHBRD_REQUEST} = "RINV_MTHBRD_RESPONSE";
            $next_status{RINV_MTHBRD_RESPONSE} = "RINV_CPU_REQUEST";
            $next_status{RINV_CPU_REQUEST} = "RINV_CPU_RESPONSE";
            $next_status{RINV_CPU_RESPONSE} = "RINV_DIMM_REQUEST";
            $next_status{RINV_DIMM_REQUEST} = "RINV_DIMM_RESPONSE";
        } else {
            return ([ 1, "Only 'cpu','dimm','all' are supportted at the same time" ]);
        }
    }

    print Dumper(%next_status) . "\n";

    return;
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

    print Dumper(%node_info) ."\n";

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

    if ($node_info{$node}{cur_url}) {
        $request_url = $node_info{$node}{cur_url};
    } else {
        $request_url = $status_info{ $node_info{$node}{cur_status} }{init_url};
    }
    $request_url = "https://" . $node_info{$node}{bmc} . $request_url;

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

    if ($response->status_line ne "200 OK") {
        my $response_info = decode_json $response->content;
        xCAT::SvrUtils::sendmsg($response_info->{'data'}->{'description'}, $callback, $node);
        $wait_node_num--;
        return;    
    }

    delete $handle_id_node{$handle_id};
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
        xCAT::SvrUtils::sendmsg("on", $callback, $node);
    } 

    if ($node_info{$node}{cur_status} eq "RPOWER_OFF_RESPONSE") {
        xCAT::SvrUtils::sendmsg("off", $callback, $node);
    }

    if ($node_info{$node}{cur_status} eq "RPOWER_STATUS_RESPONSE") {
        xCAT::SvrUtils::sendmsg($response_info->{'data'}->{system_state}, $callback, $node);
    }

    if ($next_status{ $node_info{$node}{cur_status} }) {
        if ($node_info{$node}{cur_status} eq "RPOWER_STATUS_RESPONSE") {
            if ($response_info->{'data'}->{system_state} =~ /HOST_POWERED_ON/) {
                $node_info{$node}{cur_status} = $next_status{ $node_info{$node}{cur_status} }{ON};
            } else {
                $node_info{$node}{cur_status} = $next_status{ $node_info{$node}{cur_status} }{OFF};
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

sub rinv_response {
    my $node = shift;
    my $response = shift;

    my $response_info = decode_json $response->content;

    my %rinv_response = (
        RINV_CPU_RESPONSE => {
            map_str => "cpu",
            repeat  => "RINV_CPU_REQUEST",
        },
        RINV_DIMM_RESPONSE => {
            map_str => "dimm",
            repeat  => "RINV_DIMM_REQUEST",
        },
  
    );

    my $grep_string = $rinv_response{$node_info{$node}{cur_status}}{map_str};
    my $repeat_status = $rinv_response{$node_info{$node}{cur_status}}{repeat};

    if ($node_info{$node}{cur_status} ne "RINV_MTHBRD_RESPONSE") {
        if (ref($response_info->{data}) eq "ARRAY") {
            foreach my $rsp_url (@{$response_info->{data}}) {
                if ($rsp_url =~ /\/$grep_string/) {
                    push @{ $node_info{$node}{back_urls} }, $rsp_url;
                }
            }
            
           $node_info{$node}{cur_url} = shift @{ $node_info{$node}{back_urls} };
           $node_info{$node}{cur_status} = $repeat_status;
           $node_info{$node}{src} = basename $node_info{$node}{cur_url};
           gen_send_request($node);
        } elsif (ref($response_info->{data}) eq "HASH") {
            my $cpu_info;
            foreach my $key (keys %{$response_info->{data}}) {
                $cpu_info = uc ($node_info{$node}{src}) . " " . $key . " : " . ${$response_info->{data}}{$key};
                xCAT::SvrUtils::sendmsg("$cpu_info", $callback, $node); 
            }

            if (@{ $node_info{$node}{back_urls} }) {
                $node_info{$node}{cur_url} = shift @{ $node_info{$node}{back_urls} };
                $node_info{$node}{cur_status} = $repeat_status;
                $node_info{$node}{src} = basename $node_info{$node}{cur_url};
                gen_send_request($node);
            } else {
                if ($next_status{ $node_info{$node}{cur_status} }) {
                    delete $node_info{$node}{cur_url};
                    delete $node_info{$node}{src};
                    gen_send_request($node);
                } else {
                    $wait_node_num--;
                }
            }
        }
    }

    #print Dumper(%node_info)  ."\n";
    return;
}


1;





