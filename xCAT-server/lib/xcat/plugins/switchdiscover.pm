#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT_plugin::switchdiscover;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";

use Getopt::Long;
use xCAT::Usage;
use xCAT::NodeRange;
use xCAT::NetworkUtils;
use xCAT::Utils;
use XML::Simple;
no strict;
use Data::Dumper;
use Socket;

#global variables for this module
my %globalopt;
my @filternodes;
my @iprange;
my %global_scan_type = (
    nmap => "nmap_scan",
    lldp => "lldp_scan",
    snmp => "snmp_scan"
);

my %global_switch_type = (
    Juniper => "Jun",
    Cisco => "Cisco",
    BNT => "BNT",
    Mellanox => "Mellanox"
);

#-------------------------------------------------------------------------------
=head1  xCAT_plugin:switchdiscover
=head2    Package Description
    Handles switch discovery functions. It uses lldp, nmap or snmap to scan
    the network to find out the switches attached to the network.
=cut
#-------------------------------------------------------------------------------


#--------------------------------------------------------------------------------
=head3   send_msg
      Invokes the callback with the specified message
    Arguments:
        request: request structure for plguin calls
        ecode: error code. 0 for succeful.
        msg: messages to be displayed.
    Returns:
        none
=cut
#--------------------------------------------------------------------------------
sub send_msg {

    my $request = shift;
    my $ecode   = shift;
    my $msg     = shift;
    my %output;

    #################################################
    # Called from child process - send to parent
    #################################################
    if ( exists( $request->{pipe} )) {
        my $out = $request->{pipe};

        $output{errorcode} = $ecode;
        $output{data} = \@_;
        print $out freeze( [\%output] );
        print $out "\nENDOFFREEZE6sK4ci\n";
    }
    #################################################
    # Called from parent - invoke callback directly
    #################################################
    elsif ( exists( $request->{callback} )) {
        my $callback = $request->{callback};
        $output{errorcode} = $ecode;
        $output{data} = $msg;
        $callback->( \%output );
    }
}


#--------------------------------------------------------------------------------
=head3   handled_commands
      It returns a list of commands handled by this plugin.
    Arguments:
       none
    Returns:
       a list of commands.
=cut
#--------------------------------------------------------------------------------
sub handled_commands {
    return( {switchdiscover=>"switchdiscover"} );
}


#--------------------------------------------------------------------------------
=head3   parse_args
      Parse the command line options and operands.
    Arguments:
        request: the request structure for plugin
    Returns:
        Usage string or error message.
        0 if no user promp needed.

