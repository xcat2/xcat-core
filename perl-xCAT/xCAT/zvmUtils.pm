# IBM(c) 2013 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head1

    This is a utility plugin for z/VM.

=cut

#-------------------------------------------------------
package xCAT::zvmUtils;
use xCAT::MsgUtils;
use xCAT::Utils;
use xCAT::Table;
use xCAT::NetworkUtils;
use File::Copy;
use File::Basename;
use strict;
use warnings;
1;

#-------------------------------------------------------

=head3   getNodeProps
    Description : Get node properties
    Arguments   :   Table
                    Node
                    Properties
    Returns     : Node properties from given table
    Example     : my $propVals = xCAT::zvmUtils->getNodeProps($tabName, $node, $propNames);
    
=cut

#-------------------------------------------------------
sub getNodeProps {

    # Get inputs
    my ( $class, $tabName, $node, @propNames ) = @_;

    # Get table
    my $tab = xCAT::Table->new($tabName);

    # Get property values
    my $propVals = $tab->getNodeAttribs( $node, [@propNames] );

    return ($propVals);
}

#-------------------------------------------------------

=head3   getTabPropsByKey
    Description : Get table entry properties by key
    Arguments   :   Table
                    Key name
                    Key value
                    Requested properties
    Returns     : Table entry properties
    Example     : my $propVals = xCAT::zvmUtils->getTabPropsByKey($tabName, $key, $keyValue, @reqProps);
    
=cut

#-------------------------------------------------------
sub getTabPropsByKey {

    # Get inputs
    my ( $class, $tabName, $key, $keyVal, @propNames ) = @_;

    # Get table
    my $tab = xCAT::Table->new($tabName);
    my $propVals;

    # Get table attributes matching given key
    $propVals = $tab->getAttribs( { $key => $keyVal }, @propNames );
    return ($propVals);
}

#-------------------------------------------------------

=head3   getAllTabEntries
    Description : Get all entries within given table
    Arguments   : Table name
    Returns     : All table entries
    Example     : my $entries = xCAT::zvmUtils->getAllTabEntries($tabName);
    
=cut

#-------------------------------------------------------
sub getAllTabEntries {

    # Get inputs
    my ( $class, $tabName ) = @_;

    # Get table
    my $tab = xCAT::Table->new($tabName);
    my $entries;

    # Get all entries within given table
    $entries = $tab->getAllEntries();
    return ($entries);
}

#-------------------------------------------------------

=head3   setNodeProp

    Description : Set a node property in a given table
    Arguments   :   Table
                    Node
                    Property name
                    Property value
    Returns     : Nothing
    Example     : xCAT::zvmUtils->setNodeProp($tabName, $node, $propName, $propVal);
    
=cut

#-------------------------------------------------------
sub setNodeProp {

    # Get inputs
    my ( $class, $tabName, $node, $propName, $propVal ) = @_;

    # Get table
    my $tab = xCAT::Table->new( $tabName, -create => 1, -autocommit => 0 );

    # Set property
    $tab->setAttribs( { 'node' => $node }, { $propName => $propVal } );

    # Save table
    $tab->commit;

    return;
}

#-------------------------------------------------------

=head3   setNodeProps

    Description : Set node properties in a given table
    Arguments   :   Table
                    Node
                    Reference to property name/value hash
    Returns     : Nothing
    Example     : xCAT::zvmUtils->setNodeProps($tabName, $node, \%propHash);
    
=cut

#-------------------------------------------------------
sub setNodeProps {

    # Get inputs
    my ( $class, $tabName, $node, $propHash ) = @_;

    # Get table
    my $tab = xCAT::Table->new( $tabName, -create => 1, -autocommit => 0 );

    # Set property
    $tab->setAttribs( { 'node' => $node }, $propHash );

    # Save table
    $tab->commit;

    return;
}

#-------------------------------------------------------

=head3   delTabEntry

    Description : Delete a table entry
    Arguments   :   Table
                    Key name
                    Key value 
    Returns     : Nothing
    Example     : xCAT::zvmUtils->delTabEntry($tabName, $keyName, $keyVal);
    
=cut

#-------------------------------------------------------
sub delTabEntry {

    # Get inputs
    my ( $class, $tabName, $keyName, $keyVal ) = @_;

    # Get table
    my $tab = xCAT::Table->new( $tabName, -create => 1, -autocommit => 0 );

    # Delete entry from table
    my %key = ( $keyName => $keyVal );
    $tab->delEntries( \%key );

    # Save table
    $tab->commit;

    return;
}

#-------------------------------------------------------

=head3   tabStr

    Description : Tab a string (4 spaces)
    Arguments   : String
    Returns     : Tabbed string
    Example     : my $str = xCAT::zvmUtils->tabStr($str);
    
=cut

#-------------------------------------------------------
sub tabStr {

    # Get inputs
    my ( $class, $inStr ) = @_;
    my @lines = split( "\n", $inStr );

    # Tab output
    my $outStr;
    foreach (@lines) {
        $outStr .= "    $_\n";
    }

    return ($outStr);
}

#-------------------------------------------------------

=head3   trimStr

    Description : Trim the whitespaces in a string
    Arguments   : String
    Returns     : Trimmed string
    Example     : my $str = xCAT::zvmUtils->trimStr($str);
    
=cut

#-------------------------------------------------------
sub trimStr {

    # Get string
    my ( $class, $str ) = @_;

    # Trim right
    $str =~ s/\s*$//;

    # Trim left
    $str =~ s/^\s*//;

    return ($str);
}

#-------------------------------------------------------

=head3   replaceStr

    Description : Replace a given pattern in a string
    Arguments   : String
    Returns     : New string
    Example     : my $str = xCAT::zvmUtils->replaceStr($str, $pattern, $replacement);
    
=cut

#-------------------------------------------------------
sub replaceStr {

    # Get string
    my ( $class, $str, $pattern, $replacement ) = @_;

    # Replace string
    $str =~ s/$pattern/$replacement/g;

    return ($str);
}

#-------------------------------------------------------

=head3   printLn

    Description : Print a string to stdout
    Arguments   : String
    Returns     : Nothing
    Example     : xCAT::zvmUtils->printLn($callback, $str);
    
=cut

#-------------------------------------------------------
sub printLn {

    # Get inputs
    my ( $class, $callback, $str ) = @_;

    # Print string
    my $rsp;
    my $type = "I";
    if ($str =~ m/error/i) {  # Set to print error if the string contains error
        $type = "E";
    }
    
    $rsp->{data}->[0] = "$str";
    xCAT::MsgUtils->message( $type, $rsp, $callback );
    # xCAT::MsgUtils->message( "S", $str );  # Print to syslog

    return;
}

#-------------------------------------------------------

=head3   printSyslog

    Description : Print a string to syslog
    Arguments   : String
    Returns     : Nothing
    Example     : xCAT::zvmUtils->printSyslog($str);
    
=cut

#-------------------------------------------------------
sub printSyslog {

    # Get inputs
    my ( $class, $str ) = @_;

    # Prepend where this message came from
    $str = $class . "  " . $str;

    # Print string
    xCAT::MsgUtils->message( "S", $str );

    return;
}

#-------------------------------------------------------

=head3   isZvmNode

    Description : Determines if a given node is in the 'zvm' table
    Arguments   : Node
    Returns     :   TRUE    Node exists
                    FALSE    Node does not exists
    Example     : my $out = xCAT::zvmUtils->isZvmNode($node);
    
=cut

#-------------------------------------------------------
sub isZvmNode {

    # Get inputs
    my ( $class, $node ) = @_;

    # Look in 'zvm' table
    my $tab = xCAT::Table->new( 'zvm', -create => 1, -autocommit => 0 );

    my @results = $tab->getAllAttribsWhere( "node like '%" . $node . "%'", 'userid' );
    foreach (@results) {

        # Return 'TRUE' if given node is in the table
        if ($_->{'userid'}) {
            return 1;
        }
    }

    return 0;
}

#-------------------------------------------------------

=head3   getHwcfg

    Description : Get the hardware configuration file path (SUSE only)
                  e.g. /etc/sysconfig/hardwarehwcfg-qeth-bus-ccw-0.0.0600
    Arguments   :   User (root or non-root)
                    Node
    Returns     : Hardware configuration file path
    Example     : my $hwcfg = xCAT::zvmUtils->getHwcfg($user, $node);
    
=cut

#-------------------------------------------------------
sub getHwcfg {

    # Get inputs
    my ( $class, $user, $node ) = @_;

    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }
    
    # Get OS
    my $os = xCAT::zvmUtils->getOs($user, $node);

    # Get network configuration file path
    my $out;
    my @parms;

    # If it is SUSE - hwcfg-qeth file is in /etc/sysconfig/hardware
    if ( $os =~ m/SUSE/i ) {
        $out = `ssh -o ConnectTimeout=5 $user\@$node "$sudo ls /etc/sysconfig/hardware/hwcfg-qeth*"`;
        @parms = split( '\n', $out );
        return ( $parms[0] );
    }

    # If no file is found - Return nothing
    return;
}

#-------------------------------------------------------

=head3   getIp

    Description : Get the IP address of a given node
    Arguments   : Node
    Returns     : IP address of given node
    Example     : my $ip = xCAT::zvmUtils->getIp($node);
    
=cut

#-------------------------------------------------------
sub getIp {

    # Get inputs
    my ( $class, $node ) = @_;

    # Get IP address
    # You need the extra space in the pattern,
    # else it will confuse gpok2 with gpok21
    my $out   = `cat /etc/hosts | egrep -i "$node | $node."`;
    my @parms = split( ' ', $out );

    return $parms[0];
}

#-------------------------------------------------------

=head3   getIfcfg

    Description : Get the network configuration file path of a given node
                    * Red Hat - /etc/sysconfig/network-scripts/ifcfg-eth
                    * SUSE    - /etc/sysconfig/network/ifcfg-qeth
    Arguments   :   User (root or non-root)
                    Node
    Returns     : Network configuration file path
    Example     : my $ifcfg = xCAT::zvmUtils->getIfcfg($user, $node);
    
=cut

