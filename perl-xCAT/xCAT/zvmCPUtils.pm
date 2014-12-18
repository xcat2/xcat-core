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
    my $out     = `ssh -o ConnectTimeout=5 $user\@$node "$sudo /sbin/vmcp q userid"`;
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
    my $out     = `ssh -o ConnectTimeout=5 $user\@$node "$sudo /sbin/vmcp q userid"`;
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
    my $out = `ssh -o ConnectTimeout=5 $user\@$node "$sudo /sbin/vmcp q priv"`;
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
    Example     : my $memory = xCAT::zvmCPUtils->getMemory($node);
    
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
    my $out = `ssh -o ConnectTimeout=5 $user\@$node "$sudo /sbin/vmcp q virtual storage"`;
    my @out = split( ' ', $out );

    return ( xCAT::zvmUtils->trimStr( $out[2] ) );
}



#-------------------------------------------------------

=head3   getCpu

    Description : Get the processor(s) of a given node
    Arguments   :   User (root or non-root)
                    Node
    Returns     : Processor(s)
    Example     : my $proc = xCAT::zvmCPUtils->getCpu($node);
    
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
    my $out = `ssh -o ConnectTimeout=5 $user\@$node "$sudo /sbin/vmcp q virtual cpus"`;
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
    my $out = `ssh -o ConnectTimeout=5 $user\@$node "$sudo /sbin/vmcp q virtual nic"`;
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
    
    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }

    # Get network names
    my $out = `ssh -o ConnectTimeout=5 $user\@$node "$sudo /sbin/vmcp q lan | egrep 'LAN|VSWITCH'"`;
    my @lines = split( '\n', $out );
    my @parms;
    my $names;
    foreach (@lines) {
        
        # Trim output
        $_     = xCAT::zvmUtils->trimStr($_);
        @parms = split( ' ', $_ );
        
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
    my $out   = `ssh $user\@$node "$sudo /sbin/vmcp q v nic" | egrep -i "VSWITCH|LAN"`;
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
    my ( $class, $user, $node, $netName ) = @_;

    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }
    
    # Get network info
    my $out;
    if ( $netName eq "all" ) {
        $out = `ssh -o ConnectTimeout=5 $user\@$node "$sudo /sbin/vmcp q lan"`;
    } else {
        $out = `ssh -o ConnectTimeout=5 $user\@$node "$sudo /sbin/vmcp q lan $netName"`;
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
    my $out = `ssh -o ConnectTimeout=5 $user\@$node "$sudo /sbin/vmcp q virtual dasd"`;
    my $str = xCAT::zvmUtils->tabStr($out);

    return ($str);
}

#-------------------------------------------------------

=head3   loadVmcp

    Description : Load Linux VMCP module on a given node
    Arguments   :   User (root or non-root)
                    Node
    Returns     : Nothing
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
    my $out = `ssh -o ConnectTimeout=5 $user\@$node "$sudo /sbin/modprobe vmcp"`;
    return;
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
    my $out = `ssh -o ConnectTimeout=5 $user\@$node "$sudo /sbin/vmcp q v nic" | grep "VSWITCH"`;
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
    Returns     : Operation results (Done/Failed)
    Example     : my $out = xCAT::zvmCPUtils->grantVswitch($callback, $hcp, $userId, $vswitchId);
    
=cut