=cut
#--------------------------------------------------------------------------------
sub parse_args {

    my $request  = shift;
    my $args     = $request->{arg};
    my $cmd      = $request->{command};
    my %opt;

    #############################################
    # Responds with usage statement
    #############################################
    local *usage = sub {
        my $usage_string = xCAT::Usage->getUsage($cmd);
        return( [$_[0], $usage_string] );
    };
    #############################################
    # No command-line arguments - use defaults
    #############################################
    if ( !defined( $args )) {
        return(0);
    }
    #############################################
    # Checks case in GetOptions, allows opts
    # to be grouped (e.g. -vx), and terminates
    # at the first unrecognized option.
    #############################################
    @ARGV = @$args;
    $Getopt::Long::ignorecase = 0;
    Getopt::Long::Configure( "bundling" );

    #############################################
    # Process command-line flags
    #############################################
    if (!GetOptions( \%opt,
            qw(h|help V|Verbose v|version x z w r n range=s s=s))) {
        return( usage() );
    }

    #############################################
    # Check for node range
    #############################################
    if ( scalar(@ARGV) eq 1 ) {
        my @nodes = xCAT::NodeRange::noderange( @ARGV );
        if (nodesmissed) {
            return (usage( "The following nodes are not defined in xCAT DB:\n  " . join(',', nodesmissed)));
        }
        foreach (@nodes)  {
            push @filternodes, $_;
        }
        unless (@filternodes) {
            return(usage( "Invalid Argument: $ARGV[0]" ));
        }
        if ( exists( $opt{range} )) {
            return(usage( "--range flag cannot be used with noderange." ));
        }
    } elsif ( scalar(@ARGV) > 1 ) {
        return(usage( "Invalid flag, please check and retry." ));
    }

    #############################################
    # Option -V for verbose output
    #############################################
    if ( exists( $opt{V} )) {
        $globalopt{verbose} = 1;
    }

     #############################################
    # Check for mutually-exclusive formatting
    #############################################
    if ( (exists($opt{r}) + exists($opt{x}) + exists($opt{z}) ) > 1 ) {
        return( usage() );
    }

    #############################################
    # Check for unsupported scan types
    #############################################
    if ( exists( $opt{s} )) {
        my @stypes = split ',', $opt{s};
        my $error;
        foreach my $st (@stypes) {
            if (! exists($global_scan_type{$st})) {
                $error = $error . "Invalide scan type: $st\n";    
            }
        }
        if ($error) {
            return usage($error);
        }
        $globalopt{scan_types} = \@stypes; 
    }

    #############################################
    # Check the --range ip range option
    #############################################
    if ( exists( $opt{range} )) {
        $globalopt{range} = $opt{range};
        my @ips = split /,/, $opt{range};
        foreach my $ip (@ips)  {
            if (($ip =~ /^(\d{1,3})(-\d{1,3})?\.(\d{1,3})(-\d{1,3})?\.(\d{1,3})(-\d{1,3})?\.(\d{1,3})(-\d{1,3})?$/) || 
                ($ip =~ /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})\/(\d+)$/)) {
                push @iprange, $ip;
            } else {
                return usage("Invalid ip or ip range specified: $ip.");
            }
        }
    }

    #############################################
    # write to the database
    #############################################
    if ( exists( $opt{w} )) {
        $globalopt{w} = 1;
    }

    #############################################
    # list the raw information
    #############################################
    if ( exists( $opt{r} )) {
        $globalopt{r} = 1;
    }

    #############################################
    # list the xml formate data
    #############################################
    if ( exists( $opt{x} )) {
        $globalopt{x} = 1;
    }

    #############################################
    # list the stanza formate data
    #############################################
    if ( exists( $opt{z} )) {
        $globalopt{z} = 1;
    }


    #########################################################
    # only list the nodes that discovered for the first time
    #########################################################
    if ( exists( $opt{n} )) {
        $globalopt{n} = 1;
    }

    return;
}


#--------------------------------------------------------------------------------
=head3   preprocess_request
      Parse the arguments and display the usage or the version string. 

=cut
#--------------------------------------------------------------------------------
sub preprocess_request {
    my $req = shift;
    if ($req->{_xcatpreprocessed}->[0] == 1) { return [$req]; }
    my $callback=shift;
    my $command = $req->{command}->[0];
    my $extrargs = $req->{arg};
    my @exargs=($req->{arg});
    if (ref($extrargs)) {
        @exargs=@$extrargs;
    }
    my $usage_string=xCAT::Usage->parseCommand($command, @exargs);
    if ($usage_string) {
        $callback->({data=>[$usage_string]});
        $req = {};
        return;
    }

    my @result = ();
    my $mncopy = {%$req};
    push @result, $mncopy;
    return \@result;
}

#--------------------------------------------------------------------------------
=head3   process_request
    Pasrse the arguments and call the correspondent functions
    to do switch discovery. 

