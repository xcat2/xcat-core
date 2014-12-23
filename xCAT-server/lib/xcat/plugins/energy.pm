#!/usr/bin/perl
# IBM(c) 2014 EPL license http://www.eclipse.org/legal/epl-v10.html

=head3  xCAT_plugin::energy

    This plugin module is used to handle the renergy command for:
        FSP based Power 8 machine. 
            1. mgt=fsp, mtm=(p8); 2. mgt=ipmi, arch=ppc64le;

=cut

package xCAT_plugin::energy;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}

use lib "$::XCATROOT/lib/perl";
use strict;
use warnings "all";
use Getopt::Long;

use xCAT::Usage;
use xCAT::CIMUtils;
use xCAT::MsgUtils;
use xCAT::Table;
use xCAT::FSPUtils;

sub handled_commands {
    return {
        renergy => 'nodehm:mgt=ipmi|fsp',
    }
}

# The hash includes all valid attribute for quering
my %QUERY_ATTRS = (
    'savingstatus' => 1,
    'dsavingstatus' => 1,
    'cappingstatus' => 1,
    'cappingmaxmin' => 1,
    'cappingvalue' => 1,
    'cappingsoftmin' => 1,
    'averageAC' => 1,
    'averageDC' => 1,
    'ambienttemp' => 1,
    'exhausttemp' => 1,
    'CPUspeed' => 1,
    'syssbpower' => 1,
    'sysIPLtime' => 1,
    # for FFO, only supported when communicating to fsp directly
    'ffoMin' => 1,
    'ffoVmin' => 1,
    'ffoTurbo' => 1,
    'ffoNorm' => 1,
    'fsavingstatus' => 1,
    'ffovalue' => 1,
);

# The hash includes all valid attribute for writting
my %SET_ATTRS = (
    'savingstatus' => 1,
    'dsavingstatus' => 1,
    'cappingstatus' => 1,
    'cappingwatt' => 1,
    'cappingperc' => 1,
    # for FFO
    'fsavingstatus' => 1,
    'ffovalue' => 1,
);

=head3  parse_args

    DESCRIPTION:
        Parse the arguments from the command line of renergy command
    ARGUMENTS:
        The request hash from preprocess_request or process_request
    RETURN
        First element: rc: 0 -success; 1 - fail
        Second element: 
            1. a string: a message for display; 
            2. a reference to a hash: {verbose}, {query_list} and {set_pair}.
            
