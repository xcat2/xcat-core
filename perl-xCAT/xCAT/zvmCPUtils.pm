# IBM(c) 2013 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head1

    This is a CP utility plugin for z/VM.

=cut

#-------------------------------------------------------
package xCAT::zvmCPUtils;
use xCAT::zvmUtils;
use strict;
use warnings;
1;

#-------------------------------------------------------

=head3   getUserId

    Description : Get the user ID of a given node
    Arguments   :   User (root or non-root)
                    Node
    Returns     : UserID
    Example     : my $userID = xCAT::zvmCPUtils->getUserId($node);

=cut

#-------------------------------------------------------
sub getUserId {

    # Get inputs
    my ( $class, $user, $node ) = @_;

    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }

    # Get user ID using VMCP
    #my $out     = `ssh -o ConnectTimeout=5 $user\@$node "$sudo /sbin/vmcp q userid"`;
    my $cmd = "$sudo /sbin/vmcp q userid";
    my $out = xCAT::zvmUtils->execcmdonVM($user, $node, $cmd); # caller sets $user to $::SUDOER
    if (xCAT::zvmUtils->checkOutput($out) == -1) {
        return $out;
    }
    my @results = split( ' ', $out );

    return ( $results[0] );
}

#-------------------------------------------------------

=head3   getHost

    Description : Get the z/VM host of a given node
    Arguments   :   User (root or non-root)
                    Node
    Returns     : z/VM host
    Example     : my $host = xCAT::zvmCPUtils->getHost($node);

=cut

#-------------------------------------------------------
sub getHost {

    # Get inputs
    my ( $class, $user, $node ) = @_;

    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }

    # Get host using VMCP
    #my $out     = `ssh -o ConnectTimeout=5 $user\@$node "$sudo /sbin/vmcp q userid"`;
    my $cmd = "$sudo /sbin/vmcp q userid";
    my $out = xCAT::zvmUtils->execcmdonVM($user, $node, $cmd); # caller sets $user to $::SUDOER
    if (xCAT::zvmUtils->checkOutput($out) == -1) {
        return $out;
    }
    my @results = split( ' ', $out );
    my $host    = $results[2];

    return ($host);
}

#-------------------------------------------------------

=head3   getPrivileges

    Description : Get the privilege class of a given node
    Arguments   :   User (root or non-root)
                    Node
    Returns     : Privilege class
    Example     : my $class = xCAT::zvmCPUtils->getPrivileges($node);

=cut

#-------------------------------------------------------
sub getPrivileges {

    # Get inputs
    my ( $class, $user, $node ) = @_;

    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }

    # Get privilege class
    #my $out = `ssh -o ConnectTimeout=5 $user\@$node "$sudo /sbin/vmcp q priv"`;
    my $cmd = "$sudo /sbin/vmcp q priv";
    my $out = xCAT::zvmUtils->execcmdonVM($user, $node, $cmd); # caller sets $user to $::SUDOER
    if (xCAT::zvmUtils->checkOutput($out) == -1) {
        return $out;
    }
    my @out = split( '\n', $out );
    $out[1] = xCAT::zvmUtils->trimStr( $out[1] );
    $out[2] = xCAT::zvmUtils->trimStr( $out[2] );
    my $str = "    $out[1]\n    $out[2]\n";

    return ($str);
}

#-------------------------------------------------------

=head3   getMemory

    Description : Get the memory of a given node
    Arguments   :   User (root or non-root)
                    Node
    Returns     : Memory
    Example     : my $memory = xCAT::zvmCPUtils->getMemory($user, $node);

=cut

#-------------------------------------------------------
sub getMemory {

    # Get inputs
    my ( $class, $user, $node ) = @_;

    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }

    # Get memory
    #my $out = `ssh -o ConnectTimeout=5 $user\@$node "$sudo /sbin/vmcp q virtual storage"`;
    my $cmd = "$sudo /sbin/vmcp q virtual storage";
    my $out = xCAT::zvmUtils->execcmdonVM($user, $node, $cmd); # caller sets $user to $::SUDOER
    if (xCAT::zvmUtils->checkOutput($out) == -1) {
        return $out;
    }
    my @out = split( ' ', $out );

    return ( xCAT::zvmUtils->trimStr( $out[2] ) );
}



#-------------------------------------------------------

=head3   getCpu

    Description : Get the processor(s) of a given node
    Arguments   :   User (root or non-root)
                    Node
    Returns     : Processor(s)
    Example     : my $proc = xCAT::zvmCPUtils->getCpu( $user, $node );

=cut

#-------------------------------------------------------
sub getCpu {

    # Get inputs
    my ( $class, $user, $node ) = @_;

    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }

    # Get processors
    #my $out = `ssh -o ConnectTimeout=5 $user\@$node "$sudo /sbin/vmcp q virtual cpus"`;
    my $cmd = "$sudo /sbin/vmcp q virtual cpus";
    my $out = xCAT::zvmUtils->execcmdonVM($user, $node, $cmd); # caller sets $user to $::SUDOER
    if (xCAT::zvmUtils->checkOutput($out) == -1) {
        return $out;
    }
    my $str = xCAT::zvmUtils->tabStr($out);

    return ($str);
}

#-------------------------------------------------------

=head3   getNic

    Description : Get the network interface card (NIC) of a given node
    Arguments   :   User (root or non-root)
                    Node
    Returns     : NIC(s)
    Example     : my $nic = xCAT::zvmCPUtils->getNic($node);

=cut