#-------------------------------------------------------
sub getIfcfg {

    # Get inputs
    my ( $class, $user, $node ) = @_;
    
    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }

    # Get OS
    my $os = xCAT::zvmUtils->getOs($user, $node);

    # Get network configuration file path
    my $out;
    my @parms;

    # If it is Red Hat - ifcfg-qeth file is in /etc/sysconfig/network-scripts
    if ( $os =~ m/Red Hat/i ) {
        $out = `ssh -o ConnectTimeout=5 $user\@$node "$sudo ls /etc/sysconfig/network-scripts/ifcfg-eth*"`;
        @parms = split( '\n', $out );
        return ( $parms[0] );
    }

    # If it is SUSE - ifcfg-qeth file is in /etc/sysconfig/network
    elsif ( $os =~ m/SUSE/i ) {
        $out = `ssh -o ConnectTimeout=5 $user\@$node "$sudo ls /etc/sysconfig/network/ifcfg-qeth*"`;
        @parms = split( '\n', $out );
        return ( $parms[0] );
    }

    # If no file is found - Return nothing
    return;
}

#-------------------------------------------------------

=head3   getIfcfgByNic

    Description : Get the network configuration file path of a given node
    Arguments   :   User (root or non-root)
                    Node
                    NIC address
    Returns     : Network configuration file path
    Example     : my $ifcfg = xCAT::zvmUtils->getIfcfgByNic($user, $node, $nic);
    
=cut

#-------------------------------------------------------
sub getIfcfgByNic {

    # Get inputs
    my ( $class, $user, $node, $nic ) = @_;

    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }
    
    # Get OS
    my $os = xCAT::zvmUtils->getOs($user, $node);

    # Get network configuration file path
    my $out;
    my @parms;

    # If it is Red Hat - ifcfg-qeth file is in /etc/sysconfig/network-scripts
    if ( $os =~ m/Red Hat/i ) {
        $out   = `ssh -o ConnectTimeout=5 $user\@$node "$sudo ls /etc/sysconfig/network-scripts/ifcfg-eth*"`;
        @parms = split( '\n', $out );

        # Go through each line
        foreach (@parms) {

            # If the network file contains the NIC address
            $out = `ssh -o ConnectTimeout=5 $user\@$node "$sudo cat $_" | egrep -i "$nic"`;
            if ($out) {

                # Return network file path
                return ($_);
            }
        }
    }

    # If it is SLES 10 - ifcfg-qeth file is in /etc/sysconfig/network
    elsif ( $os =~ m/SUSE Linux Enterprise Server 10/i ) {
        $out = `ssh -o ConnectTimeout=5 $user\@$node "$sudo ls /etc/sysconfig/network/ifcfg-qeth*" | grep -i "$nic"`;
        @parms = split( '\n', $out );
        return ( $parms[0] );
    }

    # If it is SLES 11 - ifcfg-qeth file is in /etc/sysconfig/network
    elsif ( $os =~ m/SUSE Linux Enterprise Server 11/i ) {

        # Get a list of ifcfg-eth files found
        $out = `ssh -o ConnectTimeout=5 $user\@$node "$sudo ls /etc/sysconfig/network/ifcfg-eth*"`;
        my @file = split( '\n', $out );

        # Go through each ifcfg-eth file
        foreach (@file) {

            # If the network file contains the NIC address
            $out = `ssh -o ConnectTimeout=5 $user\@$node "$sudo cat $_" | grep -i "$nic"`;
            if ($out) {

                # Return ifcfg-eth file path
                return ($_);
            }
        }
    }

    # If no file is found - Return nothing
    return;
}

#-------------------------------------------------------

=head3   sendFile

    Description : SCP a file to a given node
    Arguments   :   User (root or non-root)
                    Node
                    Source file
                    Target file
    Returns     : Nothing
    Example     : xCAT::zvmUtils->sendFile($user, $node, $srcFile, $trgtFile);
    
=cut

#-------------------------------------------------------
sub sendFile {

    # Get inputs
    my ( $class, $user, $node, $srcFile, $trgtFile ) = @_;

    # Create destination string
    my $dest = "$user\@$node";

    # SCP directory entry file over to HCP
    my $out = `/usr/bin/scp $srcFile $dest:$trgtFile`;

    return;
}

#-------------------------------------------------------

=head3   getRootDeviceAddr

    Description : Get the root device address of a given node
    Arguments   :   User (root or non-root)
                    Node
    Returns     : Root device address
    Example     : my $deviceAddr = xCAT::zvmUtils->getRootDeviceAddr($user, $node);
    
=cut

#-------------------------------------------------------
sub getRootDeviceAddr {

    # Get inputs
    my ( $class, $user, $node ) = @_;

    # Get the root device node
    # LVM is not supported
    my $out = `ssh $user\@$node  "mount" | grep "/ type" | sed 's/1//'`;
    my @parms = split( " ", $out );
    @parms = split( "/", xCAT::zvmUtils->trimStr( $parms[0] ) );
    my $devNode = $parms[0];

    # Get disk address
    $out = `ssh $user\@$node "cat /proc/dasd/devices" | grep "$devNode" | sed 's/(ECKD)//' | sed 's/(FBA )//' | sed 's/0.0.//'`;
    @parms = split( " ", $out );
    return ( $parms[0] );
}

#-------------------------------------------------------

=head3   disableEnableDisk

    Description : Disable/enable a disk for a given node
    Arguments   :   User (root or non-root)
                    Node
                    Device address
                    Option (-d|-e)
    Returns     : Nothing
    Example     : my $out = xCAT::zvmUtils->disableEnableDisk($callback, $user, $node, $option, $devAddr);
    
=cut

#-------------------------------------------------------
sub disableEnableDisk {

    # Get inputs
    my ( $class, $user, $node, $option, $devAddr ) = @_;
    
    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }

    # Disable/enable disk
    my $out;
    if ( $option eq "-d" || $option eq "-e" ) {
        $out = `ssh $user\@$node "$sudo /sbin/chccwdev $option $devAddr"`;
    }

    return ($out);
}

#-------------------------------------------------------

=head3   getMdisks

    Description : Get the MDISK statements in the user entry of a given node
    Arguments   :   User (root or non-root)
                    Node
    Returns     : MDISK statements
    Example     : my @mdisks = xCAT::zvmUtils->getMdisks($callback, $user, $node);
    
=cut

#-------------------------------------------------------
sub getMdisks {

    # Get inputs
    my ( $class, $callback, $user, $node ) = @_;

    # Directory where executables are
    my $dir = '/opt/zhcp/bin';

    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }
    
    # Get HCP
    my @propNames = ( 'hcp', 'userid' );
    my $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $node, @propNames );
    my $hcp = $propVals->{'hcp'};

    # Get node userID
    my $userId = $propVals->{'userid'};

    my $out = `ssh $user\@$hcp "$sudo $dir/getuserentry $userId" | grep "MDISK"`;

    # Get MDISK statements
    my @lines = split( '\n', $out );
    my @disks;
    foreach (@lines) {
        $_ = xCAT::zvmUtils->trimStr($_);

        # Save MDISK statements
        push( @disks, $_ );
    }

    return (@disks);
}

#-------------------------------------------------------

=head3   getDedicates

    Description : Get the DEDICATE statements in the user entry of a given node
    Arguments   :   User (root or non-root)
                    Node
    Returns     : DEDICATE statements
    Example     : my @dedicates = xCAT::zvmUtils->getDedicates($callback, $user, $node);
    
=cut

#-------------------------------------------------------
sub getDedicates {

    # Get inputs
    my ( $class, $callback, $user, $node ) = @_;

    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }

    # Directory where executables are
    my $dir = '/opt/zhcp/bin';
    
    # Get zHCP
    my @propNames = ( 'hcp', 'userid' );
    my $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $node, @propNames );
    my $hcp = $propVals->{'hcp'};

    # Get node userId
    my $userId = $propVals->{'userid'};

    my $out = `ssh $user\@$hcp "$sudo $dir/smcli Image_Query_DM -T $userId" | egrep -i "DEDICATE"`;
    
    # Get DEDICATE statements
    my @lines = split( '\n', $out );
    my @dedicates;
    foreach (@lines) {
        $_ = xCAT::zvmUtils->trimStr($_);

        # Save statements
        push( @dedicates, $_ );
    }

    return (@dedicates);
}

#-------------------------------------------------------

=head3   getUserEntryWODisk

    Description : Get the user entry of a given node without MDISK statments, 
                  and save it to a file
    Arguments   :   User (root or non-root)
                    Node
                    File name to save user entry under
    Returns     : Nothing
    Example     : my $out = xCAT::zvmUtils->getUserEntryWODisk($callback, $user, $node, $file);
    
=cut

#-------------------------------------------------------
sub getUserEntryWODisk {

    # Get inputs
    my ( $class, $callback, $user, $node, $file ) = @_;
    
    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }

    # Directory where executables are
    my $dir = '/opt/zhcp/bin';
        
    # Get node properties from 'zvm' table
    my @propNames = ( 'hcp', 'userid' );
    my $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $node, @propNames );

    # Get HCP
    my $hcp = $propVals->{'hcp'};
    if ( !$hcp ) {
        xCAT::zvmUtils->printLn( $callback, "Error: Missing node HCP" );
        return;
    }

    # Get node userID
    my $userId = $propVals->{'userid'};
    if ( !$userId ) {
        xCAT::zvmUtils->printLn( $callback, "Error: Missing node ID" );
        return;
    }

    my $out = `ssh $user\@$hcp "$sudo $dir/smcli Image_Query_DM -T $userId" | sed '\$d' | grep -v "MDISK"`;

    # Create a file to save output
    open( DIRENTRY, ">$file" );

    # Save output
    my @lines = split( '\n', $out );
    foreach (@lines) {

        # Trim line
        $_ = xCAT::zvmUtils->trimStr($_);

        # Write directory entry into file
        print DIRENTRY "$_\n";
    }
    close(DIRENTRY);

    return;
}

#-------------------------------------------------------

=head3   appendHostname

    Description : Append a hostname in front of a given string
    Arguments   :   Hostname
                    String
    Returns     : String appended with hostname
    Example     : my $str = xCAT::zvmUtils->appendHostname($hostname, $str);
    
=cut

#-------------------------------------------------------
sub appendHostname {
    my ( $class, $hostname, $str ) = @_;

    # Append hostname to every line
    my @outLn = split( "\n", $str );
    $str = "";
    foreach (@outLn) {
        $str .= "$hostname: " . $_ . "\n";
    }

    return $str;
}