=cut
sub parse_args {
    my $request = shift;

    my $opt     = ();
    my $cmd     = $request->{command}->[0];
    my $args    = $request->{arg};
    my $nodes   = $request->{node};

    my @query_list = ();   # The attributes list for query operation
    my @set_pair = ();      # The attribute need to be set. e.g. savingstatus=on
    
    my $set_flag = ();      # Indicate there's setting param in the argv  
    my $query_flag = ();     # Indicate there's param in the argv

    # set the usage subroutine
    local *usage = sub {
        my $add_msg = shift;
        my $usage_string = xCAT::Usage->getUsage($cmd);
        if ($add_msg) {
            return("$add_msg\n".$usage_string);
        } else {
            return($usage_string);
        }
    };

    # handle the arguments
    if ($request->{arg}) {
        @ARGV = @{$request->{arg}};

        $Getopt::Long::ignorecase = 0;
        Getopt::Long::Configure( "bundling" );

        if (!GetOptions( 'V'     => \$::VERBOSE,
                         'h|help'     => \$::HELP,
                         'v|version'  => \$::VERSION)) {
            return (1, &usage());
        }
        if ($::HELP && $::VERSION) {
            return (1, &usage());
        }
        if ($::HELP) {
            return (0, &usage());
        }
        
        if ($::VERSION) {
            my $version_string = xCAT::Usage->getVersion('renergy');
            return(0, $version_string);
        }

        if ($::VERBOSE) {
            $opt->{verbose} = 1;
        }
    }

    # if the request has node range
    if ($nodes) {
        # the default option is query all attributes
        if ($#ARGV < 0) {
            $ARGV[0] = "all";
        }
        # Check the validity of the parameters of Query and Set
        # Forbid to perform both query and set
        foreach my $attr (@ARGV) {
            my ($set_attr, $set_value) = split (/=/, $attr);
            if (defined($set_value)) {
                if ($query_flag) {
                    return (1, &usage("Cannot perform both Query and Set."));
                }

                # make sure the attribute is valid
                if ($SET_ATTRS{$set_attr} != 1) {
                    return (1, &usage("Invalid attribute."));
                }

                if ($set_flag) {
                    return (1, &usage("Only supports to perform one setting at invoke."));
                }

                # make sure the value for attirbute is valid
                if (($set_attr eq "savingstatus" || $set_attr eq "fsavingstatus") 
                     && ($set_value ne "on" && $set_value ne "off")) {
                    return (1, &usage("Incorrect Value"));
                } elsif ($set_attr eq "dsavingstatus"
                     && ($set_value ne "off"
                         && $set_value ne "on-norm" && $set_value ne "on-maxp")) {
                    return (1, &usage("Incorrect Value"));
                } elsif ($set_attr eq "cappingstatus" 
                     && ($set_value ne "on" && $set_value ne "off")) {
                    return (1, &usage("Incorrect Value"));
                } elsif ( ($set_attr eq "cappingwatt"  
                     || $set_attr eq "cappingperc" ||  $set_attr eq "ffovalue")
                       && $set_value =~ /\D/) {
                    return (1, &usage("Incorrect Value"));
                }

                push @set_pair, $set_attr."=".$set_value;
                $set_flag = 1;
            } else {
                if ($set_flag) {
                    return (1, &usage("Cannot perform both Query and Set."));
                }

                # replace the 'all' with all valid attribute
                if ($attr eq "all") {
                    foreach my $q_attr (keys %QUERY_ATTRS) {
                        if (!grep (/^$q_attr$/, @query_list)) {
                            push @query_list, $q_attr;
                        }
                    }
                } else {
                    # make sure the query attribute is valid
                    if ($QUERY_ATTRS{$attr} != 1) {
                        return (1, &usage("Invalid attribute."));
                    }
                    if (!grep (/^$attr$/, @query_list)) {
                        push @query_list, $attr;
                    }
                }
                $query_flag = 1;
            }
        }
    } else {
        # no noderange, do nothing
        return (1, &usage());
    }

    if (@query_list) {
        $opt->{'query_list'} = join(',', @query_list);
    } elsif (@set_pair) {
        $opt->{'set_pair'} = join(',',@set_pair);
    }

    return (0, $opt);
}

sub preprocess_request
{
    my $req = shift;
    my $callback = shift;

    # Exit if the packet has been preprocessed
    if (defined ($req->{_xcatpreprocessed}) && $req->{_xcatpreprocessed}->[0] == 1) { return [$req]; }

    my ($rc, $args) = parse_args($req);
    if ($rc) {
        # error or message display happens
        xCAT::MsgUtils->message("E", {error => [$args], errorcode => [$rc]}, $callback);
        return;
    } else {
        unless (ref($args)) {
            xCAT::MsgUtils->message("I", {data => [$args]}, $callback);
            return;
        }
    }

    # do nothing if no query or setting required. 
    unless (defined ($args->{query_list}) || defined($args->{set_pair})) {
        return;
    }

    # This plugin only handle the node which is 1. mgt=fsp, mtm=(p8); 2. mgt=ipmi, arch=ppc64le;
    # otherwise, make other plugin to handle it
    my (@mpnodes, @fspnodes, @bmcnodes, @nohandle);
    xCAT::Utils->filter_nodes($req, \@mpnodes, \@fspnodes, \@bmcnodes, \@nohandle);

    # Find the nodes which are not handled by mp (@mpnodes), fsp (@fspnodes) and bmc (@bmcnods), and not in @nohandle. 
    # They are the one of p8_fsp nodes which should be handled by this plugin
    my %tmphash = map {$_ => 1} (@mpnodes, @fspnodes, @bmcnodes, @nohandle);
    my @nodes  = grep {not $tmphash{$_}} @{$req->{node}};

    # build request array
    my @requests;
    if (@nodes) {
        my $sn = xCAT::ServiceNodeUtils->get_ServiceNode( \@nodes, 'xcat', 'MN' );
    
        # Build each request for each service node
        foreach my $snkey ( keys %$sn ) {
            my $reqcopy = {%$req};
            $reqcopy->{node} = $sn->{$snkey};
            $reqcopy->{'_xcatdest'} = $snkey;
            $reqcopy->{_xcatpreprocessed}->[0] = 1;
            if (defined($args->{verbose})) {
                $reqcopy->{verbose} = $args->{verbose};
            }
            if (defined($args->{query_list})) {
                $reqcopy->{query_list} = $args->{query_list};
            }
            if (defined($args->{set_pair})) {
                $reqcopy->{set_pair} = $args->{set_pair};
            }
            push @requests, $reqcopy;
        }
    
        return \@requests;
    }

    return;
}