#-------------------------------------------------------
sub getNic {

    # Get inputs
    my ( $class, $user, $node ) = @_;

    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }

    # Get NIC
    #my $out = `ssh -o ConnectTimeout=5 $user\@$node "$sudo /sbin/vmcp q virtual nic"`;
    my $cmd = "$sudo /sbin/vmcp q virtual nic";
    my $out = xCAT::zvmUtils->execcmdonVM($user, $node, $cmd); # caller sets $user to $::SUDOER
    if (xCAT::zvmUtils->checkOutput($out) == -1) {
        return $out;
    }
    my $str = xCAT::zvmUtils->tabStr($out);

    return ($str);
}

#-------------------------------------------------------

=head3   getNetworkNames

    Description : Get a list of network names available to a given node
    Arguments   :   User (root or non-root)
                    Node
    Returns     : Network names
    Example     : my $lans = xCAT::zvmCPUtils->getNetworkNames($user, $node);

=cut

#-------------------------------------------------------
sub getNetworkNames {

    # Get inputs
    my ( $class, $user, $node ) = @_;

    # Directory where executables are
    my $dir = '/opt/zhcp/bin';
    my $hcp;
    my $hcpUserId;
    # Get node properties from 'zvm' table
    my @propNames = ( 'hcp', 'userid' );
    my $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $node, @propNames );

    # Get zHCP. If not propVals then the node is probably a zhcp
    if (!$propVals) {
       $hcpUserId = xCAT::zvmCPUtils->getUserId($::SUDOER, $node);
       $hcpUserId =~ tr/a-z/A-Z/;
       $hcp = $node;
    } else {
       $hcp = $propVals->{'hcp'};
       $hcpUserId = xCAT::zvmCPUtils->getUserId($::SUDOER, $hcp);
       $hcpUserId =~ tr/a-z/A-Z/;
    }

    if ( !$hcpUserId ) {
           xCAT::zvmUtils->printSyslog("$node: (Error) Missing node HCP. Userid: $hcpUserId");
           return ("$node: (Error) Missing node HCP. Userid: $hcpUserId");
    }

    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }

    # Get network names
    my $out;
    my $outmsg;
    my $names;
    my $count;
    my @parms;
    my @lines;
    my $switchNamesFound = "";
    my $start = 0;
    my $switchName;
    my $lanType;
    my $lanName;
    my $lanOwner;
    my $rc;

    #If this is zhcp then use SMAPI calls to get network names; otherwise use q lan
    if (!$propVals) {
        my $retStr;
        # First get the VSWITCH information, saving the switch name
        xCAT::zvmUtils->printSyslog("ssh $user\@$hcp $sudo $dir/smcli Virtual_Network_Vswitch_Query_Extended -T $hcpUserId -k 'switch_name=*'");
        $out = `ssh $user\@$hcp "$sudo $dir/smcli Virtual_Network_Vswitch_Query_Extended -T $hcpUserId -k 'switch_name=*'"`;
        $rc = $? >> 8;
        if ($rc == 255) {
           $retStr = "(Error) Failed to communicate with the zhcp system: $hcpUserId";
           xCAT::zvmUtils->printSyslog($retStr);
           return $retStr;
        } elsif ($rc) {
           $retStr = "(Error) Error trying to execute smcli Virtual_Network_Vswitch_Query_Extended. rc:$rc Output:$out";
           xCAT::zvmUtils->printSyslog($retStr);
           return $retStr;
        }
        if ( $out =~ m/Failed/i ) {
           xCAT::zvmUtils->printSyslog($out);
           return ($out);
        }
        @lines = split( '\n', $out );
        # Just get the lines with "switch_name"
        @lines = grep /switch_name/, @lines;
        $count = @lines;

        # Grep output is 1 line for each item
        for (my $i=0; $i < $count; $i++) {
           @parms = split( ' ', $lines[$i]);
           $switchName = $parms[1];
           $switchNamesFound .= "+" . $switchName . "+";
           $names .= "VSWITCH" . " " . "SYSTEM" . " " . $switchName . "\n";
        }

        # Next get the LAN information, skipping switches we have
        xCAT::zvmUtils->printSyslog("ssh $user\@$hcp $sudo $dir/smcli Virtual_Network_LAN_Query -T $hcpUserId -n '*' -o '*'");
        $out = `ssh $user\@$hcp "$sudo $dir/smcli Virtual_Network_LAN_Query -T $hcpUserId -n '*' -o '*'"`;
        $rc = $? >> 8;
        if ($rc == 255) {
           $retStr = "(Error) Failed to communicate with the zhcp system: $hcpUserId";
           xCAT::zvmUtils->printSyslog($retStr);
           return $retStr;
        } elsif ($rc) {
           $retStr = "(Error) Error trying to execute smcli Virtual_Network_LAN_Query. rc:$rc Output:$out";
           xCAT::zvmUtils->printSyslog($retStr);
           return $retStr;
        }
        if ( $out =~ m/Failed/i ) {
           xCAT::zvmUtils->printSyslog($out);
           return ($out);
        }
        @lines = split( '\n', $out );
        # Just get the lines with "Name:|Owner:|LAN type:"
        @lines = grep /Name:|Owner:|LAN type:/, @lines;
        $count = @lines;

        # Grep output is 3 lines for each item
        for (my $i=0; $i < ($count/3); $i++) {
            @parms = split( ' ', $lines[$start]);
            $lanName = $parms[1];
            $start++;
            @parms = split(' ', $lines[$start]);
            $lanOwner = $parms[1];
            $start++;
            if ( $lines[$start] =~ m/QDIO/i ) {
                $lanType = ":QDIO ";
            } else {
                $lanType = ":HIPERS ";
            }
            $start++;
            # Skip any lanNames that were found by VSWITCH query
            my $search = "+$lanName+";
            if (index($switchNamesFound, $search) == -1) {
                $names .= "LAN" . $lanType . $lanOwner . " " . $lanName . "\n";
            }
        }
    # use vmcp q lan if this is not the zhcp node
    } else {
        #$out = `ssh -o ConnectTimeout=5 $user\@$node "$sudo /sbin/vmcp q lan | egrep 'LAN|VSWITCH'"`;
        my $cmd = $sudo . ' /sbin/vmcp q lan';
        $out = xCAT::zvmUtils->execcmdonVM($user, $node, $cmd); # caller sets $user to $::SUDOER
        if (xCAT::zvmUtils->checkOutput($out) == -1) {
            return $out;
        }
        $out = `echo "$out" | egrep -a -i 'LAN|VSWITCH'`;
        @lines = split( '\n', $out );

        foreach (@lines) {

            # Trim output
            $_     = xCAT::zvmUtils->trimStr($_);
            @parms = split( ' ', $_ );

            # sample output from q lan
            # LAN SYSTEM GLAN1        Type: QDIO    Connected: 1    Maxconn: INFINITE
            # VSWITCH SYSTEM XCATVSW1 Type: QDIO    Connected: 2    Maxconn: INFINITE
            # Get the network name
            if ( $parms[0] eq "LAN" ) {

                # Determine if this network is a hipersocket
                # Only hipersocket guest LANs are supported
                if ( $_ =~ m/Type: HIPERS/i ) {
                    $names .= $parms[0] . ":HIPERS " . $parms[1] . " " . $parms[2] . "\n";
                } else {
                    $names .= $parms[0] . ":QDIO " . $parms[1] . " " . $parms[2] . "\n";
                }
            } elsif ( $parms[0] eq "VSWITCH" ) {
                 $names .= $parms[0] . " " . $parms[1] . " " . $parms[2] . "\n";
            }
        }
    }

    return ($names);
}