#-------------------------------------------------------

=head3   checkOutput

    Description : Check the return of given output
    Arguments   : Output string
    Returns     :    0  Good output
                    -1  Bad output
    Example     : my $rtn = xCAT::zvmUtils->checkOutput($callback, $out);
    
=cut

#-------------------------------------------------------
sub checkOutput {
    my ( $class, $callback, $out ) = @_;

    # Check output string
    my @outLn = split( "\n", $out );
    foreach (@outLn) {

        # If output contains 'Failed', return -1
        if ( $_ =~ m/Failed/i || $_ =~ m/Error/i ) {
            return -1;
        }
    }

    return 0;
}

#-------------------------------------------------------

=head3   checkOutputExtractReason

    Description : Check the return of given output. If bad, extract the reason.
    Arguments   : Output string
                  Reason (passed as a reference)
    Returns     :    0  Good output
                    -1  Bad output
    Example     : my $rtn = xCAT::zvmUtils->checkOutput($callback, $out, \$reason);
    
=cut

#-------------------------------------------------------
sub checkOutputExtractReason {
    my ( $class, $callback, $out, $reason ) = @_;

    # Check output string
    my @outLn = split("\n", $out);
    foreach (@outLn) {
        # If output contains 'ERROR: ', return -1 and pass back the reason.
        if ($_ =~ /(.*?ERROR: )/) {
            $$reason = substr($_, index($_, "ERROR: ") + length("ERROR: "));
            return -1;
        }
    }

    return 0;
}

#-------------------------------------------------------

=head3   getDeviceNode

    Description : Get the device node for a given address
    Arguments   :   User (root or non-root)
                    Node
                    Disk address
    Returns     : Device node
    Example     : my $devNode = xCAT::zvmUtils->getDeviceNode($user, $node, $tgtAddr);
    
=cut

#-------------------------------------------------------
sub getDeviceNode {
    my ( $class, $user, $node, $tgtAddr ) = @_;

    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }
    
    # Determine device node
    my $out = `ssh $user\@$node "$sudo cat /proc/dasd/devices" | grep ".$tgtAddr("`;
    my @words = split(' ', $out);
    my $tgtDevNode;

    # /proc/dasd/devices look similar to this:
    # 0.0.0100(ECKD) at ( 94: 0) is dasda : active at blocksize: 4096, 1802880 blocks, 7042 MB
    # Look for the string 'is'
    my $i = 0;
    while ($tgtDevNode ne 'is') {
        $tgtDevNode = $words[$i];
        $i++;
    }

    return $words[$i];
}

#-------------------------------------------------------

=head3   getDeviceNodeAddr

    Description : Get the virtual device address for a given device node
    Arguments   :   User (root or non-root)
                    Node
                    Device node
    Returns     : Virtual device address
    Example     : my $addr = xCAT::zvmUtils->getDeviceNodeAddr($user, $node, $deviceNode);
    
=cut

#-------------------------------------------------------
sub getDeviceNodeAddr {
    my ( $class, $user, $node, $deviceNode ) = @_;

    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }
    
    # Find device node and determine virtual address
    #   /proc/dasd/devices look similar to this:
    #   0.0.0100(ECKD) at ( 94: 0) is dasda : active at blocksize: 4096, 1802880 blocks, 7042 MB
    my $addr = `ssh $user\@$node "$sudo cat /proc/dasd/devices" | grep -i "is $deviceNode"`;
    $addr =~ s/ +/ /g;
    $addr =~ s/^0.0.([0-9a-f]*).*/$1/;
    chomp($addr);

    return $addr;
}

#-------------------------------------------------------

=head3   isAddressUsed

    Description : Check if a given address is used
    Arguments   :   User (root or non-root)
                    Node
                    Disk address
    Returns     :  0  Address used
                  -1  Address not used
    Example     : my $ans = xCAT::zvmUtils->isAddressUsed($user, $node, $address);
    
=cut

#-------------------------------------------------------
sub isAddressUsed {
    my ( $class, $user, $node, $address ) = @_;

    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }

    # Search for disk address
    my $out = `ssh -o ConnectTimeout=5 $user\@$node "$sudo /sbin/vmcp q v dasd" | grep "DASD $address"`;
    if ($out) {
        return 0;
    }

    return -1;
}

#-------------------------------------------------------

=head3   getMacID

    Description : Get the MACID from /opt/zhcp/conf/next_macid on the HCP
    Arguments   :   User (root or non-root)
                    zHCP
    Returns     : MACID
    Example     : my $macId = xCAT::zvmUtils->getMacID($user, $hcp);
    
=cut

#-------------------------------------------------------
sub getMacID {
    my ( $class, $user, $hcp ) = @_;

    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }
    
    # Check /opt/zhcp/conf directory on HCP
    my $out = `ssh -o ConnectTimeout=5 $user\@$hcp "$sudo test -d /opt/zhcp/conf && echo 'Directory exists'"`;
    if ( $out =~ m/Directory exists/i ) {

        # Check next_macid file
        $out = `ssh -o ConnectTimeout=5 $user\@$hcp "$sudo test -e /opt/zhcp/conf/next_macid && echo 'File exists'"`;
        if ( $out =~ m/File exists/i ) {

            # Do nothing
        } else {

            # Create next_macid file
            $out = `ssh -o ConnectTimeout=5 $user\@$hcp "$sudo echo 'FFFFF0' > /opt/zhcp/conf/next_macid"`;
        }
    } else {

        # Create /opt/zhcp/conf directory
        # Create next_mac - Contains next MAC address to use
        $out = `ssh -o ConnectTimeout=5 $user\@$hcp "$sudo mkdir /opt/zhcp/conf"`;
        $out = `ssh -o ConnectTimeout=5 $user\@$hcp "$sudo echo 'FFFFF0' > /opt/zhcp/conf/next_macid"`;
    }

    # Read /opt/zhcp/conf/next_macid file
    $out = `ssh -o ConnectTimeout=5 $user\@$hcp "$sudo cat /opt/zhcp/conf/next_macid"`;
    my $macId = xCAT::zvmUtils->trimStr($out);

    return $macId;
}

#-------------------------------------------------------

=head3   generateMacId

    Description : Generate a new MACID 
    Arguments   :   User (root or non-root)
                    zHCP
    Returns     : Nothing
    Example     : my $macId = xCAT::zvmUtils->generateMacId($user, $hcp);
    
=cut

#-------------------------------------------------------
sub generateMacId {
    my ( $class, $user, $hcp ) = @_;
    
    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }

    # Check /opt/zhcp/conf directory on HCP
    my $out = `ssh -o ConnectTimeout=5 $user\@$hcp "$sudo test -d /opt/zhcp/conf && echo 'Directory exists'"`;
    if ( $out =~ m/Directory exists/i ) {

        # Check next_macid file
        $out = `ssh -o ConnectTimeout=5 $user\@$hcp "$sudo test -e /opt/zhcp/conf/next_macid && echo 'File exists'"`;
        if ( $out =~ m/File exists/i ) {

            # Do nothing
        } else {

            # Create next_macid file
            $out = `ssh -o ConnectTimeout=5 $user\@$hcp "$sudo echo 'FFFFF0' > /opt/zhcp/conf/next_macid"`;
            $out = `ssh -o ConnectTimeout=5 $user\@$hcp "$sudo /bin/chmod 666 /opt/zhcp/conf/next_macid"`;
        }
    } else {

        # Create /opt/zhcp/conf directory
        # Create next_mac - Contains next MAC address to use
        $out = `ssh -o ConnectTimeout=5 $user\@$hcp "$sudo mkdir /opt/zhcp/conf"`;
        $out = `ssh -o ConnectTimeout=5 $user\@$hcp "$sudo echo 'FFFFF0' > /opt/zhcp/conf/next_macid"`;
        $out = `ssh -o ConnectTimeout=5 $user\@$hcp "$sudo /bin/chmod 666 /opt/zhcp/conf/next_macid"`;
    }

    # Read /opt/zhcp/conf/next_macid file
    $out = `ssh -o ConnectTimeout=5 $user\@$hcp "$sudo cat /opt/zhcp/conf/next_macid"`;
    my $macId = xCAT::zvmUtils->trimStr($out);
    my $int;

    if ($macId) {

        # Convert hexadecimal - decimal
        $int   = hex($macId);
        $macId = sprintf( "%d", $int );

        # Generate new MAC suffix
        $macId = $macId - 1;

        # Convert decimal - hexadecimal
        $macId = sprintf( "%X", $macId );

        # Save new MACID
        $out = `ssh -o ConnectTimeout=5 $user\@$hcp "$sudo echo $macId > /opt/zhcp/conf/next_macid"`;
    }

    return;
}

#-------------------------------------------------------

=head3   createMacAddr

    Description : Create a MAC address using the HCP MAC prefix and a given MAC suffix
    Arguments   :   User (root or non-root)
                    Node
                    MAC suffix
    Returns     : MAC address
    Example     : my $mac = xCAT::zvmUtils->createMacAddr($user, $node, $suffix);
    
=cut

#-------------------------------------------------------
sub createMacAddr {
    my ( $class, $user, $node, $suffix ) = @_;
    
    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }
    
    # Get node properties from 'zvm' table
    my @propNames = ('hcp');
    my $propVals  = xCAT::zvmUtils->getNodeProps( 'zvm', $node, @propNames );

    # Get HCP
    my $hcp = $propVals->{'hcp'};
    if ( !$hcp ) {
        return -1;
    }

    # Get USER Prefix
    my $prefix = `ssh -o ConnectTimeout=5 $user\@$hcp "$sudo /sbin/vmcp q vmlan" | egrep -i "USER Prefix:"`;
    $prefix =~ s/(.*?)USER Prefix:(.*)/$2/;
    $prefix =~ s/^\s+//;
    $prefix =~ s/\s+$//;
                        
    # Get MACADDR Prefix instead if USER Prefix is not defined
    if (!$prefix) {
        $prefix = `ssh -o ConnectTimeout=5 $user\@$hcp "$sudo /sbin/vmcp q vmlan" | egrep -i "MACADDR Prefix:"`;
        $prefix =~ s/(.*?)MACADDR Prefix:(.*)/$2/;
        $prefix =~ s/^\s+//;
        $prefix =~ s/\s+$//;
        
        if (!$prefix) {
            return -1;
        }
    }

    # Generate MAC address of source node
    my $mac = $prefix . $suffix;

    # If length is less than 12, append a zero
    if ( length($mac) != 12 ) {
        $mac = "0" . $mac;
    }

    # Format MAC address
    $mac =
        substr( $mac, 0, 2 ) . ":"
      . substr( $mac, 2,  2 ) . ":"
      . substr( $mac, 4,  2 ) . ":"
      . substr( $mac, 6,  2 ) . ":"
      . substr( $mac, 8,  2 ) . ":"
      . substr( $mac, 10, 2 );

    return $mac;
}