#-------------------------------------------------------
sub grantVSwitch {

    # Get inputs
    my ( $class, $callback, $user, $hcp, $userId, $vswitchId ) = @_;
    
    # Directory where executables are
    my $dir = '/opt/zhcp/bin';
    
    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }

    # Use SMAPI EXEC
    my $out = `ssh $user\@$hcp "$sudo $dir/smcli Virtual_Network_Vswitch_Set -T SYSTEM -n $vswitchId -I $userId"`;
    xCAT::zvmUtils->printSyslog("grantVSwitch- ssh $user\@$hcp $sudo $dir/smcli Virtual_Network_Vswitch_Set -T SYSTEM -n $vswitchId -I $userId");
    $out = xCAT::zvmUtils->trimStr($out);

    # If return string contains 'Done' - Operation was successful
    my $retStr;
    if ( $out =~ m/Done/i ) {
        $retStr = "Done\n";
    } else {
        $retStr = "Failed\n";
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
    my $out = `ssh $user\@$hcp "$sudo /sbin/vmcp flashcopy $srcAddr 0 end to $tgtAddr 0 end synchronous"`;
    
    $out = xCAT::zvmUtils->trimStr($out);

    # If return string contains 'Command complete' - Operation was successful
    my $retStr = "";
    if ( $out =~ m/Command complete/i ) {
        $retStr = "Copying data via CP FLASHCOPY... Done\n";
    } else {
        $out    = xCAT::zvmUtils->tabStr($out);
        $retStr = "Copying data via CP FLASHCOPY... Failed\n$out";
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
    
    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }

    my $hcpUserId = xCAT::zvmCPUtils->getUserId($user, $hcp);
        
    # Use SMAPI EXEC to flash copy
    my $cmd = '\"' . "CMD=FLASHCOPY $srcId $srcAddr 0 END $tgtId $tgtAddr 0 END" . '\"';
    my $out = `ssh $user\@$hcp "$sudo $dir/smcli xCAT_Commands_IUO -T $hcpUserId -c $cmd"`;
    xCAT::zvmUtils->printSyslog("smapiFlashCopy- ssh $user\@$hcp $sudo $dir/smcli xCAT_Commands_IUO -T $hcpUserId -c $cmd");
        
    $out = xCAT::zvmUtils->trimStr($out);

    # If return string contains 'Done' - Operation was successful
    my $retStr = "";
    if ( $out =~ m/Done/i ) {
        $retStr = "Copying data via SMAPI FLASHCOPY... Done\n";
    } else {
        $out    = xCAT::zvmUtils->tabStr($out);
        $retStr = "Copying data via SMAPI FLASHCOPY... $out";
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
                    Options, e.g. -t (Convert EBCDIC to ASCII)
    Returns     : Operation results (Done/Failed)
    Example     : my $rc = xCAT::zvmCPUtils->punch2Reader($hcp, $userId, $srcFile, $tgtFile, $options);
    
=cut

#-------------------------------------------------------
sub punch2Reader {
    my ( $class, $user, $hcp, $userId, $srcFile, $tgtFile, $options ) = @_;
    
    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }
    
    # Get source node OS
    my $os = xCAT::zvmUtils->getOsVersion($user, $hcp);
            
    # Punch to reader
    # VMUR located in different directories on RHEL and SLES
    my $out;
    if ( $os =~ m/sles10/i ) {
        $out = `ssh -o ConnectTimeout=5 $user\@$hcp "$sudo /sbin/vmur punch $options -u $userId -r $srcFile -N $tgtFile"`;
    } else {
    	$out = `ssh -o ConnectTimeout=5 $user\@$hcp "$sudo /usr/sbin/vmur punch $options -u $userId -r $srcFile -N $tgtFile"`;
    }
    
    # If punch is successful -- Look for this string
    my $searchStr = "created and transferred";
    if ( !( $out =~ m/$searchStr/i ) ) {
        $out = "Failed\n";
    } else {
        $out = "Done\n";
    }

    return $out;
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
    my $out = `ssh -o ConnectTimeout=5 $user\@$node "$sudo /sbin/vmcp q lan $netName"`;
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
    Returns     : Network type (VSWITCH/HIPERS/QDIO)
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
    my $out = `ssh -o ConnectTimeout=5 $user\@$hcp "$sudo /sbin/vmcp q lan $netName" | grep "Type"`;

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
    Returns     : Nothing
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
    my $out = `ssh -o ConnectTimeout=5 $user\@$node "$sudo /sbin/vmcp define cpu $addr type $type"`;

    return ($out);
}