#-------------------------------------------------------

=head3   getNetworkNamesArray

    Description : Get an array of network names available to a given node
    Arguments   :   User (root or non-root)
                    Node
    Returns     : Array of networks names
    Example     : my @networks = xCAT::zvmCPUtils->getNetworkNamesArray($user, $node);

=cut

#-------------------------------------------------------
sub getNetworkNamesArray {

    # Get inputs
    my ( $class, $user, $node ) = @_;
    my @networks;
    my %netHash;

    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }

    # Get the networks used by the node
    #my $out   = `ssh $user\@$node "$sudo /sbin/vmcp q v nic" | egrep -i "VSWITCH|LAN"`;
    my $cmd = $sudo . ' /sbin/vmcp q v nic';
    my $out = xCAT::zvmUtils->execcmdonVM($user, $node, $cmd); # caller sets $user to $::SUDOER
    if (xCAT::zvmUtils->checkOutput($out) == -1) {
        return $out;
    }
    $out = `echo "$out" | egrep -a -i 'VSWITCH|LAN'`;
    my @lines = split( '\n', $out );

    # Loop through each line
    my $line;
    my @words;
    my $name;
    foreach(@lines) {
        # Get network name
        # Line should contain: MAC: 02-00-01-00-00-12 VSWITCH: SYSTEM VSW1
        $line = xCAT::zvmUtils->trimStr( $_ );
        @words = split( ' ', $line );
        if (@words) {
            $name = xCAT::zvmUtils->trimStr( $words[4] );

            # If network is not 'None'
            if ($name ne 'None') {
                # Save network
                $netHash{$name} = 1;
            }
        }
    }

    # Push networks into array
    foreach $name ( keys %netHash ) {
        push(@networks, $name);
    }

    return @networks;
}

#-------------------------------------------------------

=head3   getNetwork

    Description : Get the network info for a given node
    Arguments   :   User (root or non-root)
                    Node
                    Network name
    Returns     : Network configuration
    Example     : my $config = xCAT::zvmCPUtils->getNetwork($node, $netName);

=cut