=cut
#--------------------------------------------------------------------------------
sub process_request {
    my $req      = shift;
    my $callback = shift;
    my $sub_req  = shift;
  
    ###########################################
    # Build hash to pass around
    ###########################################
    my %request;
    $request{arg}      = $req->{arg};
    $request{callback} = $callback;
    $request{command}  = $req->{command}->[0];

    ####################################
    # Process command-specific options
    ####################################
    my $result = parse_args( \%request );
    

    ####################################
    # Return error
    ####################################
    if ( ref($result) eq 'ARRAY' ) {
        send_msg( \%request, 1, @$result );
        return(1);
    }

    # call the relavant functions to start the scan 
    my @scan_types = ("nmap");
    if (exists($globalopt{scan_types})) {
        @scan_types = @{$globalopt{scan_types}};
    }
    
    my $all_result;
    foreach my $st (@scan_types) {
        no strict;
        my $fn = $global_scan_type{$st};
        my $tmp_result = &$fn(\%request, $callback);
        if (ref($tmp_result) eq 'HASH') {
            $all_result->{$st} = $tmp_result;
        }
    }

    #consolidate the results by merging the swithes with the same ip or same mac 
    #or same hostname
    my $result;
    my $merged;
    my $counter=0;
    foreach my $st (keys %$all_result) {
        my $tmp_result = $all_result->{$st};
        #send_msg( \%request, 1, Dumper($tmp_result));
        foreach my $old_mac (keys %$tmp_result) {
            $same = 0;
            foreach my $new_mac (keys %$result) {
                my $old_ip = $tmp_result->{$old_mac}->{ip}; 
                my $old_name = $tmp_result->{$old_mac}->{name};
                my $old_vendor = $tmp_result->{$old_mac}->{vendor};
                my $new_ip = $result->{$new_mac}->{ip};
                my $new_name = $result->{$new_mac}->{name};
                my $new_vendor = $result->{$new_mac}->{vendor};
                
                if (($old_mac eq $new_mac) || 
                    ($old_ip && ($old_ip eq $new_ip)) || 
                    ($old_name && ($old_name eq $new_name))) {
                    $same = 1;
                    my $key =$new_mac;
                    if ($new_mac =~ /nomac/) {
                        if ($old_mac =~ /nomac/) {
                            $key = "nomac_$counter";
                            $counter++;
                        } else {
                            $key = $old_mac;
                        }
                    }
                    if ($old_name) {
                        $result->{$key}->{name} = $old_name;
                    }
                    if ($old_ip) {
                        $result->{$key}->{ip} = $old_ip;
                    }
                    $result->{$key}->{vendor} = $new_vendor;
                    if ($old_vendor) {
                        if ($old_vendor ne $new_vendor) {
                            $result->{$key}->{vendor} .= " " . $old_vendor;
                        } else {
                            $result->{$key}->{vendor} = $old_vendor;
                        }
                    }

                    if ($key ne $new_mac) {
                        delete $result->{$new_mac};
                    }
                }
            }
            if (!$same) {
                $result->{$old_mac} = $tmp_result->{$old_mac};
            }
        }
    }
        
    my $display_done = 0;
    if (exists($globalopt{r}))  { 
        #do nothing since is done by the scan functions. 
        $display_done = 1;
    }
    
    if (exists($globalopt{x}))  {
            send_msg( \%request, 0, format_xml( $result ));
            $display_done = 1;
    }

    if (exists($globalopt{z}))  { 
            
            my $stanza_output = format_stanza( $result );
            send_msg( \%request, 0, $stanza_output );
        $display_done = 1;
    }

    if (!$display_done) {
        #display header
        $format = "%-12s\t%-18s\t%-20.20s\t%-12s";
        $header = sprintf $format, "ip", "name","vendor", "mac";
        send_msg(\%request, 0, $header);
        my $sep = "------------";
        send_msg(\%request, 0, sprintf($format, $sep, $sep, $sep, $sep ));
        
        #display switches one by one
        foreach my $key (keys(%$result)) {
            my $ip = "   ";
            my $vendor = "   ";
            my $mac = "        ";
            if (exists($result->{$key}->{ip})) {
                $ip = $result->{$key}->{ip};
            }
            my $name = get_hostname($result->{$key}->{name}, $ip);
            if (exists($result->{$key}->{vendor})) {
                $vendor = $result->{$key}->{vendor};
            }
            if ($key != /nomac/) {
                $mac = $key;
            }
            my $msg = sprintf $format, $ip, $name, $vendor, $key;
            send_msg(\%request, 0, $msg);
        }
    }


    # writes the data into xCAT db
    if (exists($globalopt{w})) {
        send_msg(\%request, 0, "Writing the data into xCAT DB....");
        xCATdB($result, \%request, $sub_req);
    }

    return;
}

#--------------------------------------------------------------------------------
=head3   lldp_scan
      Use lldpd to scan the subnets to do switch discovery.
    Arguments:
       request: request structure with callback pointer.
    Returns:
        A hash containing the swithes discovered. 
        Each element is a hash of switch attributes. For examples:
        {
           "AABBCCDDEEFA" =>{name=>"switch1", vendor=>"ibm", ip=>"10.1.2.3"},
           "112233445566" =>{name=>"switch2", vendor=>"cisco", ip=>"11.4.5.6"}
       } 
       returns 1 if there are errors occurred.