sub process_request {
    my $request = shift;
    my $callback = shift;
    my $subreq = shift;

    my $verbose;

    my $nodes = $request->{node};
    my $args = $request->{arg};
    if (defined($request->{verbose})) {
        $verbose = $request->{verbose};
    }

    # get the password for the nodes
    my $user_default = "admin";
    my $password_default = "admin";

    my $ipmi_tab = xCAT::Table->new('ipmi', -create=>0);
    my $ipmi_hash;
    if ($ipmi_tab) {
        $ipmi_hash = $ipmi_tab->getNodesAttribs($request->{node}, ['bmc', 'username','password']);
    }

    my $ppc_tab = xCAT::Table->new('ppc', -create=>0);
    my $ppc_hash;
    my @ppc_all_entry;
    my $cec2fsp;
    if ($ppc_tab) {
        $ppc_hash = $ppc_tab->getNodesAttribs($request->{node}, ['hcp', 'nodetype']);
    }

    my $nodehm_tab = xCAT::Table->new('nodehm', -create => 0);
    my $nodehm_hash;
    if ($nodehm_tab) {
        $nodehm_hash = $nodehm_tab->getNodesAttribs($request->{node}, ['mgt']);
    }

    my $ppcdirect_tab = xCAT::Table->new('ppcdirect', -create=>0);

    foreach my $node (@{$request->{node}}) {
        my $user = $user_default;
        my $password = $password_default;
        my $hcp_ip;
        
         if (defined ($nodehm_hash->{$node}->[0]->{mgt})) {
            my $mgt = $nodehm_hash->{$node}->[0]->{mgt};

            if ($mgt eq 'fsp') {
               # This is Power node which is running in PowerVM mode
                unless (@ppc_all_entry) {
                    @ppc_all_entry = $ppc_tab->getAllNodeAttribs(['node', 'parent', 'hcp', 'nodetype']);
                    foreach my $ppcentry (@ppc_all_entry) {
                        if (defined($ppcentry->{parent})) {
                            $cec2fsp->{$ppcentry->{parent}} .= "$ppcentry->{node},";
                        }
                    }
                }
                $hcp_ip = $cec2fsp->{$node};  
    
                # Get the user/password for the node
                if ($ppcdirect_tab) {
                    my $ppcdirect_hash = $ppcdirect_tab->getAttribs({hcp => $node, username => $user}, 'password');
                    if ($ppcdirect_hash) {
                        $password = $ppcdirect_hash->{'password'};
                    }
                }
            } elsif ($mgt eq 'ipmi') {
                if (defined ($ipmi_hash->{$node}->[0]->{bmc})){
                    # This is a ipmi managed node. (should be a ppcle)
                    $hcp_ip = $ipmi_hash->{$node}->[0]->{bmc};
                    if (defined ($ipmi_hash->{$node}->[0]->{username})){
                        $user = $ipmi_hash->{$node}->[0]->{username};
                        $password = $ipmi_hash->{$node}->[0]->{password};
                    }
                } else {
                    xCAT::MsgUtils->message("E", {data => ["$node: Missed attribute [bmc]."]}, $callback);
                    return 1;
                }
            } else {
                xCAT::MsgUtils->message("E", {data => ["$node: Support the valid mgt [fsp, ipmi]."]}, $callback);
                return 1;
            }
        } else {
             xCAT::MsgUtils->message("E", {data => ["$node: Missed important attributes [mgt] to know how to handle this node."]}, $callback);
             return 1;
        }
        unless ($hcp_ip) {
             xCAT::MsgUtils->message("E", {data => ["$node: Cannot find HCP"]}, $callback);
             return 1;
        }
        foreach my $ip (split(',', $hcp_ip)) {
            unless ($ip) { next; }
            my %args =  (
                node => $node,
                ip => $ip,
                port => '5989',
                method => 'POST',
                user => $user,
                password => $password);

            if ($verbose) {
                $args{verbose} = 1;
                $args{callback} = $callback;
                xCAT::MsgUtils->message("I", {data => ["$node: Access hcp [$ip], user [$user], passowrd [$password]"]}, $callback);
            }
            # call the cim utils to connect to cim server
            my $ret = run_cim ($request, $callback, \%args);
            # 0 - success; 1 - cim error; 10 - ip is not pingable; 11 - this ip is a standby fsp
            unless ($ret == 10 || $ret == 11) {
                last;
            }
        }
    } 
    
}