#-------------------------------------------------------
sub getNetwork {

    # Get inputs
    my ( $class, $user, $node, $netName, $netType ) = @_;

    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }

    # Directory where executables are
    my $dir = '/opt/zhcp/bin';
    my $hcp;
    my $hcpUserId;
    my $out;
    my $retStr;
    my $rc;

    my $netNameQuery = $netName;
    if ($netName eq "all") {
       $netNameQuery = "*";
    }

    xCAT::zvmUtils->printSyslog("getNetwork for NetType:$netType NetName:$netName NetNameQuery:$netNameQuery");

    # Get node properties from 'zvm' table
    my @propNames = ( 'hcp', 'userid' );
    my $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $node, @propNames );

    # Get zHCP. If not propVals then the node is probably a zhcp
    if (!$propVals) {
       $hcpUserId = xCAT::zvmCPUtils->getUserId($::SUDOER, $node);
       $hcpUserId =~ tr/a-z/A-Z/;
       $hcp = $node;
    } else {
       $hcp = $propVals->{'hcp'};
       $hcpUserId = xCAT::zvmCPUtils->getUserId($::SUDOER, $hcp);
       $hcpUserId =~ tr/a-z/A-Z/;
    }

    if ( !$hcpUserId ) {
           xCAT::zvmUtils->printSyslog("$node: (Error) Missing node HCP. Userid: $hcpUserId");
           return ("$node: (Error) Missing node HCP. Userid: $hcpUserId");
    }

    #If this is zhcp then use SMAPI calls to get network names; otherwise use q lan
    if (!$propVals) {
        # If this is a vswitch, use: Virtual_Network_Vswitch_Query_Extended
        if (index($netType, "VSWITCH") >= 0) {
            xCAT::zvmUtils->printSyslog("ssh $user\@$hcp $sudo $dir/smcli Virtual_Network_Vswitch_Query_Extended -T $hcpUserId -k 'switch_name='$netNameQuery -k 'VEPA_STATUS=YES'");
            $out = `ssh $user\@$hcp "$sudo $dir/smcli Virtual_Network_Vswitch_Query_Extended -T $hcpUserId -k 'switch_name='$netNameQuery -k 'VEPA_STATUS=YES'"`;
            $rc = $? >> 8;
            if ($rc == 255) {
               $retStr = "(Error) Failed to communicate with the zhcp system: $hcpUserId";
               xCAT::zvmUtils->printSyslog($retStr);
               return $retStr;
            } elsif ($rc) {
               $retStr = "(Error) Error trying to execute smcli Virtual_Network_Vswitch_Query_Extended. rc:$rc Output:$out";
               xCAT::zvmUtils->printSyslog($retStr);
               return $retStr;
            }
            if ( $out =~ m/Failed/i ) {
               xCAT::zvmUtils->printSyslog($out);
            }
        } else {
            # Get the LAN information
            xCAT::zvmUtils->printSyslog("ssh $user\@$hcp $sudo $dir/smcli Virtual_Network_LAN_Query -T $hcpUserId -n $netNameQuery -o '*'");
            $out = `ssh $user\@$hcp "$sudo $dir/smcli Virtual_Network_LAN_Query -T $hcpUserId -n $netNameQuery -o '*' "`;
            $rc = $? >> 8;
            if ($rc == 255) {
               $retStr = "(Error) unable to communicate with the zhcp system: $hcpUserId";
               xCAT::zvmUtils->printSyslog($retStr);
               return $retStr;
            } elsif ($rc) {
               $retStr = "(Error) Error trying to execute smcli Virtual_Network_LAN_Query. rc:$rc Output:$out";
               xCAT::zvmUtils->printSyslog($retStr);
               return $retStr;
            }
            if ( $out =~ m/Failed/i ) {
               xCAT::zvmUtils->printSyslog($out);
            }
        }
    # if not zhcp use q lan output
    } else {
       # Get network info.
       if ( $netName eq "all" ) {
           #$out = `ssh -o ConnectTimeout=5 $user\@$node "$sudo /sbin/vmcp q lan"`;
           my $cmd = "$sudo /sbin/vmcp q lan";
           $out = xCAT::zvmUtils->execcmdonVM($user, $node, $cmd); # caller sets $user to $::SUDOER
           if (xCAT::zvmUtils->checkOutput($out) == -1) {
               return $out;
           }
       } else {
           #$out = `ssh -o ConnectTimeout=5 $user\@$node "$sudo /sbin/vmcp q lan $netName"`;
           my $cmd = "$sudo /sbin/vmcp q lan $netName";
           $out = xCAT::zvmUtils->execcmdonVM($user, $node, $cmd); # caller sets $user to $::SUDOER
           if (xCAT::zvmUtils->checkOutput($out) == -1) {
               return $out;
           }
       }
    }

    return ($out);
}

#-------------------------------------------------------

=head3   getDisks

    Description : Get the disk(s) of given node
    Arguments   :   User (root or non-root)
                    Node
    Returns     : Disk(s)
    Example     : my $storage = xCAT::zvmCPUtils->getDisks($node);

=cut

#-------------------------------------------------------
sub getDisks {

    # Get inputs
    my ( $class, $user, $node ) = @_;

    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }

    # Get disks
    #my $out = `ssh -o ConnectTimeout=5 $user\@$node "$sudo /sbin/vmcp q virtual dasd"`;
    my $cmd = "$sudo /sbin/vmcp q virtual dasd";
    my $out = xCAT::zvmUtils->execcmdonVM($user, $node, $cmd); # caller sets $user to $::SUDOER
    if (xCAT::zvmUtils->checkOutput($out) == -1) {
        return $out;
    }
    my $str = xCAT::zvmUtils->tabStr($out);

    return ($str);
}

#-------------------------------------------------------

=head3   loadVmcp

    Description : Load Linux VMCP module on a given node
    Arguments   :   User (root or non-root)
                    Node
    Returns     : Nothing, or error string

    Example     : xCAT::zvmCPUtils->loadVmcp($node);

=cut

#-------------------------------------------------------
sub loadVmcp {

    # Get inputs
    my ( $class, $user, $node ) = @_;

    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }

    # Load Linux VMCP module
    my $cmd = "$sudo /sbin/modprobe vmcp";
    my $out = xCAT::zvmUtils->execcmdonVM($user, $node, $cmd); # caller sets $user to $::SUDOER
}

#-------------------------------------------------------

=head3   getVswitchId

    Description : Get the VSwitch ID(s) of given node
    Arguments   :   User (root or non-root)
                    Node
    Returns     : VSwitch ID(s)
    Example     : my @vswitch = xCAT::zvmCPUtils->getVswitchId($node);

=cut

#-------------------------------------------------------
sub getVswitchId {

    # Get inputs
    my ( $class, $user, $node ) = @_;

    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }

    # Get VSwitch
    #my $out = `ssh -o ConnectTimeout=5 $user\@$node "$sudo /sbin/vmcp q v nic" | grep "VSWITCH"`;
    my $cmd = $sudo . ' /sbin/vmcp q v nic';
    my $out = xCAT::zvmUtils->execcmdonVM($user, $node, $cmd); # caller sets $user to $::SUDOER
    if (xCAT::zvmUtils->checkOutput($out) == -1) {
        return $out;
    }
    $out = `echo "$out" | egrep -a -i 'VSWITCH'`;
    my @lines = split( '\n', $out );
    my @parms;
    my @vswitch;
    foreach (@lines) {
        @parms = split( ' ', $_ );
        push( @vswitch, $parms[4] );
    }

    return @vswitch;
}