#-------------------------------------------------------

=head3   getOs

    Description : Get the operating system of a given node
    Arguments   :   User (root or non-root)
                    Node
    Returns     : Operating system name
    Example     : my $osName = xCAT::zvmUtils->getOs($user, $node);
    
=cut

#-------------------------------------------------------
sub getOs {

    # Get inputs
    my ( $class, $user, $node ) = @_;
    
    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }

    # Get operating system
    my $out = `ssh -o ConnectTimeout=10 $user\@$node "$sudo cat /etc/*release" | egrep -v "LSB_VERSION"`;
    my @results = split( '\n', $out );
    return ( xCAT::zvmUtils->trimStr( $results[0] ) );
}

#-------------------------------------------------------

=head3   getArch

    Description : Get the architecture of a given node
    Arguments   :   User (root or non-root)
                    Node
    Returns     : Architecture of node
    Example     : my $arch = xCAT::zvmUtils->getArch($user, $node);
    
=cut

#-------------------------------------------------------
sub getArch {

    # Get inputs
    my ( $class, $user, $node ) = @_;
    
    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }

    # Get host using VMCP
    my $arch = `ssh $user\@$node "$sudo uname -p"`;

    return ( xCAT::zvmUtils->trimStr($arch) );
}

#-------------------------------------------------------

=head3   getUserProfile

    Description : Get the user profile
    Arguments   :   User (root or non-root)
                    Profile name
    Returns     : User profile
    Example     : my $profile = xCAT::zvmUtils->getUserProfile($user, $hcp, $name);
    
=cut

#-------------------------------------------------------
sub getUserProfile {

    # Get inputs
    my ( $class, $user, $hcp, $profile ) = @_;
    
    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }

    # Set directory where executables are on zHCP
    my $hcpDir = "/opt/zhcp/bin";
        
    my $out;

    # Set directory for cache
    my $cache = '/var/opt/zhcp/cache';
    # If the cache directory does not exist
    if (!(`ssh $user\@$hcp "$sudo test -d $cache && echo Exists"`)) {
        # Create cache directory
        $out = `ssh $user\@$hcp "$sudo mkdir -p $cache"`;
    }

    # Set output file name
    my $file = "$cache/$profile.profile";

    # If a cache for the user profile exists
    if (`ssh $user\@$hcp "$sudo ls $file"`) {

        # Get current Epoch
        my $curTime = time();

        # Get time of last change as seconds since Epoch
        my $fileTime = xCAT::zvmUtils->trimStr(`ssh $user\@$hcp "$sudo stat -c %Z $file"`);

        # If the current time is greater than 5 minutes of the file timestamp
        my $interval = 300;    # 300 seconds = 5 minutes * 60 seconds/minute
        if ( $curTime > $fileTime + $interval ) {

            # Get user profiles and save it in a file
            $out = `ssh $user\@$hcp "$sudo $hcpDir/smcli Profile_Query_DM -T $profile > $file"`;
        }
    } else {

        # Get user profiles and save it in a file
        $out = `ssh $user\@$hcp "$sudo $hcpDir/smcli Profile_Query_DM -T $profile > $file"`;
    }

    # Return the file contents
    $out = `ssh $user\@$hcp "$sudo cat $file"`;
    return $out;
}

#-------------------------------------------------------

=head3   inArray

    Description : Checks if a value exists in an array
    Arguments   :   Search value
                    Search array
    Returns     : The searched expression
    Example     : my $rtn = xCAT::zvmUtils->inArray($needle, @haystack);
    
=cut

#-------------------------------------------------------
sub inArray {

    # Get inputs
    my ( $class, $needle, @haystack ) = @_;
    return grep{ $_ eq $needle } @haystack;
}

#-------------------------------------------------------

=head3   getOsVersion

    Description : Get the operating system of a given node
    Arguments   :   User (root or non-root)
                    Node
    Returns     : Operating system name
    Example     : my $os = xCAT::zvmUtils->getOsVersion($user, $node);
    
=cut

#-------------------------------------------------------
sub getOsVersion {
    
    # Get inputs
    my ( $class, $user, $node ) = @_;
    
    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }

    my $os = '';
    my $version = '';

    # Get operating system
    my $release = `ssh -o ConnectTimeout=2 $user\@$node "$sudo cat /etc/*release"`;
    my @lines = split('\n', $release);
    if (grep(/SUSE Linux Enterprise Server/, @lines)) {
        $os = 'sles';
        $version = `echo "$release" | grep "VERSION ="`;
        $version =~ s/\s*$//;
        $version =~ s/^\s*//;
        $version =~ tr/\.//;
        $version =~ s/[^0-9]*([0-9]+).*/$1/;
        $os = $os . $version;
        
        # Append service level
        $version = `echo "$release" | grep "LEVEL ="`;
        $version =~ s/\s*$//;
        $version =~ s/^\s*//;
        $version =~ tr/\.//;
        $version =~ s/[^0-9]*([0-9]+).*/$1/;
        $os = $os . 'sp' . $version;
    } elsif (grep(/Red Hat Enterprise Linux Server/, @lines)) {
        $os = 'rhel';
        $version = $lines[0];
        $version =~ tr/\.//;
        $version =~ s/([A-Za-z\s\(\)]+)//g;
        $os = $os . $version;
    }

    return xCAT::zvmUtils->trimStr($os);
}

#-------------------------------------------------------

=head3   getZfcpInfo

    Description : Get the zFCP device info
    Arguments   :   User (root or non-root)
                    Node
    Returns     : zFCP device info
    Example     : my $info = xCAT::zvmUtils->getZfcpInfo($user, $node);
    
=cut

#-------------------------------------------------------
sub getZfcpInfo {
    # Get inputs
    my ( $class, $user, $node ) = @_;
    
    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }
    
    # Get zFCP device info
    my $info = `ssh -o ConnectTimeout=5 $user\@$node "$sudo /sbin/lszfcp -D"`;
    my @zfcp = split("\n", $info);
    if (!$info || $info =~ m/No zfcp support/i || $info =~ m/No fcp devices found/i) {
        return;
    }
    
    # Get SCSI device and their attributes
    my $scsi = `ssh -o ConnectTimeout=5 $user\@$node "$sudo /usr/bin/lsscsi"`;
    $info = "";
        
    my @args;
    my $tmp;
    my $id;
    my $device;
    my $wwpn;
    my $lun;
    my $size;
    
    foreach (@zfcp) {
        @args = split(" ", $_);
        $id = $args[1];
        @args = split("/", $args[0]);
        
        $device = $args[0];
        $wwpn = $args[1];
        $lun = $args[2];
        
        # Make sure WWPN and LUN do not have 0x prefix
        $wwpn = xCAT::zvmUtils->replaceStr($wwpn, "0x", "");
        $lun = xCAT::zvmUtils->replaceStr($lun, "0x", "");
        
        # Find the device name
        $tmp = `echo "$scsi" | egrep -i $id`;
        $tmp = substr($tmp, index($tmp, "/dev/"));
        chomp($tmp);
        
        # Find the size in MiB
        $size = `ssh -o ConnectTimeout=5 $user\@$node "$sudo /usr/bin/sg_readcap $tmp" | egrep -i "Device size:"`;
        $size =~ s/Device size: //g;
        @args = split(",", $size);
        $size = xCAT::zvmUtils->trimStr($args[1]);

        $info .= "Device: $device  WWPN: 0x$wwpn  LUN: 0x$lun  Size: $size\n";
    }

    $info = xCAT::zvmUtils->tabStr($info);
    return ($info);
}

#-------------------------------------------------------

=head3   isHypervisor

    Description : Determines if a given node is in the 'hypervisor' table
    Arguments   : Node
    Returns     :   1   Node exists
                    0   Node does not exists
    Example     : my $out = xCAT::zvmUtils->isHypervisor($node);
    
=cut

#-------------------------------------------------------
sub isHypervisor {

    # Get inputs
    my ( $class, $node ) = @_;
    
    # Look in 'zvm' table
    my $tab = xCAT::Table->new( "hypervisor", -create => 1, -autocommit => 0 );

    my @results = $tab->getAllAttribsWhere( "node like '%" . $node . "%'", 'type' );
    foreach (@results) {
        
        # Return 'TRUE' if given node is in the table
        if ($_->{"type"} eq "zvm") {
            return 1;
        }
    }

    return 0;
}

#-------------------------------------------------------

=head3   getSudoer

    Description : Retrieve sudoer user name
    Arguments   : Node
    Returns     :   Sudoer user name
                    Sudo keyword
    Example     : my ($sudoer, $sudo) = xCAT::zvmUtils->getSudoer();
    
=cut

#-------------------------------------------------------
sub getSudoer {
    # Get inputs
    my ( $class ) = @_;
    
    # Use sudo or not on zHCP
    my @propNames = ('username');
    my $propVals = xCAT::zvmUtils->getTabPropsByKey( 'passwd', 'key', 'sudoer', @propNames );
    my $sudo = "sudo";
    my $user = $propVals->{'username'};
    
    if (!$user) {
        $user = "root";
    }
    
    if ($user eq "root") {
        $sudo = "";
    }
    
    return ($user, $sudo);
}

#-------------------------------------------------------

=head3   getFreeAddress

    Description : Get a free(unused) virtual address
    Arguments   :   User (root or non-root)
                    Node
                    Type (vmcp or non-vmcp)
    Returns     : vdev  An address which is free to use
                  -1    No free address is left
    Example     : my $vdev = xCAT::zvmUtils->getFreeAddress($user, $node, $type);
    