=head3 query_pum 

    DESCRIPTION:
        Query the attribute for instance of FipS_PUMService class

    ARGUMENTS:
        $http_params - refer to the HTTP_PARAMS in xCAT::CIMUtils.pm

    RETURN
        $ret - return code and messages
        $pum - a hash includes all the attributes
        $namepath - the name path of pum instance

=cut

sub query_pum
{
    my $http_params = shift;
    
    my %cimargs = ( classname => 'FipS_PUMService' );
    my ($ret, $value, $namepath) = xCAT::CIMUtils->enum_instance($http_params, \%cimargs);
    if ($ret->{rc}) {
        return ($ret);
    }

    # parse the return xml to get all the property of pum instance
    my $pum;
    foreach my $instance (@$value) {
        foreach my $pname (keys %{$instance->{property}}) {
            $pum->{$pname} = $instance->{property}->{$pname}->{value};
        }
    }
    
    return ($ret, $pum, $namepath);
}

=head3  run_cim

    DESCRIPTION:
        Handle the Query and Setting of Energy via CIM
        
    ARGUMENTS:
        $request
        $callback
        $http_params - refer to the HTTP_PARAMS in xCAT::CIMUtils.pm
        
    RETURN
        First element: rc: 0 -success; 1 - cim error; 10 - ip is not pingable; 11 - this ip is a standby fsp
        