=cut
#--------------------------------------------------------------------------------
sub lldp_scan {
    my $request  = shift;

    send_msg($request, 0, "Discovering switches using lldp...");

    # get the PID of the currently running lldpd if it is running.
    if (exists($globalopt{verbose}))    {
        send_msg($request, 0, "...Checking if lldpd is up and running:\n  ps -ef | grep lldpd | grep -v grep | awk '{print \$2}'\n");
    }    
    my $pid;
    chomp($pid= `ps -ef | grep lldpd | grep -v grep | awk '{print \$2}'`);
    unless($pid){
        my $dcmd = "lldpd -c -s -e -f";
        #my $outref = xCAT::Utils->runcmd($dcmd, 0);
        #if ($::RUNCMD_RC != 0)
        #{
        #    send_msg($request, 1, "Could not start lldpd process. The command was: $dcmd" #);
        #    return 1;
        #}
        #xCAT::Utils->runcmd("sleep 30");
        send_msg($request, 1, "Warning: lldpd is not running. Please start it with the following flags:\n  $dcmd\nThen wait a few minutes before running switchdiscover command again.\n");
        return 1;
    }

    #now run the lldpcli to collect the data
    my $ccmd = "lldpcli show neighbors -f xml";
    if (exists($globalopt{verbose}))    {
        send_msg($request, 0, "...Discovering switches using lldpd:\n $ccmd\n");
    }

    my $result = xCAT::Utils->runcmd($ccmd, 0);
    if ($::RUNCMD_RC != 0)
    {
        send_msg($request, 1, "Could not start lldpd process. The command was: $ccmd" );
        return 1;
    }
    if (exists($globalopt{verbose}))    {
        send_msg($request, 0, "$result\n");
    }

    #display the raw output
    if (exists($globalopt{r})) {
        my $ccmd = "lldpcli show neighbors";
        my $raw_result = xCAT::Utils->runcmd($ccmd, 0);
        if ($::RUNCMD_RC == 0)
        {
            send_msg($request, 0, "$raw_result\n\n");
        }
    }


    if (exists($globalopt{verbose}))    {
        send_msg($request, 0, "...Converting XML output to hash.\n");
    }
    my $result_ref = XMLin($result, KeyAttr => 'interface', ForceArray => 1);
    my $switches; 
    my $counter=0;
    if ($result_ref) {
        if (exists($result_ref->{interface})) {
            my $ref1 = $result_ref->{interface};
            foreach my $interface (@$ref1) {
                if (exists($interface->{chassis})) {
                    my $chassis = $interface->{chassis}->[0];
                    my $name = $chassis->{name}->[0]->{content};
                    my $ip = $chassis->{'mgmt-ip'}->[0]->{content};
                    # resolve the ip from name
                    if (!$ip) {
                        if ($name) {
                            $ip = xCAT::NetworkUtils->getipaddr($name);
                        }
                    }
                    my $id =  $chassis->{id}->[0]->{content};
                    if (!$id) {
                        $id="nomac_lldp_$counter";
                        $counter++;
                    }
                    my $desc = $chassis->{descr}->[0]->{content};
                    if ($desc) {
                        $desc =~ s/\n/ /g;
                        $desc =~ s/\"//g;
                    }

                    if ($id) {
                        $switches->{$id}->{name} = $name;
                        $switches->{$id}->{ip} =  $ip;
                        $switches->{$id}->{vendor} = $desc;
                    }
                }
            }
        }
    }

    # filter out the uwanted entries if noderange or ip range is specified.
    if ((@filternodes> 0) || (@iprange>0)) {
        my $ranges = get_ip_ranges($request);
        if (exists($globalopt{verbose}))    {
            send_msg($request, 0, "...Removing the switches that are not within the following ranges:\n  @$ranges\n");
        }
        foreach my $mac (keys %$switches) {
            my $ip_r = $switches->{$mac}->{ip};
            $match = 0;
            foreach my $ip_f (@$ranges) {
                my ($net, $mask) = split '/', $ip_f;
                if ($mask) { #this is a subnet
                    $mask = xCAT::NetworkUtils::formatNetmask($mask, 1, 0);
                   if (xCAT::NetworkUtils->ishostinsubnet($ip_r, $mask, $net)) {
                        $match = 1;
                        last;
                    }
                } else { #this is an ip
                    if ($ip_r eq $net) {
                        $match = 1;
                        last;
                    }
                    #TODO: handles the case where the range is something like 10.2-3.4.5-6
                }
            }
            if (!$match) {
                delete $switches->{$mac};
            }
        }
    }

    return $switches
}