=cut

#-------------------------------------------------------
sub getFreeAddress {
    my ( $class, $user, $node, $type ) = @_;
    
    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }
    
    # Although 0000 maybe is free, we do not use it
    my $freeAddress = 1;
    my $freeAddressHex = sprintf('%04X', $freeAddress);
    
    # All device type names in VM, do not contain CPU
    my $deviceTypesVm = 'CONS|CTCA|DASD|FCP|GRAF|LINE|MSGD|OSA|PRT|PUN|RDR|SWCH|TAPE';
    # All device type names in user directory, do not contain CPU
    my $deviceTypesUserDir = 'CONSOLE|MDISK|NICDEF|SPOOL|RDEVICE'; 

    # Search for all address that is in use
    my $allUsedAddr;
    if ($type eq 'vmcp') {
        # When the node is up, vmcp can be used
        $allUsedAddr = `ssh -o ConnectTimeout=5 $user\@$node "$sudo /sbin/vmcp q v all | awk '$1 ~/^($deviceTypesVm)/ {print $2}' | sort"`;
    } else {
        # When the node is down, use zHCP to get its user directory entry
        # Get HCP
        my @propNames = ('hcp', 'userid');
        my $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $node, @propNames );
        my $hcp = $propVals->{'hcp'};

        # Get node userID
        my $userId = $propVals->{'userid'};
        
        # Get user directory entry
        my $userDirEntry = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Query_DM -T $userId"'`;
        
        # Get profile if user directory entry include a profile
        if ($userDirEntry =~ "INCLUDE ") {
            my $profileName = `cat $userDirEntry | awk '$1 ~/^(INCLUDE)/ {print $2}`;    
            $profileName = xCAT::zvmUtils->trimStr($profileName);        
            $userDirEntry .= `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Query_DM -T $profileName"`;
        }
        
        # Get all defined device address
        $allUsedAddr = `cat $userDirEntry | awk '$1 ~/^($deviceTypesUserDir)/ {print $2}' | sort`;
        # Get all linked device address
        $allUsedAddr .= `cat $userDirEntry | awk '$1 ~/^(LINK)/ {print $4}' | sort`;
    }
    
    # Loop to get the lowest free address
    while ($freeAddress < 65536 && $allUsedAddr =~ $freeAddressHex) {
        $freeAddress++;
        $freeAddressHex = sprintf('%04X', $freeAddress);
    }   
    
    if ($freeAddress < 65536) {
        return $freeAddressHex;
    }

    return -1;
}

#-------------------------------------------------------

=head3   getUsedCpuTime

    Description : Get used CPU time of instance
    Arguments   :   User (root or non-root)
                    zHCP (to query on)
                    node
    Returns     : In nanoseconds for used CPU time
    Example     : my $out = xCAT::zvmUtils->getUsedCpuTime($hcp, $node);
    
=cut

#-------------------------------------------------------
sub getUsedCpuTime {
    my ( $class, $user, $hcp , $node ) = @_;

    # Directory where executables are
    my $dir = '/opt/zhcp/bin';
    
    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }
    
    my $userId = xCAT::zvmCPUtils->getUserId($user, $node);
    
    # Call IUO function to query CPU used time
    my $time = `ssh $user\@$hcp "$sudo $dir/smcli Image_Performance_Query -T $userId -c 1" | egrep -i "Used CPU time:"`;
    $time =~ s/^Used CPU time:(.*)/$1/;
    $time =~ s/"//g;
    $time =~ s/^\s+//;
    $time =~ s/\s+$//;
    if (!$time) {
        $time = 0;
    }
    
    # Not found, return 0
    return $time;
}


#-------------------------------------------------------

=head3   getUpTime

    Description : Get running time of an instance
    Arguments   :   User (root or non-root)
                    Node
    Returns     : Running time
    Example     : my $out = xCAT::zvmUtils->getUpTime($user, $node);
    
=cut

#-------------------------------------------------------
sub getUpTime {
    my ( $class, $user, $node ) = @_;
    
    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }
 
    my $out = `ssh -o ConnectTimeout=5 $user\@$node "$sudo uptime"`;
    $out = xCAT::zvmUtils->trimStr($out);
    $out =~ /.*up +(?:(\d+) days?,? +)?(\d+):(\d+),.*/;
    my $uptime;
    
    if (!$1 && !$2) {
        # Special case for less than 1 hour, will display X min
        $out =~ /.*up +(\d+) min,.*/;
        $uptime = "0 days $3 min";
    } elsif (!$1) {
        # Special case for less than 1 day, will display X hr X min
        $uptime = "0 days $2 hr $3 min";
    } else {
        $uptime = "$1 days $2 hr $3 min";
    }
    
    return ($uptime);
}

#-------------------------------------------------------

=head3   getSizeFromByte

    Description : Return disk size (G or M) from given bytes
    Arguments   : Bytes
    Returns     : Size string
    Example     : my $out = xCAT::zvmUtils->getSizeFromByte($bytes);
    
=cut

#-------------------------------------------------------
sub getSizeFromByte {
    my ( $class, $bytes ) = @_;

    my $size = ($bytes)/(1024*1024);
    if ($size > (1024*5)) {
        $size = ($size / 1024);
        # If the size > 5G, will use G to represent 
        $size = sprintf("%.1f",$size);
        $size = $size . 'G';
    } else {
        # If the size < 5G, will use M to represent
        $size = sprintf("%d",$size);
        $size = $size . 'M';
    }

    return ($size);
}


#-------------------------------------------------------

=head3   getSizeFromCyl

    Description : Return disk size (G or M) from given cylinders
    Arguments   : Node
    Returns     : Size string
    Example     : my $out = xCAT::zvmUtils->getSizeFromCyl($cyl);
    
=cut

#-------------------------------------------------------
sub getSizeFromCyl {
    my ($class, $cyl) = @_;

    my $bytes = ($cyl * 737280);
    my $size = xCAT::zvmUtils->getSizeFromByte($bytes);

    return ($size);
}

#-------------------------------------------------------

=head3   getSizeFromPage

    Description : Return disk size (G or M) from given pages
    Arguments   : Page
    Returns     : Size string
    Example     : my $out = xCAT::zvmUtils->getSizeFromPage($page);
    
=cut

#-------------------------------------------------------
sub getSizeFromPage {
    my ( $class, $page ) = @_;

    my $bytes = ($page * 4096);
    my $size = xCAT::zvmUtils->getSizeFromByte($bytes);

    return ($size);
}


#-------------------------------------------------------

=head3   getLparCpuTotal

    Description : Get total count of logical CPUs in the LPAR
    Arguments   :   User (root or non-root)
                    zHCP
    Returns     : Total CPU count
    Example     : my $out = xCAT::zvmCPUtils->getLparCpuTotal($user, $hcp);
    
=cut

#-------------------------------------------------------
sub getLparCpuTotal {
    my ($class, $user, $hcp) = @_;
    
    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }

    my $out = `ssh -o ConnectTimeout=5 $user\@$hcp "$sudo cat /proc/sysinfo" | grep "LPAR CPUs Total"`;

    my @results = split(' ', $out);
    return ($results[3]);
}

#-------------------------------------------------------

=head3   getLparCpuUsed

    Description : Get count of used logical CPUs in the LPAR
    Arguments   :   User (root or non-root)
                    zHCP
    Returns     : Used CPU count
    Example     : my $out = xCAT::zvmCPUtils->getLparCpuUsed($user, $hcp);
    
=cut

#-------------------------------------------------------
sub getLparCpuUsed {
    my ($class, $user, $hcp) = @_;

    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }
    
    my $out = `ssh -o ConnectTimeout=5 $user\@$hcp "$sudo cat /proc/sysinfo" | grep "LPAR CPUs Configured"`;

    my @results = split(' ', $out);
    return ($results[3]);
}

#-------------------------------------------------------

=head3   getCecModel

    Description : Get the model of this CEC (LPAR)
    Arguments   :   User (root or non-root)
                    zHCP
    Returns     : Model of this CEC
    Example     : my $out = xCAT::zvmCPUtils->getCecModel($user, $hcp);
    
=cut

#-------------------------------------------------------
sub getCecModel {
    my ($class, $user, $hcp) = @_;

    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }

    my $out = `ssh -o ConnectTimeout=5 $user\@$hcp "$sudo cat /proc/sysinfo" | grep "^Type:"`;
    my @results = split(' ', $out);

    return ($results[1]);
}

#-------------------------------------------------------

=head3   getCecVendor

    Description : Get the vendor of this CEC (LPAR)
    Arguments   :   User (root or non-root)
                    zHCP
    Returns     : Vendor of this CEC
    Example     : my $out = xCAT::zvmCPUtils->getCecVendor($user, $hcp);
    
=cut

#-------------------------------------------------------
sub getCecVendor {
    my ( $class, $user, $hcp ) = @_;

    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }

    my $out = `ssh -o ConnectTimeout=5 $user\@$hcp "$sudo cat /proc/sysinfo" | grep "Manufacturer"`;
    my @results = split(' ', $out);

    return ($results[1]);
}

#-------------------------------------------------------

=head3   getHypervisorInfo

    Description : Get the info(name & version) for this hypervisor
    Arguments   :   User (root or non-root)
                    zHCP
    Returns     : Name & version of this hypervisor
    Example     : my $out = xCAT::zvmCPUtils->getHypervisorInfo($user, $hcp);
    
=cut

#-------------------------------------------------------
sub getHypervisorInfo {
    my ($class, $user, $hcp) = @_;

    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }
    
    my $out = `ssh -o ConnectTimeout=5 $user\@$hcp "$sudo cat /proc/sysinfo" | grep "VM00 Control Program"`;
    my @results = split(' ', $out);

    my $str = "$results[3] $results[4]";

    return ($str);
}

#-------------------------------------------------------

=head3   getLparMemoryTotal

    Description : Get the total physical memory of this LPAR
    Arguments   :   User (root or non-root)
                    zHCP
    Returns     : Total physical memory 
    Example     : my $out = xCAT::zvmCPUtils->getLparMemoryTotal($user, $hcp);
    
=cut