#-------------------------------------------------------

=head3   grantVSwitch

    Description : Grant VSwitch access for a given userID
    Arguments   :   User (root or non-root)
                    zHCP
                    User ID
                    VSWITCH ID
                    lan port type ( or '')
                    vlan id (or '')
    Returns     : Operation results (Done/Failed)
    Example     : my $out = xCAT::zvmCPUtils->grantVswitch($callback, $hcp, $userId, $vswitchId, [$vlanporttype, $vlanid]);

=cut

#-------------------------------------------------------
sub grantVSwitch {

    # Get inputs
    my ( $class, $callback, $user, $hcp, $userId, $vswitchId, $vlanporttype, $vlanid ) = @_;

    # Directory where executables are
    my $dir = '/opt/zhcp/bin';

    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }

    my $lanidparm = '';
    if ($vlanporttype ne "") {
        $lanidparm = " -k \'port_type=" + $vlanporttype + "\'";
    }
    if ($vlanid ne "") {
        $lanidparm += " -k \'user_vlan_id=" + $vlanid + "\'";
    }

    # Use SMAPI EXEC, use new extended SMAPI vs old one
    # my $out = `ssh $user\@$hcp "$sudo $dir/smcli Virtual_Network_Vswitch_Set -T SYSTEM -n $vswitchId -I $userId -u 2"`;
    # xCAT::zvmUtils->printSyslog("grantVSwitch- ssh $user\@$hcp $sudo $dir/smcli Virtual_Network_Vswitch_Set -T SYSTEM -n $vswitchId -I $userId -u 2");
    xCAT::zvmUtils->printSyslog( "grantVSwitch- ssh $user\@$hcp $sudo $dir/smcli Virtual_Network_Vswitch_Set_Extended -T SYSTEM -k 'switch_name='$vswitchId -k 'grant_userid='$userId -k 'persist=YES '$lanidparm" );
    my $out = `ssh $user\@$hcp "$sudo $dir/smcli Virtual_Network_Vswitch_Set_Extended -T SYSTEM -k 'switch_name='$vswitchId -k 'grant_userid='$userId -k 'persist=YES' $lanidparm"`;

    $out = xCAT::zvmUtils->trimStr($out);

    # If return string contains 'Done' - Operation was successful
    my $retStr;
    if ( $out =~ m/Done/i ) {
        $retStr = "Done\n";
    } else {
        $retStr = "Failed " . "Error output: $out\n";
         xCAT::zvmUtils->printSyslog("Error output: $out");
        return $retStr;
    }

    return $retStr;
}

=head3   revokeVSwitch

    Description : Revoke VSwitch access for a given userID
    Arguments   :   User (root or non-root)
                    zHCP
                    User ID
                    VSWITCH ID
    Returns     : Operation results (Done/Failed)
    Example     : my $out = xCAT::zvmCPUtils->revokeVswitch($callback, $hcp, $userId, $vswitchId);

=cut

#-------------------------------------------------------
sub revokeVSwitch {

    # Get inputs
    my ( $class, $callback, $user, $hcp, $userId, $vswitchId ) = @_;

    # Directory where executables are
    my $dir = '/opt/zhcp/bin';

    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }

    # Use SMAPI EXEC, use new extended SMAPI
    my $out = `ssh $user\@$hcp "$sudo $dir/smcli Virtual_Network_Vswitch_Set_Extended -T SYSTEM -k 'switch_name='$vswitchId -k 'revoke_userid='$userId -k 'persist=YES'"`;
    xCAT::zvmUtils->printSyslog("revokeVSwitch- ssh $user\@$hcp $sudo $dir/smcli Virtual_Network_Vswitch_Set_Extended -T SYSTEM -k 'switch_name='$vswitchId -k 'revoke_userid='$userId -k 'persist=YES'");
    $out = xCAT::zvmUtils->trimStr($out);

    xCAT::zvmUtils->printSyslog($out);


    # If return string contains 'Done' - Operation was successful
    my $retStr;
    if ( $out =~ m/Done/i ) {
        $retStr = "Done\n";
    } else {
        $retStr = "Failed " . "Error output: $out\n";
         xCAT::zvmUtils->printSyslog("Error output: $out");
        return $retStr;
    }

    return $retStr;
}
#-------------------------------------------------------

=head3   flashCopy

    Description : Flash copy
    Arguments   :   User (root or non-root)
                    zHCP
                    Source userId
                    Source address
                    Target userId
                    Target address
    Returns     : Operation results (Done/Failed)
    Example     : my $results = xCAT::zvmCPUtils->flashCopy($user, $hcp, $srcAddr, $targetAddr);

=cut

#-------------------------------------------------------
sub flashCopy {

    # Get inputs
    my ( $class, $user, $hcp, $srcAddr, $tgtAddr ) = @_;

    # Directory where executables are
    my $dir = '/opt/zhcp/bin';

    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }

    # Flash copy using CP

    xCAT::zvmUtils->printSyslog("CP FlashCopy- ssh $user\@$hcp $sudo /sbin/vmcp flashcopy $srcAddr 0 end to $tgtAddr 0 end synchronous");
    my $out = `ssh $user\@$hcp "$sudo /sbin/vmcp flashcopy $srcAddr 0 end to $tgtAddr 0 end synchronous"`;

    $out = xCAT::zvmUtils->trimStr($out);

    # If return string contains 'Command complete' - Operation was successful
    my $retStr = "";
    if ( $out =~ m/Command complete/i ) {
        $retStr = "Copying data via CP FLASHCOPY... Done\n";
    } else {
        $out    = xCAT::zvmUtils->tabStr($out);
        $retStr = "Copying data via CP FLASHCOPY... Failed\n$out";
        xCAT::zvmUtils->printSyslog("$out");
    }

    return $retStr;
}