#--------------------------------------------------------------------------------
=head3   nmap_scan
      Use nmap to scan the subnets to do switch discovery.
    Arguments:
       request: request structure with callback pointer.
    Returns:
        A hash containing the swithes discovered. 
        Each element is a hash of switch attributes. For examples:
        {
           "AABBCCDDEEFA" =>{name=>"switch1", vendor=>"ibm", ip=>"10.1.2.3"},
           "112233445566" =>{name=>"switch2", vendor=>"cisco", ip=>"11.4.5.6"}
       } 
       returns 1 if there are errors occurred.
=cut
#--------------------------------------------------------------------------------
sub nmap_scan {
    my $request  = shift;

    my $ccmd;

    send_msg($request, 0, "Discovering switches using nmap. It may take long time...");
    #################################################
    # If --range options, take iprange, if noderange is defined
    # us the ip addresses of the nodes. If none is define, use the
    # subnets for all the interfaces.
    ##################################################
    my $ranges = get_ip_ranges($request);

    #warning the user if the range is too big
    foreach my $r (@$ranges) {
        if ($r =~ /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})\/(\d+)$/) {
            if ($5 < 24) {
                send_msg($request, 0, "You can modify the --range parameters to cut down the time.\n" );
                last;
            }
        }
    }

    $ccmd = "/usr/bin/nmap -sP -oX - @$ranges";
    my $result = xCAT::Utils->runcmd($ccmd, 0);
    if ($::RUNCMD_RC != 0)
    {
        send_msg($request, 1, "Could not process this command: $ccmd" );
        return 1;
    }

    #################################################
    #display the raw output
    #################################################
    if (exists($globalopt{r})) {
        send_msg($request, 0, "$result\n" );
    }

    #################################################
    #compose the switch hash 
    #################################################
    my $result_ref = XMLin($result, ForceArray => 1);
    my $switches;
    my $found;
    my $counter=0;
    if ($result_ref) {
        if (exists($result_ref->{host})) {
            my $host_ref = $result_ref->{host};
            foreach my $host ( @$host_ref ) {
                my $ip;
                my $mac;
                if (exists($host->{address})) {
                    my $addr_ref = $host->{address};
                    foreach my $addr ( @$addr_ref ) {
                        my $type = $addr->{addrtype};
                        if ( $type ne "mac" ) {
                            $ip = $addr->{addr};
                            $found = 0;
                        } else {
                            $mac = $addr->{addr};
                        }
                        if (!$mac) {
                            $mac="nomac_nmap_$counter";
                            $counter++;
                        }
                        if ($addr->{vendor}) {
                            my $search_string = join '|', keys(%global_switch_type);
                            if ($addr->{vendor} =~ /($search_string)/) {
                                $switches->{$mac}->{ip} = $ip;
                                $switches->{$mac}->{vendor} = $addr->{vendor};
                                $switches->{$mac}->{name} = $host->{hostname};
                                $found = 1;
                            }
                        } 
                        ##########################################################
                        # If there is no vendor or other than %global_switch_type,
                        # issue the nmap again to do more aggresively discovery
                        # Choose best guess from osscan
                        # only search port 22 and 23 for fast performance
                        ###########################################################
                        if ( ($found == 0) && ($type eq "mac") ) {
                            $ccmd = "/usr/bin/nmap -O --osscan-guess -A -p 22,23 -oX - $ip | grep osclass | grep switch | grep -v embedded ";
                            my $os_result = xCAT::Utils->runcmd($ccmd, 0);
                            if ($::RUNCMD_RC == 0)
                            {
                                if ($os_result =~ /vendor=\"(\S*)\"/) {
                                    my $vendor_name = $1;
                                    $switches->{$mac}->{ip} = $ip;
                                    $switches->{$mac}->{vendor} = $vendor_name;
                                    $switches->{$mac}->{name} = $host->{hostname};
                                    $found = 1;
                                }
                            }
                        } # end nmap osscan command
                    } #end for each address
                }
            } #end for each host
        }
    }

    return $switches
}