#-------------------------------------------------------
sub getLparMemoryTotal {
    my ($class, $user, $hcp) = @_;

    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }
    
    my $out = `ssh $user\@$hcp "$sudo /opt/zhcp/bin/smcli System_Info_Query" | grep "real storage"`;
    my @results = split(' ', $out);

    return ($results[5]);
}

#-------------------------------------------------------

=head3   getLparMemoryOffline

    Description : Get the offline physical memory of this LPAR
    Arguments   :   User (root or non-root)
                    zHCP
    Returns     : Offline physical memory 
    Example     : my $out = xCAT::zvmCPUtils->getLparMemoryOffline($user, $hcp);
    
=cut

#-------------------------------------------------------
sub getLparMemoryOffline {
    my ($class, $user, $hcp) = @_;

    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }
    
    my $out = `ssh $user\@$hcp "$sudo /opt/zhcp/bin/smcli System_Info_Query" | grep "real storage"`;
    my @results = split(' ', $out);

    return ($results[14]);
}

#-------------------------------------------------------

=head3   getLparMemoryUsed

    Description : Get the used physical memory of this LPAR
    Arguments   :   User (root or non-root)
                    zHCP
    Returns     : Used physical memory 
    Example     : my $out = xCAT::zvmCPUtils->getLparMemoryUsed($user, $hcp);
    
=cut

#-------------------------------------------------------
sub getLparMemoryUsed {
    my ($class, $user, $hcp) = @_;

    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }
    
    my $out = `ssh $user\@$hcp "$sudo /opt/zhcp/bin/smcli System_Performance_Info_Query " | grep "Used memory pages:"`;
    my @results = split(':', $out);
    
    my $page = xCAT::zvmUtils->trimStr( $results[1] );
    my $size = xCAT::zvmUtils->getSizeFromPage( $page );
    
    return ($size);
}

#-------------------------------------------------------

=head3   getDiskPoolUsed

    Description : Get the used size of specified disk pool 
    Arguments   :   User (root or non-root)
                    zHCP
                    Disk pool
    Returns     : Used size of specified disk pool 
    Example     : my $out = xCAT::zvmCPUtils->getDiskPoolUsed($user, $hcp, $diskpool);
    
=cut

#-------------------------------------------------------
sub getDiskPoolUsed {
    my ($class, $user, $hcp, $diskpool) = @_;

    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }
    
    my $hcpUserId = xCAT::zvmCPUtils->getUserId($user, $hcp);

    my $out = `ssh $user\@$hcp "$sudo /opt/zhcp/bin/smcli Image_Volume_Space_Query_DM -q 3 -e 3 -n $diskpool -T $hcpUserId"`;
    my @lines = split('\n', $out);
    my @results;
    my $used = 0;

    foreach (@lines) {
        @results = split(' ', $_);
        if ($results[1] =~ '^9336') {
            # Change the format from blocks (512 byte) to cylinder (737280)
            my $cyls = ($results[3] * 512)/(737280);
            $used += $cyls;
        } elsif ($results[1] =~ '^3390') {
            $used += $results[3];
        }
    }
    
    return ($used);
}

#-------------------------------------------------------

=head3   getDiskPoolFree

    Description : Get the free size of specified disk pool 
    Arguments   :   User (root or non-root)
                    zHCP 
                    Disk pool
    Returns     : Free size of specified disk pool 
    Example     : my $out = xCAT::zvmCPUtils->getDiskPoolFree($user, $hcp, $diskpool);
    
=cut

#-------------------------------------------------------
sub getDiskPoolFree {
    my ($class, $user, $hcp, $diskpool) = @_;
    
    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }

    my $hcpUserId = xCAT::zvmCPUtils->getUserId($user, $hcp);

    my $out = `ssh $user\@$hcp "$sudo /opt/zhcp/bin/smcli Image_Volume_Space_Query_DM -q 2 -e 3 -n $diskpool -T $hcpUserId"`;
    my @lines = split('\n', $out);
    my @results;
    my $free = 0;

    foreach (@lines) {
        @results = split(' ', $_);
        if ($results[1] =~ '^9336') {
            # Change the format from blocks (512 byte) to cylinder (737280)
            my $cyls = ( $results[3] * 512 ) / ( 737280 );
            $free += $cyls;
        } elsif ($results[1] =~ '^3390') {
            $free += $results[3];
        }
    }
    
    return ($free);
}

#-------------------------------------------------------

=head3   getMaxMemory

    Description : Get the max memory of a given node
    Arguments   :   User (root or non-root)
                    zHCP 
                    Node
    Returns     : Max memory
    Example     : my $maxMemory = xCAT::zvmCPUtils->getMaxMemory($user, $hcp, $node);
    
=cut

#-------------------------------------------------------
sub getMaxMemory {
    my ($class, $user, $hcp , $node) = @_;

    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }

    my $userId = xCAT::zvmCPUtils->getUserId( $user, $node );

    # Query the maximum memory allowed in user directory entry
    my $out = `ssh $user\@$hcp "$sudo /opt/zhcp/bin/smcli Image_Definition_Query_DM -T $userId -k STORAGE_MAXIMUM"`;
    my @results = split('=', $out);

    return ($results[1]);
}

#-------------------------------------------------------

=head3   smapi4xcat

    Description : Verify if SMAPI EXEC (xCAT_Commands_IUO) exists
    Arguments   :   User (root or non-root)
                    zHCP
    Returns     :   0  EXEC not found
                    1  EXEC found
    Example     : my $out = xCAT::zvmUtils->smapi4xcat($user, $hcp);
    
=cut

#-------------------------------------------------------
sub smapi4xcat {
    my ( $class, $user, $hcp ) = @_;
    
    # Directory where executables are
    my $dir = '/opt/zhcp/bin';
    
    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }
    
    # Get zHCP user ID
    my $hcpUserId = xCAT::zvmCPUtils->getUserId($user, $hcp);
    $hcpUserId =~ tr/a-z/A-Z/;
    
    # Check SMAPI level
    # Levels 621 and greater support SMAPI EXEC
    my $out = `ssh $user\@$hcp "$sudo $dir/smcli Query_API_Functional_Level -T $hcpUserId"`;
    $out = xCAT::zvmUtils->trimStr($out);
    if ( !($out =~ m/V6.2/i || $out =~ m/V6.1/i || $out =~ m/V5.4/i) ) {
        return 1;
    }
    
    # Check if SMAPI EXEC exists
    # EXEC found if RC = 8 and RS = 3002
    $out = `ssh $user\@$hcp "$sudo $dir/smcli xCAT_Commands_IUO -T $hcpUserId -c ''"`;
    $out = xCAT::zvmUtils->trimStr($out);
    if ( $out =~ m/Return Code: 8/i && $out =~ m/Reason Code: 3002/i ) {
        return 1;
    } 

    return 0;
}

#-------------------------------------------------------

=head3   generateUserEntryFile

    Description : Generate a user entry file without Mdisk
    Arguments   :   UserId
                    Password
                    Memory
                    Privilege
                    Profile
                    Cpu
    Returns     : If successful, return file path. Otherwise, return -1
    Example     : my $out = xCAT::zvmUtils->generateUserEntryFile($userId, $password, $memorySize, $privilege, $profileName, $cpuCount);
    
=cut

#-------------------------------------------------------
sub generateUserEntryFile {
    my ( $class, $userId, $password, $memorySize, $privilege, $profileName, $cpuCount ) = @_;

    # If a file of this name already exists, just override it
    my $file = "/tmp/$userId.txt";
    my $content = "USER $userId $password $memorySize $memorySize $privilege\nINCLUDE $profileName\nCPU 00 BASE\n";
    
    # Add additional CPUs
    my $i;
    for ( $i = 1; $i < $cpuCount; $i++ ) {
        $content = $content.sprintf("CPU %02X\n", $i)
    }
    
    unless (open(FILE, ">$file")) {
        return -1;
    }
    
    print FILE $content;    
    close(FILE);
      
    return $file;    
}

#-------------------------------------------------------

=head3   querySSI

    Description : Obtain the SSI and system status
    Arguments   :   User (root or non-root)
                    zHCP
    Returns     : SSI cluster name
    Example     : my $out = xCAT::zvmUtils->querySSI($user, $hcp);
    
=cut

#-------------------------------------------------------
sub querySSI {
    my ( $class, $user, $hcp ) = @_;
    
    # Directory where executables are
    my $dir = '/opt/zhcp/bin';
    
    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }
    
    my $ssi = `ssh -o ConnectTimeout=10 $user\@$hcp "$sudo $dir/smcli SSI_Query" | egrep -i "ssi_name"`;
    $ssi =~ s/ssi_name = //;
    $ssi =~ s/\s*$//;
    $ssi =~ s/^\s*//;
    
    return $ssi;
}

#-------------------------------------------------------

=head3   rExecute

    Description : Execute a remote command
    Arguments   :   User (root or non-root)
                    Node
                    Command to execute
    Returns     : Output returned from executing command
    Example     : my $out = xCAT::zvmUtils->rExecute($user, $node, $cmd);
    
=cut

#-------------------------------------------------------
sub rExecute {
    my ( $class, $user, $node, $cmd ) = @_;
    
    my $out;
    my $sudo = "sudo";
    if ($user eq "root") {
        # Just execute the command if root        
        $out = `ssh $user\@$node "$cmd"`;
        return $out;
    }
    
    # Encapsulate command in single quotes
    $cmd = "'" . $cmd . "'";
    $out = `ssh $user\@$node "$sudo sh -c $cmd"`;
    return $out;
}

#-------------------------------------------------------

=head3   getUsedFcpDevices

    Description : Get a list of used FCP devices in the zFCP pools
    Arguments   :   User (root or non-root)
                    zHCP
    Returns     : List of known FCP devices
    Example     : my %devices = xCAT::zvmUtils->getUsedFcpDevices($user, $zhcp);
    
=cut