#-------------------------------------------------------

=head3   smapiFlashCopy

    Description : Flash copy using SMAPI
    Arguments   :   User (root or non-root)
                    zHCP
                    Source userId
                    Source address
                    Target userId
                    Target address
    Returns     : Operation results (Done/Failed)
    Example     : my $results = xCAT::zvmCPUtils->smapiFlashCopy($user, $node, $srcId, $srcAddr, $tgtId, $targetAddr);

=cut

#-------------------------------------------------------
sub smapiFlashCopy {

    # Get inputs
    my ( $class, $user, $hcp, $srcId, $srcAddr, $tgtId, $tgtAddr ) = @_;

    # Directory where executables are
    my $dir = '/opt/zhcp/bin';

    my $retStr = "";

    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }

    my $hcpUserId = xCAT::zvmCPUtils->getUserId($user, $hcp);

    # Use SMAPI EXEC to flash copy
    my $cmd = '\"' . "CMD=FLASHCOPY $srcId $srcAddr 0 END $tgtId $tgtAddr 0 END SYNC" . '\"';
    xCAT::zvmUtils->printSyslog("smapiFlashCopy- ssh $user\@$hcp $sudo $dir/smcli xCAT_Commands_IUO -T $hcpUserId -c $cmd");
    my $out = `ssh $user\@$hcp "$sudo $dir/smcli xCAT_Commands_IUO -T $hcpUserId -c $cmd"`;
    my $rc = $? >> 8;
    if ($rc == 255) {
        $retStr = "(Error) Failed to communicate with the zhcp system: $hcp output:$out";
        return $retStr;
    }

    $out = xCAT::zvmUtils->trimStr($out);

    # If return string contains 'Done' - Operation was successful
    if (( $out =~ m/Done/i ) or (($out =~ m/Return Code: 592/i) and ($out =~m/Reason Code: 8888/i))) {
        $retStr = "Copying data via SMAPI FLASHCOPY... Done\n";
    } else {
        $out    = xCAT::zvmUtils->tabStr($out);
        $retStr = "An Error occurred copying data via SMAPI FLASHCOPY... $out";
    }

    return $retStr;
}

#-------------------------------------------------------

=head3   punch2Reader

    Description : Write file to z/VM punch and transfer it to reader
    Arguments   :   User (root or non-root)
                    zHCP
                    UserID to receive file
                    Source file
                    Target file to be created by punch (e.g. sles.parm)
                    Options, e.g. -t (Convert EBCDIC to ASCII) or "" for no options
                    SPOOL file class to be assigned to the punched file
                        "" means that the current class is to be used
                        anything else is the class to set on the punched file
    Returns     : Operation results ("Done" or "Failed" with additional info)
    Example     : my $response = xCAT::zvmCPUtils->punch2Reader( $user, $hcp, $userId, $srcFile,
                                                                 $tgtFile, $options, $spoolClass );

=cut