#--------------------------------------------------------------------------------
=head3   snmp_scan
      Use lldpd to scan the subnets to do switch discovery.
    Arguments:
       request: request structure with callback pointer.
    Returns:
        A hash containing the swithes discovered. 
        Each element is a hash of switch attributes. For examples:
        {
           "AABBCCDDEEFA" =>{name=>"switch1", vendor=>"ibm", ip=>"10.1.2.3"},
           "112233445566" =>{name=>"switch2", vendor=>"cisco", ip=>"11.4.5.6"}
       } 
       returns 1 if there are errors occurred.
=cut
#--------------------------------------------------------------------------------
sub snmp_scan {
    my $request  = shift;

    send_msg($request, 0, "Discovering switches using snmp...");
    my $switches = {
        "AABBCCDDEEFA" =>{name=>"switch1", vendor=>"ibm", ip=>"10.1.2.3"},
        "112233445566" =>{name=>"switch2", vendor=>"cisco", ip=>"11.4.5.6"}
     };
    return $switches
}

#--------------------------------------------------------------------------------
=head3   get_hostname 
      return hostname for the switch discovered
    Arguments:
      host:  hostname passed by the switch after scan
      ip  :  IP address passed by the switch after scan
    Returns:
      hose:  hostname of the switch
      if host is empty, try to lookup use ip address, otherwise format hostname 
      as switch and ip combination. ex:  switch_9_114_5_6
=cut
#--------------------------------------------------------------------------------
sub get_hostname {
    my $host = shift;
    my $ip = shift;

    if ( !$host ) {
        $host = gethostbyaddr( inet_aton($ip), AF_INET );
        if ( !$host ) {
            my $ip_str = $ip;
            $ip_str =~ s/\./\_/g;
            $host = "switch_$ip_str";
        }
    }
    return $host;
}

#--------------------------------------------------------------------------------
=head3   get_switchtype
      determine the switch type based on the switch vendor
    Arguments:
      vendor: switch vendor 
    Returns:
      stype: type of switch, supports Jun, Cisco, BNT and Mellanox 
=cut
#--------------------------------------------------------------------------------
sub get_switchtype {
    my $vendor = shift;
    my $key;
    
    my $search_string = join '|', keys(%global_switch_type);
    if ($vendor =~ /($search_string)/) {
        $key = $1;
        return $global_switch_type{$key};
    } else {
        return vendor;
    }
}

#--------------------------------------------------------------------------------
=head3  xCATdB
      Write discovered switch information to xCAT database.
    Arguments:
       outhash: A hash containing the swithes discovered.
       request: The request structure for plugin.
       sub_req: The request structure for runxcmd.
    Returns:
       none
=cut
#--------------------------------------------------------------------------------
sub xCATdB {
    my $outhash = shift;
    my $request = shift;
    my $sub_req = shift;
    my $ret;

    #################################################
    # write each switch to xcat database
    ##################################################
    foreach my $mac ( keys %$outhash ) {
        my $ip = $outhash->{$mac}->{ip};
        my $vendor = $outhash->{$mac}->{vendor};

        #Get hostname and switch type
        my $host = get_hostname($outhash->{$mac}->{name}, $ip);
        my $stype = get_switchtype($vendor);
        if ($mac =~ /nomac/) {
            $mac=" ";
        }


        #################################################
        # use lsdef command to check if this switch is
        # already in the switch table
        # if it is, use chdef to update it's attribute
        # otherwise, use mkdef to add this switch to
        # switch table
        ##################################################
        $ret = xCAT::Utils->runxcmd( { command => ['lsdef'], arg => ['-t','switch','-o',$host] }, $sub_req, 0, 1);
        if ($::RUNCMD_RC == 0)
        {
            $ret = xCAT::Utils->runxcmd({ command => ['chdef'], arg => ['-t','switch','-o',$host,"ip=$ip","comments=$vendor",'nodetype=switch','mgt=switch',"switchtype=$stype"] }, $sub_req, 0, 1);
        } else {
            $ret = xCAT::Utils->runxcmd( { command => ['mkdef'], arg => ['-t','switch','-o',$host,'groups=switch',"ip=$ip","comments=$vendor",'nodetype=switch','mgt=switch',"switchtype=$stype"] }, $sub_req, 0, 1);
        }
        if ($::RUNCMD_RC != 0)
        {
            send_msg($request, 0, "$$ret[0]");
        }
    }
}