#-------------------------------------------------------
sub getUsedFcpDevices {
    my ( $class, $user, $hcp ) = @_;
    
    # Directory where zFCP pools are
    my $pool = "/var/opt/zhcp/zfcp";
    
    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }
    
    # Grep the pools for used or allocated zFCP devices
    my %usedDevices;
    my @args;
    my @devices = split("\n", `ssh $user\@$hcp "$sudo cat $pool/*.conf" | egrep -i "used|allocated"`);
    foreach (@devices) {
        @args = split(",", $_);
        
        # Sample pool configuration file:
        #   #status,wwpn,lun,size,range,owner,channel,tag
        #     used,1000000000000000,2000000000000110,8g,3B00-3B3F,ihost1,1a23,$root_device$
        #     free,1000000000000000,2000000000000111,,3B00-3B3F,,,
        #     free,1230000000000000,2000000000000112,,3B00-3B3F,,,
        $args[6] = xCAT::zvmUtils->trimStr($args[6]);
        
        # Push used or allocated devices into hash 
        if ($args[6]) {
            $usedDevices{uc($args[6])} = 1;
        }
    }
    
    return %usedDevices;
}

#-------------------------------------------------------

=head3   establishMount

    Description : Establish an NFS mount point on a zHCP system.
    Arguments   : Sudoer user name
                  Sudo keyword
                  zHCP hostname
                  Local directory to remotely mount
                  Mount access ('ro' for read only, 'rw' for read write)
                  Directory as known to zHCP (out)
    Returns     : 0 - Mounted, or zHCP and MN are on the same system
                  1 - Mount failed
    Example     : establishMount( $callback, $::SUDOER, $::SUDO, $hcp, "$installRoot/$provMethod", "ro", \$remoteDeployDir );
    
=cut

#-------------------------------------------------------
sub establishMount {
    # Get inputs
    my ($class, $callback, $sudoer, $sudo, $hcp, $localDir, $access, $mountedPt) = @_;    
    my $out;

    # If the target system is not on this system then establish the NFS mount point.
    my $hcpIP = xCAT::NetworkUtils->getipaddr( $hcp );
    if (! defined $hcpIP) {
        xCAT::zvmUtils->printLn( $callback, "(Error) Unable to obtain the IP address of the hcp node" );
        return 1;
    }
    
    my $masterIp = xCAT::TableUtils->get_site_Master();
    if (! defined $masterIp) {
        xCAT::zvmUtils->printLn( $callback, "$hcp: (Error) Unable to obtain the management node IP address from the site table" );
        return 1;
    }
    
    if ($masterIp eq $hcpIP) {
        # xCAT MN and zHCP are on the same box and will use the same directory without the need for an NFS mount.
        $$mountedPt = $localDir;
    } else {
        # Determine the hostname for this management node
        my $masterHostname = Sys::Hostname::hostname();
        if (! defined $masterHostname) {
            # For some reason, the xCAT MN's hostname is not known.  We pass along the IP address instead.
            $masterHostname = $masterIp;
        }
        
        xCAT::zvmUtils->printSyslog( "establishMount() Preparing the NFS mount point on zHCP ($hcpIP) to xCAT MN $masterHostname($masterIp) for $localDir" );
        
        # Prepare the staging mount point on zHCP, if they need to be established
        $$mountedPt = "/mnt/$masterHostname$localDir";
        my $rc = `ssh $sudoer\@$hcp "$sudo mkdir -p $$mountedPt && mount -t nfs -o $access $masterIp:$localDir $$mountedPt; echo \\\$?"`;
        
        # Return code = 0 (mount succeeded) or 32 (mount already exists)
        if ($rc != '0' && $rc != '32') {
            xCAT::zvmUtils->printLn( $callback, "$hcp: (Error) Unable to establish zHCP mount point: $$mountedPt" );
            return 1;
        }
    }
    
    return 0;
}

#-------------------------------------------------------

=head3   getFreeRepoSpace

    Description : Get the free space of image repository under /install
    Arguments   : Node
    Returns     : The available space for /install
    Example     : my $free = getFreeRepoSpace($callback, $node);
    
=cut

#-------------------------------------------------------
sub getFreeRepoSpace {
    # Get inputs
    my ($class, $user, $node) = @_;
    
    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }
    
    # Check if node is the management node
    my @entries = xCAT::TableUtils->get_site_attribute("master");
    my $master = xCAT::zvmUtils->trimStr($entries[0]);
    my $ip = xCAT::NetworkUtils->getipaddr($node);
    $ip = xCAT::zvmUtils->trimStr($ip);
    my $mn = 0;
    if ($master eq $ip) {
        # If the master IP and node IP match, then it is the management node
        my $out = `$sudo /bin/df -h /install | sed 1d`;
        $out =~ s/\h+/ /g;
        my @results = split(' ', $out);
        return ($results[3]);
    } 

    return;
}

#-------------------------------------------------------

=head3   findAndUpdatezFcpPool

    Description : Find and update a SCSI/FCP device in a given storage pool.
                  xCAT will find and update the SCSI/FCP device in all known pools based on the unique WWPN/LUN combo.
    Arguments   :   Message header
                    User (root or non-root)
                    zHCP
                    Storage pool
                    Criteria hash including:
                        - Status (free, reserved, or used)
                        - zFCP channel
                        - WWPN
                        - LUN
                        - Size requested
                        - Owner
                        - Tag                                      
    Returns     :   Results hash including:
                        - Return code (0 = Success, -1 = Failure)
                        - zFCP device (if one is requested)
                        - WWPN
                        - LUN
    Example     : my $resultsRef = xCAT::zvmUtils->findAndUpdatezFcpPool($callback, $header, $user, $hcp, $pool, $criteriaRef);
    
=cut