#-------------------------------------------------------
sub punch2Reader {
    my ( $class, $user, $hcp, $userId, $srcFile, $tgtFile, $options, $spoolClass ) = @_;

    my $out = "";
    my $punched = 0;
    my $rc = 0;
    my $subResp = "";

    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }

    my $punchTarget = "";
    if ( $spoolClass eq "" ) {
        $punchTarget = "-u $userId";
    }

    # Get source node OS
    my $os = xCAT::zvmUtils->getOsVersion($user, $hcp);

    # VMUR located in different directories on RHEL and SLES
    my $vmur;
    if ( $os =~ m/sles10/i ) {
        $vmur = "/sbin/vmur";
    } else {
        $vmur = "/usr/sbin/vmur";
    }

    # Punch the file.  A loop is done in case the punch is currently in use.
    my $done = 0;
    my $maxTries = 12;              # 12 attempts with 15 second waits for punch to become available
    my $maxTime = $maxTries / 4;    # Total time: 3 minutes
    for ( my $i=0; ( $i < $maxTries and !$done ); $i++ ) {
        $out = `ssh -o ConnectTimeout=5 $user\@$hcp "$sudo $vmur punch $options $punchTarget -r $srcFile -N $tgtFile" 2>&1`;
        $rc = $? >> 8;
        if ( $rc == 255 ) {
            xCAT::zvmUtils->printSyslog( "(Error) In punch2Reader(), SSH communication with $hcp failed for command: $vmur punch" );
            $subResp = "Failed to communicate with the zHCP system: $hcp";
            $done = 1;
        } elsif ( $out =~ m/A concurrent instance of vmur is already active/i ) {
            # Recoverable error: retry the command after a delay
            xCAT::zvmUtils->printSyslog( "punch2Reader() Punch in use on $hcp, retrying in 15 seconds" );
            $subResp = "Failed, Punch in use on $hcp for over $maxTime minutes.";    # Assume it will never become available
            sleep( 15 );
        } elsif ( $rc == 0 ) {
            # Punch appears successful
            $subResp = '';
            $punched = 1;
            $done = 1;
        } else {
            # Punch failed for other than currently in use.
            chomp( $out );
            $subResp = "Failed, punch info: '$out'";
            xCAT::zvmUtils->printSyslog( "punch2Reader() Failed punching $srcFile to $userId from $hcp, rc: $rc, out: '$out'" );
            $done = 1;
        }
    }

    # If we successfully punched the file, we may have some final steps.
    if ( $punched == 1 ) {
        # If a spool class was specified then we punched to the zHCP's reader instead of
        # punching directly to the target virtual machine and now we need to transfer it
        # to the target virtual machine.  Otherwise, we are done.
        if ( $spoolClass ne "" ) {
            # Split the punch response line so we can access the spoolid of the created punch file.
            # e.g. Reader file with spoolid 0002 created.
            my @words = split( / /, $out );
            my $spoolId = $words[4];

            # Change the class of the spool file that we created so that it is the requested class.
            # We could not spool the punch to the desired class because of the possibility of
            # multiple threads using the punch that require different classes.  Thus, we need to
            # change the individual punch files.
            $out = `ssh -o ConnectTimeout=5 $user\@$hcp "$sudo vmcp change rdr $spoolId class $spoolClass" 2>&1`;
            $rc = $? >> 8;
            if ( $rc == 255 ) {
                # SSH failure to communicate with zHCP.  Nothing to do, file remains in zHCP's reader.
                xCAT::zvmUtils->printSyslog( "(Error) In punch2Reader(), SSH communication with $hcp failed for command: vmcp change rdr $spoolId class $spoolClass" );
                $subResp = "Failed to communicate with the zHCP system to change the reader file $spoolId to class $spoolClass: $hcp";
            } elsif ( $rc != 0 ) {
                # Generic failure of transfer command.
                chomp( $out );
                xCAT::zvmUtils->printSyslog( "punch2Reader() Change of spool file $spoolId on $hcp to class $spoolClass failed, rc: $rc, out: $out" );
                $subResp = "Failed, change rdr info rc: $rc, out: '$out'";
            }

            # If we did not have any errors, then transfer the spoolfile to the targer user's reader.
            if ( $subResp eq "" ) {
                $out = `ssh -o ConnectTimeout=5 $user\@$hcp "$sudo vmcp transfer rdr $spoolId to $userId" 2>&1`;
                $rc = $? >> 8;
                if ( $rc == 0 ) {
                    # Successful transfer
                    $subResp = "Done";
                } elsif ( $rc == 255 ) {
                    # SSH failure to communicate with zHCP.  Nothing to do, file remains in zHCP's reader.
                    xCAT::zvmUtils->printSyslog( "(Error) In punch2Reader(), SSH communication with $hcp failed for command: vmcp transfer rdr $spoolId to $userId" );
                    $subResp = "Failed to communicate with the zHCP system to transfer reader file $spoolId: $hcp";
                } else {
                    # Generic failure of transfer command.
                    chomp( $out );
                    xCAT::zvmUtils->printSyslog( "punch2Reader() Transfer of spool file $spoolId from $hcp to $userId failed, rc: $rc, out: $out" );
                    $subResp = "Failed, transfer info rc: $rc, out: '$out'";
                }
            }

            # If we had any error then attempt to purge the file from the zHCP machine.
            if ( $subResp ne "Done" ) {
                $out = `ssh -o ConnectTimeout=5 $user\@$hcp "$sudo vmcp purge reader $spoolId"`;
                $rc = $? >> 8;
                if ( $rc == 255 ) {
                    # SSH failure to communicate with zHCP.  Nothing to do, file remains in zHCP's reader.
                    xCAT::zvmUtils->printSyslog( "(Error) In punch2Reader(), SSH communication with $hcp failed for command: vmcp purge reader $spoolId" );
                    $subResp = $subResp. "\nFailed to communicate with the zHCP system to purge reader file $spoolId: $hcp";
                } elsif ( $rc != 0 ) {
                    # Any failure is bad and unrecoverable.
                    chomp( $out );
                    xCAT::zvmUtils->printSyslog( "punch2Reader() Unable to purge spool file $spoolId on $hcp, rc: $rc, out: $out" );
                    $subResp = $subResp . "\nUnable to purge reader rc: $rc, out: '$out'";
                }
            }
        } else {
            # Successful punch directly to the target virtual machine.
            $subResp = "Done";
        }
    }

    return $subResp;
}

#-------------------------------------------------------

=head3   purgeReader

    Description : Purge reader
    Arguments   :   User (root or non-root)
                    zHCP
                    UserID to purge reader
    Returns     : Nothing
    Example     : my $rc = xCAT::zvmCPUtils->purgeReader($hcp, $userId);

=cut

#-------------------------------------------------------
sub purgeReader {
    my ( $class, $user, $hcp, $userId ) = @_;

    # Directory where executables are
    my $dir = '/opt/zhcp/bin';

    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }

    xCAT::zvmUtils->printSyslog("sudoer:$user zHCP:$hcp sudo:$sudo");

    my $out;
    if (xCAT::zvmUtils->smapi4xcat($user, $hcp)) {
        # Use SMAPI EXEC to purge reader
        my $cmd = '\"' . "CMD=PURGE $userId RDR ALL" . '\"';
        $out = `ssh $user\@$hcp "$sudo $dir/smcli xCAT_Commands_IUO -T $userId -c $cmd"`;
        xCAT::zvmUtils->printSyslog("smcli xCAT_Commands_IUO -T $userId -c $cmd");
    } else {
        # Purge reader using CP
        $out = `ssh -o ConnectTimeout=5 $user\@$hcp "$sudo /sbin/vmcp purge $userId rdr all"`;
        xCAT::zvmUtils->printSyslog("/sbin/vmcp purge $userId rdr all");
    }

    $out = xCAT::zvmUtils->trimStr($out);
    return $out;
}

#-------------------------------------------------------

=head3   sendCPCmd

    Description : Send CP command to a given userID (Class C users only)
    Arguments   :   User (root or non-root)
                    zHCP
                    UserID to send CP command
    Returns     : Nothing
    Example     : xCAT::zvmCPUtils->sendCPCmd($hcp, $userId, $cmd);