=cut
sub run_cim
{
    my $request = shift;
    my $callback = shift;
    
    my $http_params = shift;
    my $node = $http_params->{node};

    my @output;
    my $verbose;
    my $query_list;
    my $set_pair;

    if (defined($request->{verbose})) {
        $verbose = $request->{verbose};
    }
    if (defined($request->{query_list})) {
        $query_list = $request->{query_list};
    }
    if (defined($request->{set_pair})) {
        $set_pair = $request->{set_pair};
    }

    # Try to connect CIM Server to Enumerate CEC object;
    # If cannot access this ip, return 10 for caller to connect to the next ip
    my $cimargs = {
        classname => 'fips_cec',
    };
    $http_params->{timeout} = 5;
    my ($ret, $value) = xCAT::CIMUtils->enum_instance($http_params, $cimargs);
    if ($ret->{rc}) {
        if ($ret->{msg} =~ /Couldn't connect to server/) {
            xCAT::MsgUtils->message("E", data => ["$node: Couldn not connect to server [$http_params->{ip}]."], $callback);
            return 10;
        } else {
            xCAT::MsgUtils->message("E", {data => ["$node: $ret->{msg}"]}, $callback);
            return 1;
        }
    }
    
   
    # ======start to handle the query and setting======
    
    # Pre-query some specific instances since some instances are common for multiple energy attributes
    #my $query_pum_capabilities_flag;    # set to query the instance for [FipS_PUMServiceCapabilities]
    my $query_pum_flag;    # set to query the instance for [FipS_PUMService]
    my $query_pum_value;    # the rep queried PUM instance
    my $namepath_pum;     # the name path of PUM instance

    if ($query_list) {
        foreach my $attr (split(',', $query_list)) {
            if ($attr =~ /^(savingstatus|dsavingstatus|fsavingstatus)$/) {
                $query_pum_flag = 1;
                last;
            }
            if ($attr =~ /^(ffoMin|ffoVmin|ffoTurbo|ffoNorm|ffovalue)$/) {
                $query_pum_flag = 1;
                last;
            }
        }
    }

    if ($set_pair) {
        my ($set_name, $set_value) = split('=', $set_pair);
        if ($set_name =~/^(savingstatus|dsavingstatus|fsavingstatus|ffovalue)$/) {
            $query_pum_flag = 1;
        }
    }
    
    # query the pre required instances 
    if ($query_pum_flag) {
        ($ret, $query_pum_value, $namepath_pum) = query_pum($http_params);
        if ($ret->{rc}) {
            xCAT::MsgUtils->message("E", {data => ["$node: $ret->{msg}"]}, $callback);
            return ($ret->{rc});
        }
    } 

    # perform the query request
    if ($query_list) {
        foreach my $attr (split(',', $query_list)) {
            # Query the power saving status
            if ($attr =~ /^(savingstatus|dsavingstatus|fsavingstatus)$/) {
                if ($query_pum_flag) {
                    if (defined ($query_pum_value->{PowerUtilizationMode})) {
                        # 2 = None; 3 = Dynamic; 4 = Static; 32768 = Dynamic Favor Performance; 32769 = FFO
                        if ($query_pum_value->{PowerUtilizationMode} eq "2") {
                            push @output, "$node: $attr: off";
                        } elsif ($query_pum_value->{PowerUtilizationMode} eq "3") {
                            if ($attr eq "dsavingstatus") {
                                push @output, "$node: $attr: on-norm";
                            } else {
                                 push @output, "$node: $attr: off";
                            }
                        } elsif ($query_pum_value->{PowerUtilizationMode} eq "4") {
                            if ($attr eq "savingstatus") {
                                push @output, "$node: $attr: on";
                            } else {
                                 push @output, "$node: $attr: off";
                            }
                        } elsif ($query_pum_value->{PowerUtilizationMode} eq "32768") {
                            if ($attr eq "dsavingstatus") {
                                push @output, "$node: $attr: on-maxp";
                            } else {
                                 push @output, "$node: $attr: off";
                            }
                        } elsif ($query_pum_value->{PowerUtilizationMode} eq "32769") {
                            if ($attr eq "fsavingstatus") {
                                push @output, "$node: $attr: on";
                            } else {
                                 push @output, "$node: $attr: off";
                            }
                        }
                    } else {
                        push @output, "$node: $attr: na";
                    }
                } else {
                    push @output, "$node: $attr: na";
                }
            }
    
            # Query the FFO settings
            if ($attr =~ /^(ffoMin|ffoVmin|ffoTurbo|ffoNorm|ffovalue)$/) {
                if ($query_pum_flag) {
                    if (defined ($query_pum_value->{FixedFrequencyPoints}) && defined ($query_pum_value->{FixedFrequencyPointValues})) {
                        my @ffo_point = split (',', $query_pum_value->{FixedFrequencyPoints});
                        my @ffo_point_value = split (',', $query_pum_value->{FixedFrequencyPointValues});
                        foreach my $index (0..$#ffo_point) {
                            if ($ffo_point[$index] eq '2' && $attr eq 'ffoNorm') { # Norminal
                                push @output, "$node: $attr: $ffo_point_value[$index]";
                            } elsif ($ffo_point[$index] eq '3' && $attr eq 'ffoTurbo') { # Turbo
                                push @output, "$node: $attr: $ffo_point_value[$index]";
                            } elsif ($ffo_point[$index] eq '4' && $attr eq 'ffoVmin') { # Vmin
                                push @output, "$node: $attr: $ffo_point_value[$index]";
                            } elsif ($ffo_point[$index] eq '5' && $attr eq 'ffoMin') { # Min
                                push @output, "$node: $attr: $ffo_point_value[$index]";
                            }
                        }
                    } else {
                        push @output, "$node: $attr: na";
                    }
                } else {
                    push @output, "$node: $attr: na";
                }
            }
    
            # Query the FFO Value
            if ($attr eq 'ffovalue') {
                if ($query_pum_flag) {
                    if (defined ($query_pum_value->{FixedFrequencyOverrideFreq})) {
                        if ($query_pum_value->{FixedFrequencyOverrideFreq} eq '4294967295') {
                            push @output, "$node: $attr: 0";
                        } else {
                            push @output, "$node: $attr: $query_pum_value->{FixedFrequencyOverrideFreq}";
                        }
                    } else {
                        push @output, "$node: $attr: na";
                    }
                } else {
                    push @output, "$node: $attr: na";
                }
    
            }
        }
    }

    # Perform the setting request
    if ($set_pair) {
        my ($set_name, $set_value) = split('=', $set_pair);
        if ($set_name =~/^(savingstatus|dsavingstatus|fsavingstatus|ffovalue)$/) {
            if ($query_pum_flag) {
                if (defined ($query_pum_value->{PowerUtilizationMode})) {

                    # set the power saving value
                    my $ps_value;
                    if ($set_name eq "savingstatus") {
                        if ($set_value eq 'on') {
                            $ps_value = '4';
                        } elsif ($set_value eq 'off') {
                            $ps_value = '2';
                        }
                    } elsif ($set_name eq "dsavingstatus") {
                        if ($set_value eq 'on-norm') {
                            $ps_value = '3';
                        } elsif ($set_value eq 'on-maxp') {
                            $ps_value = '32768';
                        }elsif ($set_value eq 'off') {
                            $ps_value = '2';
                        }
                    } elsif ($set_name eq "fsavingstatus") {
                        if ($set_value eq 'on') {
                            $ps_value = '32769';
                        } elsif ($set_value eq 'off') {
                            $ps_value = '2';
                        }
                    } 
    
                    if ($set_name eq "ffovalue") {
                        # set ffo value
                        $cimargs = {
                            propertyname => 'FixedFrequencyOverrideFreq',
                            propertyvalue =>  $set_value,
                            namepath => $namepath_pum,
                        };
                        $ret = xCAT::CIMUtils->set_property($http_params, $cimargs);
                        if ($ret->{rc}) {
                            push @output, "$node: Set $set_name failed. [$ret->{msg}]"; 
                        } else {
                            push @output, "$node: Set $set_name succeeded";
                        }
                    } else {
                        # set the power saving
                        if ($ps_value eq $query_pum_value->{PowerUtilizationMode}) {    # do nothing if it already was the correct status
                            push @output, "$node: Set $set_name succeeded";
                        } else {
                            # perform the setting
                            $cimargs = {
                                propertyname => 'PowerUtilizationMode',
                                propertyvalue =>  $ps_value,
                                namepath => $namepath_pum,
                            };
                            $ret = xCAT::CIMUtils->set_property($http_params, $cimargs);
                            if ($ret->{rc}) {
                                push @output, "$node: Set $set_name failed. [$ret->{msg}]"; 
                            } else {
                                push @output, "$node: Set $set_name succeeded";
                            }
                        }
                    }
                } else {
                     push @output, "$node: Set $set_name failed"; 
                }
            } else {
                push @output, "$node: Set $set_name failed"; 
            }
        }
    } 

    # Display the output
    my $rsp;
    push @{$rsp->{data}}, @output;
    xCAT::MsgUtils->message("I", $rsp, $callback);

    return;    
}


1;