#-------------------------------------------------------
sub findAndUpdatezFcpPool {
    # Get inputs
    my ($class, $callback, $header, $user, $hcp, $pool, $criteriaRef) = @_;
        
    # Determine if sudo is used
    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }
    
    # Directory where executables are on zHCP
    my $dir = "/opt/zhcp/bin";
        
    # Directory where FCP disk pools are on zHCP
    my $zfcpDir = "/var/opt/zhcp/zfcp";
    
    my %results = ('rc' => -1);  # Default to error

    # Extract criteria
    my %criteria = %$criteriaRef;
    my $status = defined($criteria{status}) ? $criteria{status} : "";
    my $fcpDevice = defined($criteria{fcp}) ? $criteria{fcp} : "";
    my $wwpn = defined($criteria{wwpn}) ? $criteria{wwpn} : "";
    my $lun = defined($criteria{lun}) ? $criteria{lun} : "";
    my $size = defined($criteria{size}) ? $criteria{size} : "";
    my $owner = defined($criteria{owner}) ? $criteria{owner} : "";
    my $tag = defined($criteria{tag}) ? $criteria{tag} : "";
    
    # Check required arguments: pool, status
    # If you do not know what to update, why update!
    if (!$pool && !$status) {
       return \%results;
    }
        
    # Check status
    if ($status !~ m/^(free|used|reserved)$/i) {
        xCAT::zvmUtils->printLn($callback, "$header: (Error) Status not recognized. Status can be free, used, or reserved.");
        return \%results;
    }
    
    # Check FCP device syntax
    if ($fcpDevice && ($fcpDevice !~ /^auto/i) && ($fcpDevice =~ /[^0-9a-f]/i)) {
        xCAT::zvmUtils->printLn($callback, "$header: (Error) Invalid FCP channel address $fcpDevice.");
        return \%results;
    }
    
    # Check WWPN and LUN syntax
    if ( $wwpn && ($wwpn =~ /[^0-9a-f;"]/i) ) {
        xCAT::zvmUtils->printLn( $callback, "$header: (Error) Invalid world wide portname $wwpn." );
        return \%results;
    } if ( $lun && ($lun =~ /[^0-9a-f]/i) ) {
        xCAT::zvmUtils->printLn( $callback, "$header: (Error) Invalid logical unit number $lun." );
        return \%results;
    }
        
    # Size can be M(egabytes) or G(igabytes). Convert size into MB.
    my $originSize = $size;
    if ($size) {
        if ($size =~ m/G/i) {
            # Convert to MegaBytes
            $size =~ s/\D//g;
            $size = int($size) * 1024
        } elsif ($size =~ m/M/i || !$size) {
            # Do nothing
        } else {
            xCAT::zvmUtils->printLn( $callback, "$header: (Error) Size not recognized. Size can be M(egabytes) or G(igabytes)." );
            return \%results;
        }
    }
        
    # Check if WWPN and LUN are given
    # WWPN can be given as a semi-colon separated list (multipathing)
    my $useWwpnLun = 0;
    if ($wwpn && $lun) {
        xCAT::zvmUtils->printLn($callback, "$header: Using given WWPN and LUN");
        $useWwpnLun = 1;
        
        # Make sure WWPN and LUN do not have 0x prefix
        $wwpn = xCAT::zvmUtils->replaceStr($wwpn, "0x", "");
        $lun = xCAT::zvmUtils->replaceStr($lun, "0x", "");
    }
    
    # Find disk pool (create one if non-existent)
    my $out;
    if (!(`ssh $user\@$hcp "$sudo test -d $zfcpDir && echo Exists"`)) {
        # Create pool directory
        $out = `ssh $user\@$hcp "$sudo mkdir -p $zfcpDir"`;
    }
    
    # Find if disk pool exists
    if (!(`ssh $user\@$hcp "$sudo test -e $zfcpDir/$pool.conf && echo Exists"`)) {
        # Return if xCAT is expected to find a FCP device, but no disk pool exists.
        xCAT::zvmUtils->printLn($callback, "$header: (Error) FCP storage pool does not exist");
        return \%results;
    }
        
    # Find a free disk in the pool
    # FCP devices are contained in /var/opt/zhcp/zfcp/<pool-name>.conf   
    my $range = "";
    my $sizeFound = "*";
    my @info;
    if (!$useWwpnLun) {
        # Find a suitable pair of WWPN and LUN in device pool based on requested size
        # Sample pool configuration file:
        #   #status,wwpn,lun,size,range,owner,channel,tag
        #     used,1000000000000000,2000000000000110,8g,3B00-3B3F,ihost1,1a23,$root_device$
        #     free,1000000000000000,2000000000000111,,3B00-3B3F,,,
        #     free,1230000000000000;4560000000000000,2000000000000112,,3B00-3B3F,,,
        my @devices = split("\n", `ssh $user\@$hcp "$sudo cat $zfcpDir/$pool.conf" | egrep -i ^free`);            
        $sizeFound = 0;
        foreach (@devices) {
            @info = split(',', $_);
                    
            # Check if the size is sufficient. Convert size into MB.
            if ($info[3] =~ m/G/i) {
                # Convert to MegaBytes
                $info[3] =~ s/\D//g;
                $info[3] = int($info[3]) * 1024
            } elsif ($info[3] =~ m/M/i) {
                # Do nothing
                $info[3] =~ s/\D//g;
            } else {
                next;
            }
            
            # Find optimal disk based on requested size
            if ($sizeFound && $info[3] >= $size && $info[3] < $sizeFound) {
                $sizeFound = $info[3];
                $wwpn = $info[1];                    
                $lun = $info[2];
                $range = $info[4];
            } elsif (!$sizeFound && $info[3] >= $size) {
                $sizeFound = $info[3];
                $wwpn = $info[1];
                $lun = $info[2];   
                $range = $info[4];       
            }
        }
        
        # Do not continue if no devices can be found
        if (!$wwpn && !$lun) {
            xCAT::zvmUtils->printLn($callback, "$header: (Error) A suitable device of $size" . "M or larger could not be found");
            return \%results;
        }
    } else {
    	# Find given WWPN and LUN. Do not continue if device is used
        my $select = `ssh $user\@$hcp "$sudo cat $zfcpDir/$pool.conf" | grep -i "$wwpn,$lun"`;
        chomp($select);
        
        @info = split(',', $select);
        
        if ($size) {
            if ($info[3] =~ m/G/i) {
                # Convert to MegaBytes
                $info[3] =~ s/\D//g;
                $info[3] = int($info[3]) * 1024
            } elsif ($info[3] =~ m/M/i) {
                # Do nothing
                $info[3] =~ s/\D//g;
            } else {
                next;
            }
                
            # Do not continue if specified device does not have enough capacity
            if ($info[3] < $size) {
                xCAT::zvmUtils->printLn($callback, "$header: (Error) FCP device $wwpn/$lun is not large enough");
                return \%results;
            }
        }

        # Find range of the specified disk
        $range = $info[4];
    }
       
    # If there are multiple paths, take the 1st one
    # Handle multi-pathing in postscript because autoyast/kickstart does not support it.
    my $origWwpn = $wwpn;
    if ($wwpn =~ m/;/i) {
        @info = split(';', $wwpn);
        $wwpn = xCAT::zvmUtils->trimStr($info[0]);
    }
        
    xCAT::zvmUtils->printLn($callback, "$header: Found FCP device 0x$wwpn/0x$lun");
        
    # Find a free FCP device based on the given range
    if ($fcpDevice =~ m/^auto/i) {
        my @ranges;
        my $min;
        my $max;
        my $found = 0;
                
        if ($range =~ m/;/i) {
            @ranges = split(';', $range);
        } else {
            push(@ranges, $range);
        }
                    
        if (!$found) {
            # If the node has an eligible FCP device, use it
            my @deviceList = xCAT::zvmUtils->getDedicates($callback, $user, $owner);
            foreach (@deviceList) {
                # Check if this devide is eligible (among the range specified for disk $lun)
                @info = split(' ', $_);
                my $candidate = $info[2];
                foreach (@ranges) {
                    ($min, $max) = split('-', $_);
                    if (hex($candidate) >= hex($min) && hex($candidate) <= hex($max)) {
                        $found = 1;
                        $fcpDevice = uc($candidate);
                        
                        last;
                    }
                }
                
                if ($found) {
                	xCAT::zvmUtils->printLn($callback, "$header: Found eligible FCP channel $fcpDevice");
                    last;
                }       
            }
        }
        
        if (!$found) {
            # If the node has no eligible FCP device, find a free one for it.
            my %usedDevices = xCAT::zvmUtils->getUsedFcpDevices($user, $hcp);
            
            my $hcpUserId = xCAT::zvmCPUtils->getUserId($user, $hcp);
            $hcpUserId =~ tr/a-z/A-Z/;
        
            # Find a free FCP channel
            $out = `ssh $user\@$hcp "$sudo $dir/smcli System_WWPN_Query -T $hcpUserId" | egrep -i "FCP device number|Status"`;
            my @devices = split( "\n", $out );
            for (my $i = 0; $i < @devices; $i++) {
                # Extract the device number and status
                $fcpDevice = $devices[$i];
                $fcpDevice =~ s/^FCP device number:(.*)/$1/;
                $fcpDevice =~ s/^\s+//;
                $fcpDevice =~ s/\s+$//;
                        
                $i++;
                my $fcpStatus = $devices[$i];
                $fcpStatus =~ s/^Status:(.*)/$1/;
                $fcpStatus =~ s/^\s+//;
                $fcpStatus =~ s/\s+$//;                    
                        
                # Only look at free FCP devices
                if ($fcpStatus =~ m/free/i) {                    
                    # If the device number is within the specified range, exit out of loop
                    # Range: 3B00-3C00;4B00-4C00;5E12-5E12
                    foreach (@ranges) {
                        ($min, $max) = split('-', $_);
                        if (hex($fcpDevice) >= hex($min) && hex($fcpDevice) <= hex($max)) {
                            $fcpDevice = uc($fcpDevice);
                
                            # Used found FCP channel if not in use or allocated                        
                            if (!$usedDevices{$fcpDevice}) {
                                $found = 1;
                                last;
                            }
                        }
                    }
                }
                
                # Break out of loop if FCP channel is found
                if ($found) {
                	xCAT::zvmUtils->printLn($callback, "$header: Found FCP channel within acceptable range $fcpDevice");
                    last;
                }
            }
        }
            
        # Do not continue if no FCP channel is found
        if (!$found) {
            xCAT::zvmUtils->printLn($callback, "$header: (Error) A suitable FCP channel could not be found");
            return \%results;
        }
    }
    
    # If there are multiple devices (multipathing), take the 1st one
    if ($fcpDevice) {
        if ($fcpDevice =~ m/;/i) {
            @info = split(';', $fcpDevice);
            $fcpDevice = xCAT::zvmUtils->trimStr($info[0]);
        }
                    
        # Make sure channel has a length of 4
        while (length($fcpDevice) < 4) {
            $fcpDevice = "0" . $fcpDevice;
        }
    }
            
    # Mark WWPN and LUN as used, free, or reserved and set the owner/channel appropriately
    # This config file keeps track of the owner of each device, which is useful in nodeset
    $size = $size . "M";
    my $select = `ssh $user\@$hcp "$sudo cat $zfcpDir/$pool.conf" | grep -i "$lun" | grep -i "$wwpn"`;
    chomp($select);
    if ($select) {
        @info = split(',', $select);
        
        if (!$info[3]) {
            $info[3] = $size;
        }
            
        # Do not update if WWPN/LUN pair is specified but the pair does not exist
        if (!($info[1] =~ m/$wwpn/i)) {
            xCAT::zvmUtils->printLn($callback, "$header: (Error) FCP device $wwpn/$lun does not exists");
            return \%results;
        }
                    
        # Entry order: status,wwpn,lun,size,range,owner,channel,tag
        # The following are never updated: wwpn, lun, size, and range
        my $update = "$status,$info[1],$info[2],$info[3],$info[4],$owner,$fcpDevice,$tag";
        my $expression = "'s#" . $select . "#" .$update . "#i'";
        $out = `ssh $user\@$hcp "$sudo sed --in-place -e $expression $zfcpDir/$pool.conf"`;
    } else {
        # Insert device entry into file
        $out = `ssh $user\@$hcp "$sudo echo \"$status,$origWwpn,$lun,$size,,$owner,$fcpDevice,$tag\" >> $zfcpDir/$pool.conf"`;
    }

    # Generate results hash
    %results = (
        'rc' => 0,
        'fcp' => $fcpDevice,
        'wwpn' => $wwpn,
        'lun' => $lun
    );
    return \%results;
}

#-------------------------------------------------------

=head3   findzFcpDevicePool

    Description : Find the zFCP storage pool that contains the given zFCP device
    Arguments   :   User (root or non-root)
                    zHCP
                    WWPN
                    LUN
    Returns     : Storage pool where zFCP device resides
    Example     : my $pool = xCAT::zvmUtils->findzFcpDevicePool($user, $hcp, $wwpn, $lun);
    
=cut

#-------------------------------------------------------
sub findzFcpDevicePool {

    # Get inputs
    my ( $class, $user, $hcp, $wwpn, $lun ) = @_;
    
    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }
            
    # Directory where FCP disk pools are on zHCP
    my $zfcpDir = "/var/opt/zhcp/zfcp";

    # Find the pool that contains the SCSI/FCP device
    my @pools = split("\n", `ssh $user\@$hcp "$sudo grep -i -l \"$wwpn,$lun\" $zfcpDir/*.conf"`);
    my $pool = ""; 
    if (scalar(@pools)) {
        $pool = basename($pools[0]);
        $pool =~ s/\.[^.]+$//;  # Do not use extension
    }

    return $pool;
}

#-------------------------------------------------------

=head3   findzFcpDeviceAttr

    Description : Find the zFCP device attributes
    Arguments   :   User (root or non-root)
                    zHCP
                    Storage pool
                    WWPN
                    LUN
    Returns     : Architecture of node
    Example     : my $deviceRef = xCAT::zvmUtils->findzFcpDeviceAttr($user, $hcp, $wwpn, $lun);
    
=cut

#-------------------------------------------------------
sub findzFcpDeviceAttr {

    # Get inputs
    my ( $class, $user, $hcp, $pool, $wwpn, $lun ) = @_;
    
    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }
            
    # Directory where FCP disk pools are on zHCP
    my $zfcpDir = "/var/opt/zhcp/zfcp";

    # Find the SCSI/FCP device
    # Entry order: status,wwpn,lun,size,range,owner,channel,tag
    my @info = split("\n", `ssh $user\@$hcp "$sudo grep \"$wwpn,$lun\" $zfcpDir/$pool.conf"`);
    my $entry = $info[0];
    chomp($entry);
    
    # Do not continue if no device is found
    my %attrs = ();
    if (!$entry) {
        return \%attrs;
    }
    
    @info = split(',', $entry);    
    %attrs = (
        'status' => $info[0],
        'wwpn' => $info[1],
        'lun' => $info[2],
        'size' => $info[3],
        'range' => $info[4],
        'owner' => $info[5],
        'fcp' => $info[6],
        'tag' => $info[7]        
    );
    
    return \%attrs;
}