=cut

#-------------------------------------------------------
sub sendCPCmd {
    my ( $class, $user, $hcp, $userId, $cmd ) = @_;

    # Directory where executables are
    my $dir = '/opt/zhcp/bin';

    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }

    xCAT::zvmUtils->printSyslog("sudoer:$user zHCP:$hcp sudo:$sudo");

    my $out;
    if (xCAT::zvmUtils->smapi4xcat($user, $hcp)) {
        # Use SMAPI EXEC to send command
        $cmd = '\"' . "CMD=SEND CP $userId " . uc($cmd) . '\"';
        $out = `ssh $user\@$hcp "$sudo $dir/smcli xCAT_Commands_IUO -T $userId -c $cmd"`;
        xCAT::zvmUtils->printSyslog("smcli xCAT_Commands_IUO -T $userId -c $cmd");
    } else {
        # Send CP command to given user
        $out = `ssh $user\@$hcp "$sudo /sbin/vmcp send cp $userId $cmd"`;
        xCAT::zvmUtils->printSyslog("/sbin/vmcp send cp $userId $cmd");
    }

    $out = xCAT::zvmUtils->trimStr($out);
    return;
}

#-------------------------------------------------------

=head3   getNetworkLayer

    Description : Get the network layer for a given node
    Arguments   :   User (root or non-root)
                    Node
                    Network name
    Returns     :  2     - Layer 2
                   3     - Layer 3
                  -1     - Failed to get network layer
                  error string if SSH fails
    Example     : my $layer = xCAT::zvmCPUtils->getNetworkLayer($node);

=cut

#-------------------------------------------------------
sub getNetworkLayer {
    my ( $class, $user, $node, $netName ) = @_;

    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }

    # Exit if the network name is not given
    if ( !$netName ) {
        return -1;
    }

    # Get network type (Layer 2 or 3)
    #$out = `ssh -o ConnectTimeout=5 $user\@$node "$sudo /sbin/vmcp q lan $netName"`;
    my $cmd = "$sudo /sbin/vmcp q lan $netName";
    my $out = xCAT::zvmUtils->execcmdonVM($user, $node, $cmd); # caller sets $user to $::SUDOER
    if (xCAT::zvmUtils->checkOutput($out) == -1) {
        return $out;
    }
    if ( !$out ) {
        return -1;
    }

    # Go through each line
    my $layer = 3;    # Default to layer 3
    my @lines = split( '\n', $out );
    foreach (@lines) {

        # If the line contains ETHERNET, then it is a layer 2 network
        if ( $_ =~ m/ETHERNET/i ) {
            $layer = 2;
        }
    }

    return $layer;
}

#-------------------------------------------------------

=head3   getNetworkType

    Description : Get the network type of a given network
    Arguments   :   User (root or non-root)
                    zHCP
                    Name of network
    Returns     : Network type (VSWITCH/HIPERS/QDIO) or string containing (Error)...
    Example     : my $netType = xCAT::zvmCPUtils->getNetworkType($hcp, $netName);

=cut

#-------------------------------------------------------
sub getNetworkType {
    my ( $class, $user, $hcp, $netName ) = @_;

    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }

    # Get network details
    my $outmsg;
    my $rc;
    my $out = `ssh -o ConnectTimeout=5 $user\@$hcp "$sudo /sbin/vmcp q lan $netName"`;
    ($rc, $outmsg) = xCAT::zvmUtils->checkSSH_Rc( $?, "ssh -o ConnectTimeout=5 $user\@$hcp \"$sudo /sbin/vmcp q lan $netName\"", $hcp, "getNetworkType", $out );
    if ($rc != 0) {
       return $outmsg;
    }

    $out = `echo "$out" | egrep -a 'Type'`;

    # Go through each line and determine network type
    my @lines = split( '\n', $out );
    my $netType = "";
    foreach (@lines) {

        # Virtual switch
        if ( $_ =~ m/VSWITCH/i ) {
            $netType = "VSWITCH";
        }

        # HiperSocket guest LAN
        elsif ( $_ =~ m/HIPERS/i ) {
            $netType = "HIPERS";
        }

        # QDIO guest LAN
        elsif ( $_ =~ m/QDIO/i ) {
            $netType = "QDIO";
        }
    }

    return $netType;
}

#-------------------------------------------------------

=head3   defineCpu

    Description : Add processor(s) to given node
    Arguments   :   User (root or non-root)
                    Node
    Returns     : Nothing or error string if failure
    Example     : my $out = xCAT::zvmCPUtils->defineCpu($node, $addr, $type);

=cut

#-------------------------------------------------------
sub defineCpu {

    # Get inputs
    my ( $class, $user, $node, $addr, $type ) = @_;

    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }

    # Define processor(s)
    #my $out = `ssh -o ConnectTimeout=5 $user\@$node "$sudo /sbin/vmcp define cpu $addr type $type"`;
    my $cmd = "$sudo /sbin/vmcp define cpu $addr type $type";
    my $out = xCAT::zvmUtils->execcmdonVM($user, $node, $cmd); # caller sets $user to $::SUDOER

    return ($out);
}

#-------------------------------------------------------

=head3   getIplTime

    Description : Get the IPL time
    Arguments   :   User (root or non-root)
                    zHCP
    Returns     : IPL time
    Example     : my $out = xCAT::zvmCPUtils->getIplTime($user, $hcp);

=cut

#-------------------------------------------------------
sub getIplTime {
    my ($class, $user, $hcp) = @_;

    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }

    my $out = `ssh -o ConnectTimeout=5 $user\@$hcp "$sudo /sbin/vmcp q cplevel"`;
    return ((split("\n", $out))[2]);
}
