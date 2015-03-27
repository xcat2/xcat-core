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
use IO::Socket;
use Thread qw(yield);
use POSIX "WNOHANG";
use Storable qw(store_fd fd_retrieve);

use xCAT::Usage;
use xCAT::CIMUtils;
use xCAT::MsgUtils;
use xCAT::Table;
use xCAT::FSPUtils;
use xCAT::NetworkUtils;

sub handled_commands {
    return {
        renergy => 'nodehm:mgt=ipmi|fsp',
    }
}

my $parent_fd;

# The hash includes all valid attribute for quering
my %QUERY_ATTRS = (
    'savingstatus' => 1,
    'dsavingstatus' => 1,
    'cappingstatus' => 1,
    'cappingmaxmin' => 1,
    'cappingvalue' => 1,
    'cappingsoftmin' => 1,
    'averageAC' => 1,
    'averageAChistory' => 1,
    'averageDC' => 1,
    'averageDChistory' => 1,
    'ambienttemp' => 1,
    'ambienttemphistory' => 1,
    'exhausttemp' => 1,
    'exhausttemphistory' => 1,
    'CPUspeed' => 1,
    'CPUspeedhistory' => 1,
    'fanspeed' => 1,
    'fanspeedhistory' => 1,
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
                        # do not include 'history' related attributes for all keyword
                        if ($q_attr =~ /history$/) {
                            next;
                        }
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
    if (defined ($req->{_xcatpreprocessed}->[0]) && $req->{_xcatpreprocessed}->[0] == 1) { return [$req]; }

    my ($rc, $args) = parse_args($req);
    if ($rc) {
        # error or message display happens
        xCAT::MsgUtils->message("E", {error => [$args], errorcode => [$rc]}, $callback);
        return [];
    } else {
        unless (ref($args)) {
            xCAT::MsgUtils->message("I", {data => [$args]}, $callback);
            return [];
        }
    }

    # do nothing if no query or setting required. 
    unless (defined ($args->{query_list}) || defined($args->{set_pair})) {
        return [];
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

    return [];
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

    my $children;    # The number of child process
    my %sp_children;    # Record the pid of child process
    my $sub_fds = new IO::Select;    # Record the parent fd for each child process

    # Set the signal handler for ^c
    $SIG{TERM} = $SIG{INT} = sub {
        foreach (keys %sp_children) {
            kill 2, $_;
        }
        $SIG{ALRM} = sub { 
            while (wait() > 0) {
                yield;
            }
            exit @_;
        };
        alarm(1); # wait 1s for grace exit
    };

    # Set the singal handler for child process finished it's work
    $SIG{CHLD} = sub { 
        my $cpid; 
        while (($cpid = waitpid(-1, WNOHANG)) > 0) { 
            if ($sp_children{$cpid}) { 
                delete $sp_children{$cpid}; 
                $children--; 
            } 
        } 
    };

    # Do run each node
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
                        if (defined($ppcentry->{parent}) && defined($ppcentry->{nodetype}) && $ppcentry->{nodetype} =~ /fsp/) {
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

        # fork a sub process to handle the communication with service processor
        $children++;
        my $cfd;

        # the $parent_fd will be used by &send_rep() to send response from child process to parent process
        socketpair($parent_fd, $cfd,AF_UNIX,SOCK_STREAM,PF_UNSPEC) or die "socketpair: $!";
        $cfd->autoflush(1);
        $parent_fd->autoflush(1);
        
        my $child = xCAT::Utils->xfork;
        if ($child == 0) {
            close($cfd);
            $0 = $0." for node [$node]";
            $callback = \&send_rep;
            foreach my $ip (split(',', $hcp_ip)) {
                unless ($ip) { next; }
                my $real_ip = xCAT::NetworkUtils->getipaddr($ip);
                unless ($real_ip) {
                    xCAT::MsgUtils->message("E", {error => ["$node: Cannot get ip for $ip"], errorcode => [1]}, $callback);
                    next;
                }
                my %args =  (
                    node => $node,
                    ip => $real_ip,
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
            exit(0);
        } else {
            # in the main process, record the created child process and add parent fd for the child process to an IO:Select object 
            # the main process will check all the parent fd and receive response
            $sp_children{$child}=1;
            close ($parent_fd);
            $sub_fds->add($cfd);
        }
    }

    # receive data from child processes
    while ($sub_fds->count > 0 or $children > 0) {
        forward_data($callback,$sub_fds);
    }
    while (forward_data($callback,$sub_fds)) {}
}

=head3 send_rep 

    DESCRIPTION:
        Send date from forked child process to parent process.
        This subroutine will be replace the original $callback in the forked child process

    ARGUMENTS:
        $resp - The response which generated in xCAT::Utils->message();

=cut
sub send_rep {
    my $resp=shift;
    
    unless ($resp) { return; }
    store_fd($resp,$parent_fd);
}

=head3 forward_data 

    DESCRIPTION:
        Receive data from forked child process and call the original $callback to forward data to xcat client

=cut
sub forward_data {
  my $callback = shift;
  my $fds = shift;
  my @ready_fds = $fds->can_read(1);
  my $rfh;
  my $rc = @ready_fds;
  foreach $rfh (@ready_fds) {
    my $data;
    my $responses;
    eval {
    	$responses = fd_retrieve($rfh); 
    };
    if ($@ and $@ =~ /^Magic number checking on storable file/) { #this most likely means we ran over the end of available input
      $fds->remove($rfh);
      close($rfh);
    } else {
      eval { print $rfh "ACK\n"; }; #Ignore ack loss due to child giving up and exiting, we don't actually explicitly care about the acks
      $callback->($responses);
    }
  }
  yield; #Try to avoid useless iterations as much as possible
  return $rc;
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
    if ($value && @$value) {
        my $instance = $$value[0];
        foreach my $pname (keys %{$instance->{property}}) {
            $pum->{$pname} = $instance->{property}->{$pname}->{value};
        }
    }
    
    return ($ret, $pum, $namepath);
}

=head3 query_cec_drawer 

    DESCRIPTION:
        Query the attribute for instance of FipS_CECDrawer class

    ARGUMENTS:
        $http_params - refer to the HTTP_PARAMS in xCAT::CIMUtils.pm

    RETURN
        $ret - return code and messages
        $cec_drawer - a hash includes all the attributes

=cut
sub query_cec_drawer
{
    my $http_params = shift;
    
    my %cimargs = ( classname => 'FipS_CECDrawer' );
    my ($ret, $value, $namepath) = xCAT::CIMUtils->enum_instance($http_params, \%cimargs);
    if ($ret->{rc}) {
        return ($ret);
    }

    # parse the return xml to get all the property of pum instance
    my $cec_drawer;
    if ($value && @$value) {
        my $instance = $$value[0];
        foreach my $pname (keys %{$instance->{property}}) {
            $cec_drawer->{$pname} = $instance->{property}->{$pname}->{value};
        }
    } else {
        return ({rc => 1, msg => "Cannot find instance for FipS_CECDrawer class"});
    }
    
    return ($ret, $cec_drawer, $namepath);
}

=head3 query_metric

    DESCRIPTION:
        Query the attribute for instance of FipS_*metricValue class

    ARGUMENTS:
        $http_params - refer to the HTTP_PARAMS in xCAT::CIMUtils.pm
        $option - the specified operation

    RETURN
        $ret - return code and messages
        $array - a hash includes all the attributes

=cut

sub query_metric
{
    my $http_params = shift;
    my $classname = shift;
    my $matching_string = shift;
    my $value_unit = shift;
    if (!defined($value_unit)) {
        $value_unit = 1;
    }
    my %cimargs = ( classname => "$classname" );
    my ($ret, $value) = xCAT::CIMUtils->enum_instance($http_params, \%cimargs);
    if ($ret->{rc}) {
        return $ret;
    }
    my ($matching_key, $matching_value) = split /:/,$matching_string;
    my %instances_hash = ();
    foreach my $instance (@$value) {
        my $instance_element = undef;
        my $timestamp = undef;
        if (defined ($instance->{property}->{$matching_key}) and $instance->{property}->{$matching_key}->{value} !~ /$matching_value/) {
            next;
        }
        if (defined ($instance->{property}->{InstanceID})) {
            $instance_element = $instance->{property}->{InstanceID}->{value};
            $instance_element =~ s/ .*$//;
        }
        if (!defined($instance_element)) {
            next;
        }

        if (defined ($instance->{property}->{MeasuredElementName})) {
            $instances_hash{$instance_element}->{MeasuredElementName} = $instance->{property}->{MeasuredElementName}->{value};
        } else {
            next;
        }

        if (defined ($instance->{property}->{TimeStamp})) {
            $timestamp = $instance->{property}->{TimeStamp}->{value};
            $timestamp =~ s/\..*$//;
        }
        if (defined ($instance->{property}->{MetricValue})) {
            if (defined($timestamp)) {
                $instances_hash{$instance_element}->{MetricValue}->{$timestamp} = $instance->{property}->{MetricValue}->{value} / $value_unit;
            }
        }
    }

    return ($ret, \%instances_hash);
}

=head3 query_tmp
    DESCRIPTION:
        Require the input and output temperature
=cut 
sub query_tmp 
{
    &query_metric(@_, "FipS_ThermalMetricValue", "InstanceID:InletAirTemp|ExhaustAirTemp", 100);
}
=head3 query_cpuspeed
    DESCRIPTION:
        Require the cpuspeed history
=cut 
sub query_cpuspeed
{
    &query_metric(@_, "FipS_CPUUsageMetricValue", "InstanceID:AvgCPUUsage");
}
=head3 query_fanspeed
    DESCRIPTION:
        Require the fanspeed history
=cut 
sub query_fanspeed
{
    &query_metric(@_, "FipS_FanSpeedMetricValue", "InstanceID:FansSpeed");
}
=head3 query_powermetric
    DESCRIPTION:
        Require the AC and DC power comsume history
=cut 
sub query_powermetric
{
    my $http_params = shift;
    $http_params->{timeout} = 500;
    my ($ret, $return_hash) = &query_metric($http_params, "FipS_PowerMetricValue", "InstanceID:AvgInputPwr");
    if ($ret->{rc})  {
        return $ret;
    }
    my %instances = ();
    foreach my $ins (keys %$return_hash) {
        if ($return_hash->{$ins}->{MeasuredElementName} =~ /Power Supply/) {
            foreach my $timestamp (keys %{$return_hash->{$ins}->{MetricValue}}) {
                if (!exists($instances{"averageAC"}->{MetricValue}->{$timestamp})) {
                    $instances{"averageAC"}->{MetricValue}->{$timestamp} = $return_hash->{$ins}->{MetricValue}->{$timestamp};
                } else {
                    $instances{"averageAC"}->{MetricValue}->{$timestamp} += $return_hash->{$ins}->{MetricValue}->{$timestamp};
                }
            }
        } else {
            $instances{"averageDC"}->{MetricValue} = $return_hash->{$ins}->{MetricValue};
        }
    }
    return ($ret, \%instances); 
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

    my $output;
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
        if ($ret->{msg} =~ /(Couldn't connect to server)|(Can't connect to)/) {
            xCAT::MsgUtils->message("E", {data => ["$node: Couldn't connect to server [$http_params->{ip}]."]}, $callback);
            return 10;
        } else {
            xCAT::MsgUtils->message("E", {data => ["$node: $ret->{msg}"]}, $callback);
            return 1;
        }
    }
    delete $http_params->{timeout};
    # check whether the primary ip of fsp is the IP we are accessing
    if (defined ($value->[0]->{property}->{PrimaryFSP_IP}->{value}) && $value->[0]->{property}->{PrimaryFSP_IP}->{value} ne $http_params->{ip}) {
        # run against the standby fsp, do the next one
        return 11;
    }
    
   
    # ======start to handle the query and setting======
    
    # Pre-query some specific instances since some instances are common for multiple energy attributes
    #my $query_pum_capabilities_flag;    # set to query the instance for [FipS_PUMServiceCapabilities]
    my $query_pum_flag;    # set to query the instance for [FipS_PUMService]
    my $query_pum_value;    # the pre-queried PUM instance
    my $namepath_pum;     # the name path of PUM instance

    my $query_drawer_flag;    # set to query the instance for [FipS_CECDrawer]
    my $query_drawer_value;    # the pre-queried cec drawer instance
    
    my %query_return_hash = (); # the hash store the returned hashes for query functions
    my $query_tmp_value; # the requrest for FipS_ThermalMetricValue class
    my $query_cpuspeed_value; # the request for FipS_CPUUsageMetricValue class
    my $query_fanspeed_value; # the request for FipS_FanSpeedMetricValue class
    my $query_powermetric_value; # the request for FipS_PowerMetricValue class
    if ($query_list) {
        foreach my $attr (split(',', $query_list)) {
            if ($attr =~ /^(savingstatus|dsavingstatus|fsavingstatus|ffoMin|ffoVmin|ffoTurbo|ffoNorm|ffovalue)$/) {
                $query_pum_flag = 1;
            } elsif ($attr =~ /^(syssbpower|sysIPLtime)$/) {
                $query_drawer_flag = 1;
            } elsif ($attr =~ /^(ambienttemp|exhausttemp)/) {
                $query_tmp_value = 1;
            } elsif ($attr =~ /^CPUspeed/) {
                $query_cpuspeed_value = 1;
            } elsif ($attr =~ /^fanspeed/) {
                $query_fanspeed_value = 1;
            } elsif ($attr =~ /^(averageAC|averageDC)/) {
                $query_powermetric_value = 1;
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
    if ($query_drawer_flag) {
        ($ret, $query_drawer_value) = query_cec_drawer($http_params);
        if ($ret->{rc}) {
            xCAT::MsgUtils->message("E", {data => ["$node: $ret->{msg}"]}, $callback);
            return ($ret->{rc});
        }
    }
    if ($query_powermetric_value) {
        my ($tmpret, $tmpvalue) = query_powermetric($http_params);
        if ($tmpret->{rc}) {
            xCAT::MsgUtils->message("E", {data => ["$node: $ret->{msg}"]}, $callback);
            return ($tmpret->{rc});
        }
        $query_return_hash{query_powermetric} = $tmpvalue;
    }
    if ($query_fanspeed_value) {
        $http_params->{timeout} = 200;
        my ($tmpret, $tmpvalue) = query_fanspeed($http_params);
        if ($tmpret->{rc}) {
            xCAT::MsgUtils->message("E", {data => ["$node: $ret->{msg}"]}, $callback);
            return ($tmpret->{rc});
        }
        $query_return_hash{query_fanspeed} = $tmpvalue;
    }
    if ($query_cpuspeed_value) {
        my ($tmpret, $tmpvalue) = query_cpuspeed($http_params);
        if ($tmpret->{rc}) {
            xCAT::MsgUtils->message("E", {data => ["$node: $ret->{msg}"]}, $callback);
            return ($tmpret->{rc});
        }
        $query_return_hash{query_cpuspeed} = $tmpvalue;
    }
    if ($query_tmp_value) {
        $http_params->{timeout} = 200;
        my ($tmpret, $tmpvalue) = query_tmp($http_params);
        if ($tmpret->{rc}) {
            xCAT::MsgUtils->message("E", {data => ["$node: $ret->{msg}"]}, $callback);
            return ($tmpret->{rc});
        }
        $query_return_hash{query_tmp} = $tmpvalue;
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
                            push @{$output->{$node}}, "$attr: off";
                        } elsif ($query_pum_value->{PowerUtilizationMode} eq "3") {
                            if ($attr eq "dsavingstatus") {
                                push @{$output->{$node}}, "$attr: on-norm";
                            } else {
                                 push @{$output->{$node}}, "$attr: off";
                            }
                        } elsif ($query_pum_value->{PowerUtilizationMode} eq "4") {
                            if ($attr eq "savingstatus") {
                                push @{$output->{$node}}, "$attr: on";
                            } else {
                                 push @{$output->{$node}}, "$attr: off";
                            }
                        } elsif ($query_pum_value->{PowerUtilizationMode} eq "32768") {
                            if ($attr eq "dsavingstatus") {
                                push @{$output->{$node}}, "$attr: on-maxp";
                            } else {
                                 push @{$output->{$node}}, "$attr: off";
                            }
                        } elsif ($query_pum_value->{PowerUtilizationMode} eq "32769") {
                            if ($attr eq "fsavingstatus") {
                                push @{$output->{$node}}, "$attr: on";
                            } else {
                                 push @{$output->{$node}}, "$attr: off";
                            }
                        }
                    } else {
                        push @{$output->{$node}}, "$attr: na";
                    }
                } else {
                    push @{$output->{$node}}, "$attr: na";
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
                                push @{$output->{$node}}, "$attr: $ffo_point_value[$index] MHZ";
                            } elsif ($ffo_point[$index] eq '3' && $attr eq 'ffoTurbo') { # Turbo
                                push @{$output->{$node}}, "$attr: $ffo_point_value[$index] MHZ";
                            } elsif ($ffo_point[$index] eq '4' && $attr eq 'ffoVmin') { # Vmin
                                push @{$output->{$node}}, "$attr: $ffo_point_value[$index] MHZ";
                            } elsif ($ffo_point[$index] eq '5' && $attr eq 'ffoMin') { # Min
                                push @{$output->{$node}}, "$attr: $ffo_point_value[$index] MHZ";
                            }
                        }
                    } else {
                        push @{$output->{$node}}, "$attr: na";
                    }
                } else {
                    push @{$output->{$node}}, "$attr: na";
                }
            }
    
            # Query the FFO Value
            if ($attr eq 'ffovalue') {
                if ($query_pum_flag) {
                    if (defined ($query_pum_value->{FixedFrequencyOverrideFreq})) {
                        if ($query_pum_value->{FixedFrequencyOverrideFreq} eq '4294967295') {
                            push @{$output->{$node}}, "$attr: 0 MHZ";
                        } else {
                            push @{$output->{$node}}, "$attr: $query_pum_value->{FixedFrequencyOverrideFreq} MHZ";
                        }
                    } else {
                        push @{$output->{$node}}, "$attr: na";
                    }
                } else {
                    push @{$output->{$node}}, "$attr: na";
                }
    
            }
            
            # Query the attribute sysIPLtime and syssbpower
            if ($attr =~ /^(syssbpower|sysIPLtime)$/) {
                if ($query_drawer_flag) {
                    if (defined ($query_drawer_value->{AverageTimeToIPL}) && $attr eq "sysIPLtime") {
                        push @{$output->{$node}}, "$attr: $query_drawer_value->{AverageTimeToIPL} S";
                    } elsif (defined ($query_drawer_value->{StandbyPowerUtilization}) && $attr eq "syssbpower") {
                        push @{$output->{$node}}, "$attr: $query_drawer_value->{StandbyPowerUtilization} W";
                    } else {
                        push @{$output->{$node}}, "$attr: na";
                    }
                } else {
                    push @{$output->{$node}}, "$attr: na";
                }
            }

            if ($attr =~ /^ambienttemp/) {
                my $tmphash = $query_return_hash{query_tmp};
                foreach my $ins (keys %$tmphash) {
                    if ($ins =~ /InletAirTemp/) {
                        my @times = sort keys %{$tmphash->{$ins}->{MetricValue}};
                        if ($attr eq "ambienttemp") {
                            #push @{$output->{$node}}, "$attr ($tmphash->{$ins}->{MeasuredElementName}): $tmphash->{$ins}->{MetricValue}->{$times[-1]}";
                            push @{$output->{$node}}, "$attr: $tmphash->{$ins}->{MetricValue}->{$times[-1]} C";
                        } else {
                            foreach my $time (@times) {
                                #push @{$output->{$node}}, "$attr ($tmphash->{$ins}->{MeasuredElementName}): $tmphash->{$ins}->{MetricValue}->{$time}: $time";
                                push @{$output->{$node}}, "$attr: $tmphash->{$ins}->{MetricValue}->{$time} C: $time";
                            }
                        }
                    }
                }
            } elsif ($attr =~ /^exhausttemp/) {
                my $tmphash = $query_return_hash{query_tmp}; 
                foreach my $ins (keys %$tmphash) {
                    if ($ins =~ /ExhaustAirTemp/) {
                        my @times = sort keys %{$tmphash->{$ins}->{MetricValue}};
                        if ($attr eq "exhausttemp") {
                            #push @{$output->{$node}}, "$attr ($tmphash->{$ins}->{MeasuredElementName}): $tmphash->{$ins}->{MetricValue}->{$times[-1]}";
                            push @{$output->{$node}}, "$attr: $tmphash->{$ins}->{MetricValue}->{$times[-1]} C";
                        } else {
                            foreach my $time (@times) {
                                #push @{$output->{$node}}, "$attr ($tmphash->{$ins}->{MeasuredElementName}): $tmphash->{$ins}->{MetricValue}->{$time}: $time";
                                push @{$output->{$node}}, "$attr: $tmphash->{$ins}->{MetricValue}->{$time} C: $time";
                            }
                        }
                    }
                }
            } elsif ($attr =~ /^CPUspeed/) {
                my $tmphash = $query_return_hash{query_cpuspeed}; 
                foreach my $ins (keys %$tmphash) {
                    if ($ins =~ /AvgCPUUsage/) {
                        my @times = sort keys %{$tmphash->{$ins}->{MetricValue}};
                        if ($attr eq "CPUspeed") {
                            #push @{$output->{$node}}, "$attr ($tmphash->{$ins}->{MeasuredElementName}): $tmphash->{$ins}->{MetricValue}->{$times[-1]}";
                            push @{$output->{$node}}, "$attr: $tmphash->{$ins}->{MetricValue}->{$times[-1]} MHZ";
                        } else {
                            foreach my $time (@times) {
                                #push @{$output->{$node}}, "$attr ($tmphash->{$ins}->{MeasuredElementName}): $tmphash->{$ins}->{MetricValue}->{$time}: $time";
                                push @{$output->{$node}}, "$attr: $tmphash->{$ins}->{MetricValue}->{$time} MHZ: $time";
                            }
                        }
                    }
                }
            } elsif ($attr =~ /^fanspeed/) {
                my $tmphash = $query_return_hash{query_fanspeed}; 
                foreach my $ins (keys %$tmphash) {
                    if ($ins =~ /FansSpeed/) {
                        my @times = sort keys %{$tmphash->{$ins}->{MetricValue}};
                        if ($attr eq "fanspeed") {
                            push @{$output->{$node}}, "$attr ($tmphash->{$ins}->{MeasuredElementName}): $tmphash->{$ins}->{MetricValue}->{$times[-1]} RPM";
                        } else {
                            foreach my $time (@times) {
                                push @{$output->{$node}}, "$attr ($tmphash->{$ins}->{MeasuredElementName}): $tmphash->{$ins}->{MetricValue}->{$time} RPM: $time";
                            }
                        }
                    }
                }
                $query_fanspeed_value = 1;
            } elsif ($attr =~ /^(averageAC|averageDC)/) {
                my $tmpattr = $1;
                my $tmphash = $query_return_hash{query_powermetric};
                my @times = sort keys %{$tmphash->{$tmpattr}->{MetricValue}};
                if ($attr =~ /history$/) {
                    foreach my $time (@times) {
                        push @{$output->{$node}}, "$attr: $tmphash->{$tmpattr}->{MetricValue}->{$time} W: $time";
                    }
                } else {
                    push @{$output->{$node}}, "$attr: $tmphash->{$attr}->{MetricValue}->{$times[-1]} W";
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
                            push @{$output->{$node}}, "Set $set_name failed. [$ret->{msg}]"; 
                        } else {
                            push @{$output->{$node}}, "Set $set_name succeeded";
                        }
                    } else {
                        # set the power saving
                        if ($ps_value eq $query_pum_value->{PowerUtilizationMode}) {    # do nothing if it already was the correct status
                            push @{$output->{$node}}, "Set $set_name succeeded";
                        } else {
                            # perform the setting
                            $cimargs = {
                                propertyname => 'PowerUtilizationMode',
                                propertyvalue =>  $ps_value,
                                namepath => $namepath_pum,
                            };
                            $ret = xCAT::CIMUtils->set_property($http_params, $cimargs);
                            if ($ret->{rc}) {
                                push @{$output->{$node}}, "Set $set_name failed. [$ret->{msg}]"; 
                            } else {
                                push @{$output->{$node}}, "Set $set_name succeeded";
                            }
                        }
                    }
                } else {
                     push @{$output->{$node}}, "Set $set_name failed"; 
                }
            } else {
                push @{$output->{$node}}, "Set $set_name failed"; 
            }
        }
    } 

    # Display the output
    foreach my $node (keys (%{$output})) {
        my @newoutput;
        if ($query_list && $query_list !~ /history/) {
            @newoutput = sort (@{$output->{$node}});
        } else {
            @newoutput = @{$output->{$node}};
        }
        foreach (@newoutput) {
            my $rsp;
            $rsp->{node}->[0]->{name} = $node;
            push @{$rsp->{node}->[0]->{data}->[0]->{contents}}, $_;

            xCAT::MsgUtils->message("N", $rsp, $callback);
        }
    }

    return 0;    
}


1;