#--------------------------------------------------------------------------------
=head3  get_ip_ranges
      Return the an array of ip ranges. If --range is specified, use it. If
      noderange is specified, use the ip address of the nodes. Otherwise, use 
      the subnets for all the live nics on the xCAT mn. 
    Arguments:
       request: request structure with callback pointer.
    Returns:
        A pointer of an array of ip ranges.
=cut
#--------------------------------------------------------------------------------
sub get_ip_ranges {
    $request = shift;

    # if --range is defined, just return the ranges specified by the user
    if (@iprange > 0) {
        return \@iprange;
    }

    # if noderange is defined, then put the ip addresses of the nodes in
    if (@filternodes > 0) {
        my @ipranges=();
        foreach my $node (@filternodes) {
            my $ip = xCAT::NetworkUtils->getipaddr($node);
            push(@ipranges, $ip);
        }
        return \@ipranges;
    }

    # for default, use the subnets for all the live nics on the mn
    my $nets = xCAT::NetworkUtils->my_nets();
    my $ranges=[];
    foreach my $net (keys %$nets) {
        if ($net !~ /127\.0\.0\.0/) {
            push(@$ranges, $net);
        }
    }

    return $ranges;
    
}

#-------------------------------------------------------------------------------
=head3  format_stanza 
      list the stanza format for swithes
    Arguments:
      outhash: a hash containing the switches discovered 
    Returns:
      result: return lists as stanza format for swithes 
=cut
#--------------------------------------------------------------------------------
sub format_stanza {
    my $outhash = shift;
    my $result;

    #####################################
    # Write attributes
    #####################################
    foreach my $mac ( keys %$outhash ) {
        my $ip = $outhash->{$mac}->{ip};
        my $vendor = $outhash->{$mac}->{vendor};

        #Get hostname and switch type
        my $host = get_hostname($outhash->{$mac}->{name}, $ip);
        my $stype = get_switchtype($vendor);
        if ($mac =~ /nomac/) {
            $mac = " ";
        }

        $result .= "$host:\n\tobjtype=switch\n";
        $result .= "\tcomments=$vendor\n";
        $result .= "\tgroups=switch\n";
        $result .= "\tip=$ip\n";
        $result .= "\tmac=$mac\n";
        $result .= "\tmgt=switch\n";
        $result .= "\tnodetype=switch\n";
        $result .= "\tswitchtype=$stype\n";
    }
    return ($result);
}

#--------------------------------------------------------------------------------
=head3  format_xml 
      list the xml format for swithes
    Arguments:
      outhash: a hash containing the switches discovered 
    Returns:
      result: return lists as xml format for swithes 
=cut
#--------------------------------------------------------------------------------
sub format_xml {
    my $outhash = shift;
    my $xml;

    #####################################
    # Write attributes
    #####################################
    foreach my $mac ( keys %$outhash ) {
        my $result;
        my $ip = $outhash->{$mac}->{ip};
        my $vendor = $outhash->{$mac}->{vendor};
        
        #Get hostname and switch type
        my $host = get_hostname($outhash->{$mac}->{name}, $ip);
        my $stype = get_switchtype($vendor);
        if ($mac =~ /nomac/) {
            $mac = " ";
        }

        $result .= "hostname=$host\n";
        $result .= "objtype=switch\n";
        $result .= "comments=$vendor\n";
        $result .= "groups=switch\n";
        $result .= "ip=$ip\n";
        $result .= "mac=$mac\n";
        $result .= "mgt=switch\n";
        $result .= "nodetype=switch\n";
        $result .= "switchtype=$stype\n";

        my $href = {
            Switch => { }
        };
        my @attr = split '\\n', $result;
        for (my $i = 0; $i < scalar(@attr); $i++ ){
            if( $attr[$i] =~ /(\w+)\=(.*)/){
                $href->{Switch}->{$1} = $2;
            }
        }
        $xml.= XMLout($href,
                     NoAttr   => 1,
                     KeyAttr  => [],
                     RootName => undef );
    }
    return ($xml);    
}

1;

