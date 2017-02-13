# IBM(c) 2013-2016 EPL license http://www.eclipse.org/legal/epl-v10.html
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
use File::Basename;
use Net::Ping;
use strict;
use warnings;
use Encode;
use JSON;
use Data::Dumper;
use Cwd;
1;

my $locOpenStackUpdateName = '/var/lib/sspmod/setnewname.py';

# Files which contain OS distribution and version information.
my $locEtcDebianVersion    = '/etc/debian_version';
my $locEtcFedoraRelease    = '/etc/fedora-release';
my $locEtcIssue            = '/etc/issue';
my $locEtcLsbRelease       = '/etc/lsb-release';
my $locEtcOsRelease        = '/etc/os-release';
my $locEtcRedhatRelease    = '/etc/redhat-release';
my $locEtcStarRelease      = '/etc/*-release';
my $locEtcSuseRelease      = '/etc/SuSE-release';
my $locEtcUnitedLinux      = '/etc/UnitedLinux-release';
my $locAllEtcVerFiles      = "/etc/*-release /etc/issue /etc/debian_version";

# Supported Operating System distros and versions
my %supportedVersions = (
    rhel5 => 1,
    rhel6 => 1,
    sles10 => 1,
    sles11 => 1,
    );

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
    if ($str =~ m/(\(error\)|\s*failed)/i) {  # Set to print error if the string contains (error) or starts with failed
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
        #$out = `ssh -o ConnectTimeout=5 $user\@$node "$sudo ls /etc/sysconfig/hardware/hwcfg-qeth*"`;
        my $cmd = "$sudo ls /etc/sysconfig/hardware/hwcfg-qeth*";
        $out = xCAT::zvmUtils->execcmdonVM($user, $node, $cmd); # caller sets $user to $::SUDOER
        if (xCAT::zvmUtils->checkOutput( $out ) == -1) {
            return $out;
        }
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
        #$out = `ssh -o ConnectTimeout=5 $user\@$node "$sudo ls /etc/sysconfig/network-scripts/ifcfg-eth*"`;
        my $cmd = "$sudo ls /etc/sysconfig/network-scripts/ifcfg-eth*";
        $out = xCAT::zvmUtils->execcmdonVM($user, $node, $cmd); # caller sets $user to $::SUDOER
        if (xCAT::zvmUtils->checkOutput( $out ) == -1) {
            return $out;
        }
        @parms = split( '\n', $out );
        return ( $parms[0] );
    }

    # If it is SUSE - ifcfg-qeth file is in /etc/sysconfig/network
    elsif ( $os =~ m/SUSE/i ) {
        #$out = `ssh -o ConnectTimeout=5 $user\@$node "$sudo ls /etc/sysconfig/network/ifcfg-qeth*"`;
        my $cmd = "$sudo ls /etc/sysconfig/network/ifcfg-qeth*";
        $out = xCAT::zvmUtils->execcmdonVM($user, $node, $cmd); # caller sets $user to $::SUDOER
        if (xCAT::zvmUtils->checkOutput( $out ) == -1) {
            return $out;
        }
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
        #$out   = `ssh -o ConnectTimeout=5 $user\@$node "$sudo ls /etc/sysconfig/network-scripts/ifcfg-eth*"`;
        my $cmd   = "$sudo ls /etc/sysconfig/network-scripts/ifcfg-eth*";
        $out = xCAT::zvmUtils->execcmdonVM($user, $node, $cmd); # caller sets $user to $::SUDOER
        if (xCAT::zvmUtils->checkOutput( $out ) == -1) {
            return $out;
        }
        @parms = split( '\n', $out );

        # Go through each line
        foreach (@parms) {

            # If the network file contains the NIC address
            #$out = `ssh -o ConnectTimeout=5 $user\@$node "$sudo cat $_" | egrep -i "$nic"`;
            my $cmd = $sudo . ' cat $_ | egrep -i "' . $nic .'"';
            $out = xCAT::zvmUtils->execcmdonVM($user, $node, $cmd); # caller sets $user to $::SUDOER
            if (xCAT::zvmUtils->checkOutput( $out ) == -1) {
                return $out;
            }
            if ($out) {

                # Return network file path
                return ($_);
            }
        }
    }

    # If it is SLES 10 - ifcfg-qeth file is in /etc/sysconfig/network
    elsif ( $os =~ m/SUSE Linux Enterprise Server 10/i ) {
        #$out = `ssh -o ConnectTimeout=5 $user\@$node "$sudo ls /etc/sysconfig/network/ifcfg-qeth*" | grep -i "$nic"`;
        my $cmd = $sudo . ' ls /etc/sysconfig/network/ifcfg-qeth* | grep -i "' . $nic .'"';
        $out = xCAT::zvmUtils->execcmdonVM($user, $node, $cmd); # caller sets $user to $::SUDOER
        if (xCAT::zvmUtils->checkOutput( $out ) == -1) {
            return $out;
        }
        @parms = split( '\n', $out );
        return ( $parms[0] );
    }

    # If it is SLES 11 - ifcfg-qeth file is in /etc/sysconfig/network
    elsif ( $os =~ m/SUSE Linux Enterprise Server 11/i ) {

        # Get a list of ifcfg-eth files found
        #$out = `ssh -o ConnectTimeout=5 $user\@$node "$sudo ls /etc/sysconfig/network/ifcfg-eth*"`;
        my $cmd = "$sudo ls /etc/sysconfig/network/ifcfg-eth*";
        $out = xCAT::zvmUtils->execcmdonVM($user, $node, $cmd); # caller sets $user to $::SUDOER
        if (xCAT::zvmUtils->checkOutput( $out ) == -1) {
            return $out;
        }
        my @file = split( '\n', $out );

        # Go through each ifcfg-eth file
        foreach (@file) {

            # If the network file contains the NIC address
            #$out = `ssh -o ConnectTimeout=5 $user\@$node "$sudo cat $_" | grep -i "$nic"`;
            my $cmd = $sudo . ' cat $_ | grep -i "' . $nic .'"';
            $out = xCAT::zvmUtils->execcmdonVM($user, $node, $cmd); # caller sets $user to $::SUDOER
            if (xCAT::zvmUtils->checkOutput( $out ) == -1) {
                return $out;
            }
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
    Returns     : Return code from SCP
    Example     : $rc = xCAT::zvmUtils->sendFile($user, $node, $srcFile, $trgtFile);

=cut

#-------------------------------------------------------
sub sendFile {

    # Get inputs
    my ( $class, $user, $node, $srcFile, $trgtFile ) = @_;

    my $out;
    my $rc;

    # Create destination string
    my $dest = "$user\@$node";

    # SCP directory entry file over to HCP
    foreach my $wait ( 1, 2, 3, 5, 8, 15, 22, 34, 60 ) {
        $out = `/usr/bin/scp $srcFile $dest:$trgtFile 2>&1`;
        $rc = $?;
        if ( $rc == 0 ) {
            last;
        }

        xCAT::zvmUtils->printSyslog("SCP $srcFile $dest:$trgtFile - failed with rc: $rc, out: $out");
        sleep( $wait );
    }

    return $rc;
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

    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }

    # Get the root device node
    # LVM is not supported
    #my $out = `ssh $user\@$node  "mount" | grep "/ type" | sed 's/1//'`;
    my $cmd = $sudo . ' mount | grep "/ type" | sed \'s/1//\'';
    my $out = xCAT::zvmUtils->execcmdonVM($user, $node, $cmd); # caller sets $user to $::SUDOER
    if (xCAT::zvmUtils->checkOutput( $out ) == -1) {
        return $out;
    }

    my @parms = split( " ", $out );
    @parms = split( "/", xCAT::zvmUtils->trimStr( $parms[0] ) );
    my $devNode = $parms[0];

    # Get disk address
    #$out = `ssh $user\@$node "cat /proc/dasd/devices" | grep "$devNode" | sed 's/(ECKD)//' | sed 's/(FBA )//' | sed 's/0.0.//'`;
    $cmd = $sudo . ' cat /proc/dasd/devices | grep "' . $devNode . '" | sed "s/(ECKD)//" | sed "s/(FBA )//" | sed \'s/0.0.//\'';
    $out = xCAT::zvmUtils->execcmdonVM($user, $node, $cmd); # caller sets $user to $::SUDOER
    if (xCAT::zvmUtils->checkOutput( $out ) == -1) {
        return $out;
    }

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
        # Can't guarantee the success of online/offline disk, need to wait
        # Until it's done because we may detach the disk after -d option
        # or use the disk after the -e option
        my @sleepTime = (1,2,3,5,8,15,22,34,60,60,60,60,60,90,120);
        foreach (@sleepTime) {
            #$out = system("ssh $user\@$node '$sudo /sbin/chccwdev $option $devAddr'");
            my $cmd = "$sudo /sbin/chccwdev $option $devAddr";
            $out = xCAT::zvmUtils->execcmdonVM($user, $node, $cmd); # caller sets $user to $::SUDOER
            if (xCAT::zvmUtils->checkOutput( $out ) == -1) { # try again if an error
                sleep($_);
            } else {
                return "ssh $user\@$node $sudo /sbin/chccwdev $option $devAddr... Done";
            }
        }
    }
    return "Error: failed to ssh $user\@$node $sudo /sbin/chccwdev $option $devAddr";
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
        # skip comment lines that start with * or whitespace *
        if ( $_ =~ m/^\s*\*/) {
            next;
        }
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

=head3   getCommands

    Description : Get the COMMAND statements in the user entry of a given node
    Arguments   :   User (root or non-root)
                    Node
    Returns     : COMMAND statements
    Example     : my @commands = xCAT::zvmUtils->getCommands($callback, $user, $node);

=cut

#-------------------------------------------------------
sub getCommands {

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

    my $out = `ssh $user\@$hcp "$sudo $dir/smcli Image_Query_DM -T $userId" | egrep -i "COMMAND"`;

    # Get COMMAND statements
    my @lines = split( '\n', $out );
    my @commands;
    foreach (@lines) {
        $_ = xCAT::zvmUtils->trimStr($_);

        # Save statements
        push( @commands, $_ );
    }

    return (@commands);
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
    Example     : my $rtn = xCAT::zvmUtils->checkOutput( $out );

=cut

#-------------------------------------------------------
sub checkOutput {
    my ( $class, $out ) = @_;

    # Check output string
    my @outLn = split( "\n", $out );
    foreach (@outLn) {

        # If output contains 'Failed', or Error return -1
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
    Example     : my $rtn = xCAT::zvmUtils->checkOutput( $out, \$reason );

=cut

#-------------------------------------------------------
sub checkOutputExtractReason {
    my ( $class, $out, $reason ) = @_;

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

=head3   checkSSHOutput

    Description : Check for SSH errors, and command failure
    Arguments   : $?
                  command that was issued
    Returns     : rc = 0  Good output
                  rc = -1  Error occurred
                  $outmsg = error message string if $rc = -1


    Example     : ($rc, $outmsg) = xCAT::zvmUtils->checkSSHOutput( $?, "Command being issued");

=cut

#-------------------------------------------------------
sub checkSSHOutput {
    my ( $class, $rc, $cmd ) = @_;

    my $msgTxt = '';
    $rc = $rc >> 8;
    if ( $rc == 255 ) {
        # SSH failure to communicate with zHCP.
        $msgTxt = "SSH Failed to communicate when trying command: $cmd";
        xCAT::zvmUtils->printSyslog("$msgTxt");
        return (-1, $msgTxt);
    } elsif ( $rc != 0 ) {
        # Generic failure of the command.
        $msgTxt = "Command failed with return code $rc trying to issue cmd: $cmd";
        xCAT::zvmUtils->printSyslog("$msgTxt");
        return ($rc, $msgTxt);
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
    #my $out = `ssh $user\@$node "$sudo cat /proc/dasd/devices" | grep ".$tgtAddr("`;
    my $cmd = $sudo . ' cat /proc/dasd/devices | grep ".' . $tgtAddr . '("';
    my $out = xCAT::zvmUtils->execcmdonVM($user, $node, $cmd); # caller sets $user to $::SUDOER
    if (xCAT::zvmUtils->checkOutput( $out ) == -1) {
        return $out;
    }
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
    #my $addr = `ssh $user\@$node "$sudo cat /proc/dasd/devices" | grep -i "is $deviceNode"`;
    my $cmd = $sudo . ' cat /proc/dasd/devices | grep -i "is ' . $deviceNode . '"';
    my $addr = xCAT::zvmUtils->execcmdonVM($user, $node, $cmd); # caller sets $user to $::SUDOER
    if (xCAT::zvmUtils->checkOutput( $addr ) == -1) {
        return $addr;
    }
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
    #my $out = `ssh -o ConnectTimeout=5 $user\@$node "$sudo /sbin/vmcp q v dasd" | grep "DASD $address"`;
    my $cmd = $sudo . ' /sbin/vmcp q v dasd | grep "DASD '. $address. '"';
    my $out = xCAT::zvmUtils->execcmdonVM($user, $node, $cmd); # caller sets $user to $::SUDOER
    if (xCAT::zvmUtils->checkOutput( $out ) == -1) {
        return $out;
    }
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
    #my $out = `ssh -o ConnectTimeout=10 $user\@$node "$sudo cat /etc/*release" | egrep -v "LSB_VERSION"`;
    my $cmd = $sudo . ' cat /etc/*release | egrep -v "LSB_VERSION"';
    my $out = xCAT::zvmUtils->execcmdonVM($user, $node, $cmd); # caller sets $user to $::SUDOER
    if (xCAT::zvmUtils->checkOutput( $out ) == -1) {
        return $out;
    }
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
    #my $arch = `ssh $user\@$node "$sudo uname -m"`;
    my $cmd = "$sudo uname -m";
    my $arch = xCAT::zvmUtils->execcmdonVM($user, $node, $cmd); # caller sets $user to $::SUDOER
    if (xCAT::zvmUtils->checkOutput( $arch ) == -1) {
        return $arch;
    }

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

=head3   getVswitchIdsFromDirectory

    Description : Get the nicdef switch names of a given node
    Arguments   :   User (root or non-root)
                    zHCP
                    Userid
    Returns     : Vswitch names
    Example     : my $vSwitchNamers = xCAT::zvmCPUtils->getVswitchIdsFromDirectory($user, $hcp, $userId);

=cut

#-------------------------------------------------------
sub getVswitchIdsFromDirectory {

    # Get inputs
    my ( $class, $user, $hcp ,$userId ) = @_;

    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }
    my @vswitch;

    # Get VSwitchs in directory
    # only get lines that have SYSTEM switchname in them
    # smcli Image_Definition_Query_DM -T xcat -k nicdef
    # NICDEF=VDEV=0600 TYPE=QDIO LAN=SYSTEM SWITCHNAME=XCATVSW1
    # NICDEF=VDEV=0700 TYPE=QDIO LAN=SYSTEM SWITCHNAME=XCATVSW2
    #

    xCAT::zvmUtils->printSyslog("Calling: ssh $user\@$hcp $sudo /opt/zhcp/bin/smcli Image_Definition_Query_DM -T $userId -k NICDEF | egrep -i 'SWITCHNAME'");
    my $out = `ssh $user\@$hcp "$sudo /opt/zhcp/bin/smcli Image_Definition_Query_DM -T $userId -k NICDEF | egrep -i 'SWITCHNAME'"`;
    # if there is nothing found, log that and return;
    if ( !length($out) ) {
        xCAT::zvmUtils->printSyslog("No SWITCHNAME found in NICDEF statement for userid $userId");
        return (@vswitch);
    }
    xCAT::zvmUtils->printSyslog("$userId output: $out");
    my @lines = split( '\n', $out );
    my @parms;
    my $vswitchToken = '';

    foreach (@lines) {
        @parms = split( ' ', $_ );
        $vswitchToken = $parms[3];
        @parms = split( '=', $vswitchToken );
        push( @vswitch, $parms[1] );
    }

    return (@vswitch);
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
                    Node or IP Address
                    Callback handle (optional).  Allows the routine,
                    to write error messages when SSH fails.
    Returns     : Operating system name & version as a single word.
                  Otherwise, an empty string.
    Example     : my $os = xCAT::zvmUtils->getOsVersion($user, $node);
                  my $os = xCAT::zvmUtils->getOsVersion($user, $node, $callback);

=cut

#-------------------------------------------------------
sub getOsVersion {

    # Get inputs
    my ( $class, $user, $node, $callback ) = @_;

    my $osVer = '';

    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }

    # Contact the system to extract the possible files which contain pertinent data.
    #my $releaseInfo = `ssh -qo ConnectTimeout=2 $user\@$node "$sudo ls /dev/null $locAllEtcVerFiles 2>/dev/null | xargs grep ''"`;
    my $cmd = $sudo . ' ls /dev/null '. $locAllEtcVerFiles . ' 2>/dev/null | xargs grep ""';
    my $releaseInfo = xCAT::zvmUtils->execcmdonVM($user, $node, $cmd);
    if (xCAT::zvmUtils->checkOutput( $releaseInfo ) == -1) {
        return '';
    }
    $osVer = buildOsVersion( $callback, $releaseInfo, 'all' );

    return $osVer;
}

#-------------------------------------------------------

=head3   getOSFromIP

    Description : Get the operating system name and
                    version for the system at the specified
                    IP Address.
    Arguments   :   Callback handle
                    z/VM userid of the system
                    IP Address
                    Type of IP address (not currently used)
    Returns     : Operating system name & version as a single word.
                  Otherwise, an empty string.
    Example     : my $os = xCAT::zvmUtils->getOSFromIP( $callback, $userid, $ipAddr, $ipVersion };

=cut

#-------------------------------------------------------
sub getOSFromIP {
    my ( $class, $callback, $activeSystem, $ipAddr, $ipVersion ) = @_;

    my $osVer = '';
    my $rc = 0;

    # Get operating system
    my $releaseInfo = `ssh -qo ConnectTimeout=2 $ipAddr "ls /dev/null $locAllEtcVerFiles 2>/dev/null | xargs grep ''"`;
    $rc = $? >> 8;
    if ( $rc == 0 ) {
        $osVer = buildOsVersion( $callback, $releaseInfo, 'all' );
    } else {
        if ( $callback ) {
            # We have a callback so we can write an error message.
            if ( $rc == 255 ) {
                my $rsp;
                push @{$rsp->{data}}, "Unable to communicate with $activeSystem at $ipAddr using ssh.";
                xCAT::MsgUtils->message( "E", $rsp, $callback );
            } else {
                my $rsp;
                push @{$rsp->{data}}, "Received an unexpected ssh return code $rc from $activeSystem at $ipAddr.";
                xCAT::MsgUtils->message( "E", $rsp, $callback );
            }
        }
    }

    return $osVer;
}

#-------------------------------------------------------

=head3   stripHeader

    Description : Scans an input string to find only
                    lines that match a specified header string
                    and return an array of those lines without
                    the prefix.
    Arguments   : Multi-line string to scan
                  String to match
    Returns     : Array of matching lines.
    Example     : my @lines = stripHeader( $releaseInfo, '^/etc/os-release:' );
                  ($ver) = stripHeader( $releaseInfo, "^$locEtcUnitedLinux:" );

=cut

#-------------------------------------------------------
sub stripHeader {
    my ( $inputLines, $matchString ) = @_;
    my @outputLines;

    my @lines = split( /\n/, $inputLines );
    foreach my $line ( @lines ){
        if ( $line =~ m/$matchString/ ) {
            $line =~ s/$matchString//g;
            chomp $line;
            if ( $line eq '' ) { next }
            push @outputLines, $line;
        }
    }

    return @outputLines;
}


#-------------------------------------------------------

=head3   buildOsVersion

    Description : Build the OS version string from the
                  provided data files.

                  Note: Only RHEL and SLES are supported
                    z/VM xCAT supported distributions.
                    This routine has code for other distributions
                    supported by common xCAT.  If z/VM
                    ever supports another distribution
                    then we need to verify that the code
                    gets the correct version information.
    Arguments   : Callback (or undef)
                  Operating system data file(s) output
                  Type of data to return:
                    'all'       - $os$ver.$rel
                    'all_comma' - $os,$ver.$rel
                    'os'        - $os
                    'version'   - $ver
                    'release'   - $rel
                    ''          - $os$ver
    Returns     : Operating system name & version as a
                  single word.
    Example     : my $osVer = buildOsVersion( $callback, $releaseInfo, $type );

=cut

#-------------------------------------------------------
sub buildOsVersion {
    my $callback = shift;
    my $releaseInfo = shift;
    my $type = shift;

    my $os = 'unknown';          # OS indicator, e.g. "rhel", "SLES"
    my $ver   = '';              # Version indicator, e.g. "7.1",
    my $version = '';
    my $rel   = '';
    my $line  = '';
    my @lines;

    # Test strings that were used when we added the original support.  These
    # strings are what we used to simulate the other common Linux distros.
    #$releaseInfo = "$locEtcSuseRelease:SUSE Linux Enterprise Server 11 (s390x)\n$locEtcSuseRelease:VERSION = 11\n$locEtcSuseRelease:PATCHLEVEL = 4.32";
    #$releaseInfo = "$locEtcDebianVersion:1.0\n$locEtcIssue:debian release";
    #$releaseInfo = "$locEtcUnitedLinux:2.1a";
    #$releaseInfo = "$locEtcLsbRelease:Ubuntu\n$locEtcLsbRelease:  DISTRIB_ID=Ubuntu\n$locEtcLsbRelease:  DISTRIB_RELEASE=4.1";

    my @relOut = split('\n', $releaseInfo);
    if ( grep( /^$locEtcOsRelease:/, @relOut ) ) {
        my $version = '';
        my $version_id;
        my $id;
        my $id_like;
        my $name;
        my $prettyname;
        my $verrel = '';

        my @text = stripHeader( $releaseInfo, "^$locEtcOsRelease:" );
        foreach my $line ( @text ) {
            if ( $line =~ /^\s*VERSION=\"?([0-9\.]+).*/ ) {
                $version = $1;
            }
            if($line =~ /^\s*VERSION_ID=\"?([0-9\.]+).*/){
                $version_id = $1;
            }

            if ( $line =~ /^\s*Base release\s?([0-9\.]+).*/ ) {
                $version = $1;
                $id = 'BASE';
            }

            if ( $line =~ /^\s*ID=\"?([0-9a-z\_\-\.]+).*/ ) {
                $id = $1;
            }
            if ( $line =~ /^\s*ID_LIKE=\"?([0-9a-z\_\-\.]+).*/ ) {
                $id_like = $1;
            }

            if ( $line =~ /^\s*NAME=\"?(.*)/ ) {
                $name = $1;
            }
            if($line =~ /^\s*PRETTY_NAME=\"?(.*)/){
                $prettyname = $1;
            }
        }

        $os = $id;
        if ( !$os and $id_like ) {
            $os = $id_like;
        }

        $verrel = $version;
        if ( !$verrel and $version_id ) {
            $verrel = $version_id;
        }

        if( !$name and $prettyname ){
            $name = $prettyname;
        }

        # Note: xcat::Utils->osver() sets this value with an 's' but zvm.pm
        #       does not use it.  So for now, we don't set 's'.
        #if ( $os =~ /rhel/ and $name =~ /Server/i ) {
        #    # $os = "rhels";
        #}

        if ( $verrel =~ /([0-9]+)\.?(.*)/ ) {
            $ver = $1;
            $rel = $2;
        }
    } elsif ( grep( /^$locEtcRedhatRelease:/, @relOut ) ) {
        my @text = stripHeader( $releaseInfo, "^$locEtcRedhatRelease:" );
        my $line = $text[0];
        chomp( $line );
        $os = "rh";
        my $verrel = $line;
        $ver = $line;

        if ( $type ) {
            $verrel =~ s/[^0-9]*([0-9.]+).*/$1/;
            ($ver,$rel) = split /\./, $verrel;
        } else {
            $ver=~ tr/\.//;
            $ver =~ s/[^0-9]*([0-9]+).*/$1/;
        }

        if    ( $line =~ /AS/ )      { $os = 'rhas'  }
        elsif ( $line =~ /ES/ )      { $os = 'rhes'  }
        elsif ( $line =~ /WS/ )      { $os = 'rhws'  }
        elsif ( $line =~ /Server/ )  {
            if ( $type ) {
                $os = 'rhel';
                # Note: xcat::Utils->osver() sets this value with an 's' but zvm.pm
                #       does not use it.  So for now, we don't set 's'.
                #$os = 'rhels';
            } else {
                $os = 'rhserver';
            }
        } elsif ( $line =~ /Client/ )  {
            if ( $type ) {
                $os = 'rhel';
            } else {
                $os = 'rhclient';
            }
        } elsif ( grep( /$locEtcFedoraRelease:/, @relOut ) ) { $os = 'rhfc' }
    } elsif ( grep( /^$locEtcSuseRelease:/, @relOut ) ) {
        my @lines = stripHeader( $releaseInfo, "^$locEtcSuseRelease:" );
        if ( grep /SLES|Enterprise Server/, @lines ) { $os = "sles" }
        if ( grep /SLEC/, @lines ) { $os = "slec" }
        $ver = $lines[0];
        $ver =~ tr/\.//;
        $ver =~ s/[^0-9]*([0-9]+).*/$1/;

        $rel = $lines[2];
        $rel =~ tr/\.//;
        $rel =~ s/[^0-9]*([0-9]+).*/$1/;
    } elsif ( grep( /^$locEtcUnitedLinux:/, @relOut ) ) {
        # Note: Not a z/VM xCAT supported distribution.
        #       If we ever support this then we need to verify this code
        #       gets the correct version information.
        ($ver) = stripHeader( $releaseInfo, "^$locEtcUnitedLinux:" );
        $os = "ul";
        $ver =~ tr/\.//;
        $ver =~ s/[^0-9]*([0-9]+).*/$1/;
    } elsif ( grep( /$locEtcLsbRelease:/, @relOut ) ) {
        # Ubuntu release
        my @text = stripHeader( $releaseInfo, "^$locEtcLsbRelease:" );
        chomp( @text );
        my $distrib_id = '';
        my $distrib_rel = '';

        foreach ( @text ) {
            if ( $_ =~ /^\s*DISTRIB_ID=(.*)$/ ) {
                $distrib_id = $1;                   # last DISTRIB_ID value in file used
            } elsif ( $_ =~ /^\s*DISTRIB_RELEASE=(.*)$/ ) {
                $distrib_rel = $1;                  # last DISTRIB_RELEASE value in file used
            }
        }

        if ( $distrib_id =~ /^(Ubuntu|"Ubuntu")\s*$/ ) {
            $os = "ubuntu";

            if ( $distrib_rel =~ /^(.*?)\s*$/ ) {       # eliminate trailing blanks, if any
                $distrib_rel = $1;
            }
            if ( $distrib_rel =~ /^"(.*?)"$/ ) {        # eliminate enclosing quotes, if any
                $distrib_rel = $1;
            }
            $ver = $distrib_rel;
        }
    } elsif ( grep( /^$locEtcDebianVersion:/, @relOut ) ) {
        # Debian release
        if ( grep( /^$locEtcIssue:/, @relOut ) ) {
            ($line) = stripHeader( $releaseInfo, "^$locEtcIssue:" );
            if ( $line =~ /debian.*/i ) {
                $os = "debian";
                ($ver) = stripHeader( $releaseInfo, "^$locEtcDebianVersion:" );
            }
        }
    }

    my $outString = '';
    if ( $type eq 'all_comma' ) {
        if ( $rel ne "") {
            $outString = "$os,$ver.$rel";
        } else {
            $outString =  "$os,$ver";
        }
    } elsif ( $type eq 'all' ) {
        if ( $rel ne "") {
            $outString = "$os$ver.$rel";
        } else {
            $outString =  "$os$ver";
        }
    } elsif ( $type eq 'os' ) {
        $outString =  $os;
    } elsif ( $type eq 'version' ) {
        $outString =  $ver;
    } elsif ( $type eq 'release' ) {
        $outString =  $os;
    } else {
        $outString =  "$os$ver";
    }

    return $outString;
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
    #my $info = `ssh -o ConnectTimeout=5 $user\@$node "$sudo /sbin/lszfcp -D"`;
    my $cmd = "$sudo /sbin/lszfcp -D";
    my $info = xCAT::zvmUtils->execcmdonVM($user, $node, $cmd); # caller sets $user to $::SUDOER
    # will not check for connection errors here
    my @zfcp = split("\n", $info);
    if (!$info || $info =~ m/No zfcp support/i || $info =~ m/No fcp devices found/i) {
        return;
    }

    # Get SCSI device and their attributes
    #my $scsi = `ssh -o ConnectTimeout=5 $user\@$node "$sudo /usr/bin/lsscsi"`;
    $cmd = "$sudo /usr/bin/lsscsi";
    my $scsi = xCAT::zvmUtils->execcmdonVM($user, $node, $cmd); # caller sets $user to $::SUDOER
    if (xCAT::zvmUtils->checkOutput( $info ) == -1) {
        return $info;
    }
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
        #$size = `ssh -o ConnectTimeout=5 $user\@$node "$sudo /usr/bin/sg_readcap $tmp" | egrep -i "Device size:"`;
        my $cmd = $sudo . ' /usr/bin/sg_readcap ' . $tmp . ' | egrep -i Device size:';
        $size = xCAT::zvmUtils->execcmdonVM($user, $node, $cmd); # caller sets $user to $::SUDOER
        if (xCAT::zvmUtils->checkOutput( $size ) == -1) {
            return $size;
        }
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

=head3   isOSVerSupported

    Description : Determine if the specified OS version supported.
    Arguments   : OS version string (e.g. RHEL6, RHEL6.1, SLES11sp2)
    Returns     : 1 - version is supported
                  0 - version is not supported
    Example     : my $supported = xCAT::zvmUtils->isOSVerSupported( $os );

=cut

#-------------------------------------------------------
sub isOSVerSupported {
    my ( $class, $osVer ) = @_;

    # Keep just the OS distro name and the version, ie. drop any release info.
    $osVer = lc( $osVer );
    if ( $osVer =~ /([a-z]+[0-9]+)/ ) {
        $osVer = $1;
    }

    # Check against our list of supported versions.
    if ( $supportedVersions{$osVer} ) {
        return 1;
    } else {
        return 0;
    }
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
    #my $deviceTypesVm = 'CONS|CTCA|DASD|FCP|GRAF|LINE|MSGD|OSA|PRT|PUN|RDR|SWCH|TAPE';
    my $deviceTypesVm = '^CONS|^CTCA|^DASD|^FCP|^GRAF|^LINE|^MSGD|^OSA|^PRT|^PUN|^RDR|^SWCH|^TAPE';
    # All device type names in user directory, do not contain CPU
    my $deviceTypesUserDir = 'CONSOLE|MDISK|NICDEF|SPOOL|RDEVICE';


    # Search for all address that is in use
    my $allUsedAddr;
    if ($type eq 'vmcp') {
        # When the node is up, vmcp can be used
        #$allUsedAddr = `ssh -o ConnectTimeout=5 $user\@$node "$sudo /sbin/vmcp q v all | awk '\$1 ~/^($deviceTypesVm)/ {print \$2}' | sort"`;
        my $cmd = $sudo . '/sbin/vmcp q v all | egrep "' . $deviceTypesVm . '"';
        my $allUsedAddr = xCAT::zvmUtils->execcmdonVM($user, $node, $cmd); # caller sets $user to $::SUDOER
        if (xCAT::zvmUtils->checkOutput( $allUsedAddr ) == -1) {
           return -1;
        }
        $allUsedAddr = `echo '$allUsedAddr' | awk '\$1 ~/^($deviceTypesVm)/ {print \$2}' | sort`;
    } else {
        # When the node is down, use zHCP to get its user directory entry
        # Get HCP
        my @propNames = ('hcp', 'userid');
        my $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $node, @propNames );
        my $hcp = $propVals->{'hcp'};

        # Get node userID
        my $userId = $propVals->{'userid'};

        # Get user directory entry
        my $userDirEntry = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Query_DM -T $userId"`;

        # Get profile if user directory entry include a profile
        if ($userDirEntry =~ "INCLUDE ") {
            my $profileName = `cat $userDirEntry | awk '\$1 ~/^(INCLUDE)/ {print \$2}'`;
            $profileName = xCAT::zvmUtils->trimStr($profileName);
            $userDirEntry .= `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Query_DM -T $profileName"`;
        }

        # Get all defined device address
        $allUsedAddr = `cat $userDirEntry | awk '\$1 ~/^($deviceTypesUserDir)/ {print \$2}' | sort`;
        # Get all linked device address
        $allUsedAddr .= `cat $userDirEntry | awk '\$1 ~/^(LINK)/ {print \$4}' | sort`;
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

    #my $out = `ssh -o ConnectTimeout=5 $user\@$node "$sudo uptime"`;
    my $cmd = "$sudo uptime";
    my $out = xCAT::zvmUtils->execcmdonVM($user, $node, $cmd); # caller sets $user to $::SUDOER
    if (xCAT::zvmUtils->checkOutput( $out ) == -1) {
       return $out;
    }
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

=head3   handlePowerUp

    Description : Handle power up of nodes whose IP information
                  may change on power up.  The routine will weed out
                  non-s390x architectures and do processing for nodes whose
                  status in the zvm table is "POWER_UP=1".
    Arguments   : Callback
                  Nodes that are to be handled.
    Returns     : None
    Example     : xCAT::zvmUtils->handlePowerUp( $callback, $nodes, \%args );

=cut

#-------------------------------------------------------
sub handlePowerUp {
    my ( $class, $callback, $nodes, $argsRef ) = @_;
    my %propHash;               # Property hash used to fill in various tables
    my %sysInfo;                # Hash to hold system information
    my %args = %$argsRef;       # Command arguments, verbose is one such operand

    my $nodetypeTab = xCAT::Table->new('nodetype');
    my $nodetypeHash = $nodetypeTab->getNodesAttribs( $nodes, ['arch'] );
    my $zvmTab = xCAT::Table->new('zvm');
    my $zvmHash = $zvmTab->getNodesAttribs( $nodes, ['hcp', 'status', 'userid'] );

    foreach my $node ( keys %{$nodetypeHash} ) {
        next if ( $nodetypeHash->{$node}->[0]->{'arch'} !~ 's390x' );
        my $status = $zvmHash->{$node}->[0]->{'status'};
        if ( $status =~ 'POWER_UP=1' ) {
            my $userid = $zvmHash->{$node}->[0]->{'userid'};
            my $rc = xCAT::zvmUtils->findAccessIP( $callback,
                                                   $userid,
                                                   $zvmHash->{$node}->[0]->{'hcp'},
                                                   \%sysInfo,
                                                   \%args );
            if ( $rc == 0 ) {
                # Got what we needed so we can update tables with the current information.
                if ( $args{'verbose'} == 1 ) {
                    my $rsp;
                    push @{$rsp->{data}}, "Updating xCAT tables with IP information for $node:\n" .
                                          "    ip: $sysInfo{$userid}{'ipAddr'}, hostname: $sysInfo{$userid}{'hostname'}\n".
                                          "    macAddr: $sysInfo{$userid}{'macAddr'}, switch: $sysInfo{$userid}{'switch'}\n".
                                          "    Network Adapter VDEV: $sysInfo{$userid}{'adapterAddr'}";
                    xCAT::MsgUtils->message( "I", $rsp, $callback );
                }

                substr( $sysInfo{$userid}{'macAddr'}, 10, 0 ) = ':';
                substr( $sysInfo{$userid}{'macAddr'}, 8, 0 ) = ':';
                substr( $sysInfo{$userid}{'macAddr'}, 6, 0 ) = ':';
                substr( $sysInfo{$userid}{'macAddr'}, 4, 0 ) = ':';
                substr( $sysInfo{$userid}{'macAddr'}, 2, 0 ) = ':';
                %propHash = (
                             'disable'     => 0,
                             'interface'   => $sysInfo{$userid}{'vdev'},
                             'mac'         => $sysInfo{$userid}{'macAddr'},
                            );
                xCAT::zvmUtils->setNodeProps( 'mac', $node, \%propHash );

                %propHash = (
                             'disable'     => 0,
                             'hostnames'   => $sysInfo{$userid}{'hostname'},
                             'ip'          => $sysInfo{$userid}{'ipAddr'},
                            );
                xCAT::zvmUtils->setNodeProps( 'hosts', $node, \%propHash );

                $status =~ s/POWER_UP=1/POWER_UP=0/g;
                %propHash = (
                             'status'    => $status,
                            );
                xCAT::zvmUtils->setNodeProps( 'zvm', $node, \%propHash );

                my $out = `/opt/xcat/sbin/makehosts $node 2>&1`;
                if ( $out ne '' ) {
                    my $rsp;
                    push @{$rsp->{data}}, "'makehosts' failed for $node.  " .
                        "'makehosts' response: $out";
                    xCAT::MsgUtils->message( "E", $rsp, $callback );
                }

                # Inform OpenStack of the hostname.
                if ( -e $locOpenStackUpdateName ) {
                    # Call the python change instance name command
                    my $renamed = 0;
                    my $args = "--nodename $node --hostname $sysInfo{$userid}{'hostname'}";
                    xCAT::MsgUtils->message( "S", "Invoking $locOpenStackUpdateName $args" );
                    my $out = `python $locOpenStackUpdateName $args`;
                    xCAT::MsgUtils->message( "S", "Returned from OpenStack node name update for $node with $out" );
                    if ( $out ) {
                        if ( $out =~ m/^Success!/ ) {
                            $renamed = 1;
                            if ( $args{'verbose'} == 1 ) {
                                my $rsp;
                                push @{$rsp->{data}}, "Renamed the OpenStack instance.";
                                xCAT::MsgUtils->message("I", $rsp, $callback);
                            }
                        }
                    }

                    if ( !$renamed ) {
                        # Return an information message but do not fail the nodeset with an error
                        # message.  This error is minor to the overall operation.
                        my $rsp;
                        push @{$rsp->{data}}, "Unable to update the OpenStack node name: $node";
                        xCAT::MsgUtils->message("I", $rsp, $callback);
                    }
                }
            } else {
                my $rsp;
                push @{$rsp->{data}}, "Did not find sufficient IP information for $node.";
                xCAT::MsgUtils->message( "I", $rsp, $callback );
            }
        }
    }
}


#-------------------------------------------------------

=head3   findAccessIP

    Description : Obtain TCP/IP and hostname information about
                  the virtual machine related to the node.
    Arguments   : Callback in case we want to produce a message
                  Virtual machine userid
                  ZHCP node handling the z/VM host node
                  Hash to contain information on the system
                  Command invocation argument hash.  'ipfilter' and
                    'verbose' keys are used in this routine.
                  SUDO issuer ($sudoer) or 'root' user for the SSH into ZHCP.
                    This parameter avoids the call to getsudoer() to obtain
                    the sudo and sudoer value.  'root' user does not use 'sudo'.
    Returns     : 0 - No error
                  non-zero - Error detected or filtered out as a usable IP address
    Example     : $rc = findAccessIP( $callback, 'linux001', $hcp
                                      \%sysInfo, \%args );

=cut

#-------------------------------------------------------
sub findAccessIP
{
    my $class = shift;                # Perl class
    my $callback = shift;             # Callback for messaging
    my $activeSystem = shift;         # Userid of the system being queried
    my $hcp = shift;                  # HCP
    my $sysInfoRef = shift;           # Hash reference for system IP information
    my $argsRef = shift;              # Command arguments, verbose, ipFilter
    my %args = %$argsRef;             # Access hash for easier reference
    my $sudoer = shift;               # SUDO issuer

    my %adapter;                      # Adapter hash info, used mainly for verbose processing
    my @failureInfo;                  # Information on IP contact failures
    my $hostname = '';                # Hostname from the target node
    my @hostnameCmds = ( # List of host name resolution commands to be issued in a virtual OS.
                         'hostname --fqdn',
                         'hostname --long',
                         'hostname',
                       );
    my %ips;                          # Hash of IP info obtained from the various calls
    my $out;                          # Output buffer work area
    my $rc;                           # Return code
    my $rsp;                          # Message work buffer
    my $sudo = '';                    # Assume we are not going to use SUDO on ZHCP call.

    # Use sudo or not
    if ( $sudoer eq '' ) {
        # Looks in the passwd table for a key = sudoer.
        ($sudoer, $sudo) = xCAT::zvmUtils->getSudoer();
    } elsif ( $sudoer ne 'root' ) {
        # Non-root user specified so we will invoke 'sudo' on the SSH call to ZHCP.
        $sudo = 'sudo';
    }

    # Get the list of IP addresses currently in use by the virtual machine.
    $out = `ssh -q $sudoer\@$hcp $sudo /opt/zhcp/bin/smcli "Virtual_Network_Adapter_Query_Extended -T '$activeSystem' -k 'image_device_number=*'"`;
    $rc = $? >> 8;
    if ($rc == 255) {
        push @{$rsp->{data}}, "Unable to communicate with the zhcp system: $hcp";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        goto FINISH_findAccessIP;
    } elsif ( $rc == 1 ) {
        my ( $smcliRC, $smcliRS, $smcliDesc );
        my $errorOut = `echo "$out" | egrep -i '(^  Return Code: |^  Reason Code: |^  Description: )'`;
        my @errorLines = split( "\n", $errorOut );
        foreach my $errorLine ( @errorLines ) {
            if ( $errorLine =~ /^  Return Code: / ) {
                ($smcliRC) = $errorLine =~ /^  Return Code: (.*)/;
            }
            if ( $errorLine =~ /^  Reason Code: / ) {
                ($smcliRS) = $errorLine =~ /^  Reason Code: (.*)/;
            }
            if ( $errorLine =~ /^  Description: / ) {
                ($smcliDesc) = $errorLine =~ /^  Description: (.*)/;
            }
        }
        if (( $smcliRC == 212 ) && ( $smcliRS == 8 )) {
            if ( $args{'verbose'} == 1 ) {
                push @{$rsp->{data}}, "For userid $activeSystem, the virtual machine does not have any network adapters.";
                xCAT::MsgUtils->message( "I", $rsp, $callback );
            }
            push @failureInfo, "The virtual machine does not have any network adapters";
            goto FINISH_findAccessIP;
        } else {
            push @{$rsp->{data}}, "An unexpected return code $smcliRC and reason code $smcliRS was received from " .
                                  "the zhcp server $hcp for an smcli Virtual_Network_Adapter_Query_Extended " .
                                  "request.  Error description: $smcliDesc";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            goto FINISH_findAccessIP;
        }

    } elsif ( $rc != 0 ) {
        push @{$rsp->{data}}, "An unexpected return code $rc was received from " .
                              "the zhcp server $hcp for an smcli Virtual_Network_Adapter_Query_Extended " .
                              "request.  SMAPI servers may be unavailable.  " .
                              "Received response: $out";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        goto FINISH_findAccessIP;
    }

    my $filteredOut = `echo "$out" | egrep -i '(adapter_address=|adapter_status=|mac_address=|mac_ip_address=|mac_ip_version=|lan_name=|lan_owner=)'`;
    my @ipOut = split( "\n", $filteredOut );
    my ($adapterAddr, $adapterStatus, $ipAddr, $ipVersion, $lanName, $lanOwner, $macAddr );
    foreach my $ipLine ( @ipOut ) {
        if ( $ipLine =~ /adapter_address=/ ) {
            ($adapterAddr) = $ipLine =~ /adapter_address=(.*)/;
            $adapter{$adapterAddr}{'ipCnt'} = 0;
            $adapter{$adapterAddr}{'macCnt'} = 0;
            ($lanName, $lanOwner) = '';
        } elsif ( $ipLine =~ /adapter_status=/ ) {
            ($adapterStatus) = $ipLine =~ /adapter_status=(.*)/;
            $adapter{$adapterAddr}{'status'} = $adapterStatus;
        } elsif ( $ipLine =~ /^lan_name=/ ) {
            ($lanName) = $ipLine =~ /lan_name=(.*)/;
        #} elsif ( $ipLine =~ /^lan_owner=/ ) {
        #    ($lanOwner) = $ipLine =~ /lan_owner=(.*)/;
        } elsif ( $ipLine =~ /^mac_address=/ ) {
            ($macAddr) = $ipLine =~ /mac_address=(.*)/;
            ($ipVersion, $ipAddr) = '';
            $adapter{$adapterAddr}{'macCnt'} += 1;
        } elsif ( $ipLine =~ /^mac_ip_address=/ ) {
            ($ipAddr) = $ipLine =~ /mac_ip_address=(.*)/;
        } elsif ( $ipLine =~ /^mac_ip_version=/ ) {
            ($ipVersion) = $ipLine =~ /mac_ip_version=(.*)/;
        }
        if ( $ipVersion ne '' and $ipAddr ne '' ) {
            $ips{$ipAddr}{'adapterAddr'} = $adapterAddr;
            $ips{$ipAddr}{'ipVersion'} = $ipVersion;
            $ips{$ipAddr}{'lanName'} = $lanName if $lanName;
            #$ips{$ipAddr}{'lanOwner'} = $lanOwner if $lanOwner;
            $ips{$ipAddr}{'macAddr'} = $macAddr;
            $adapter{$adapterAddr}{'ipCnt'} += 1;
        }
    }

    my $adapterCnt = keys %adapter;
    push @{$rsp->{data}}, "For userid $activeSystem, $adapterCnt adapters were detected." if ( $args{'verbose'} == 1 );
    foreach $adapterAddr ( keys %adapter ) {
        if ( $adapter{$adapterAddr}{'macCnt'} > 0 ) {
            if ( $adapter{$adapterAddr}{'ipCnt'} != 0 ) {
                push @{$rsp->{data}}, "  Adapter $adapterAddr: $adapter{$adapterAddr}{'macCnt'} MACs with $adapter{$adapterAddr}{'ipCnt'} associated IP address(es)" if ( $args{'verbose'} == 1 );
            } else {
                push @{$rsp->{data}}, "  Adapter $adapterAddr: $adapter{$adapterAddr}{'macCnt'} MACs but no associated IP addresses" if ( $args{'verbose'} == 1 );
                push @failureInfo, "Adapter $adapterAddr: $adapter{$adapterAddr}{'macCnt'} MACs but no associated IP addresses";
            }
        } elsif ( $adapter{$adapterAddr}{'status'} eq '00' ) {
           push @{$rsp->{data}}, "  Adapter $adapterAddr: Not coupled" if ( $args{'verbose'} == 1 );
           push @failureInfo, "Adapter $adapterAddr: Not coupled";
        } elsif ( $adapter{$adapterAddr}{'status'} eq '01' ) {
            push @{$rsp->{data}}, "  Adapter $adapterAddr: Not active" if ( $args{'verbose'} == 1 );
            push @failureInfo, "Adapter $adapterAddr: Not active";
        } else {
            push @{$rsp->{data}}, "  Adapter $adapterAddr: No MACs with associated IP addresses" if ( $args{'verbose'} == 1 );
            push @failureInfo, "Adapter $adapterAddr: No MACs with associated IP addresses";
        }
    }
    xCAT::MsgUtils->message( "I", $rsp, $callback ) if ( $args{'verbose'} == 1 );

    if ( !%ips ) {
        if ( keys %adapter eq 0 ) {
            push @failureInfo, "No adapters were found";
        } else {
            push @failureInfo, "No IP addresses were detected";
        }

        goto FINISH_findAccessIP;
    }

    # Contact the IPs to see which one, if any, lets us in.
    foreach $ipAddr ( keys %ips ) {
        $rc = 0;
        if ( $ips{$ipAddr}{'ipVersion'} eq '6' ) {
            # IPv6 is not currently supported.
            next;
        }

        if ( $args{'ipfilter'} ) {
            if ( $ipAddr !~ m/$args{'ipfilter'}/i ) {
                if ( $args{'verbose'} == 1 ) {
                    push @{$rsp->{data}}, "For userid $activeSystem, filtered out IP: $ipAddr";
                    xCAT::MsgUtils->message( "I", $rsp, $callback );
                }
                push @failureInfo, "$ipAddr - filtered out by the specified IP filter";
                next;
            }
        }

        # Ping the address to see if it is responsive.
        if ( $ips{$ipAddr}{'ipVersion'} eq '4' ) {
            $out = `ping -c1 $ipAddr`;
            $rc = $?;
        } elsif ( $ips{$ipAddr}{'ipVersion'} eq '6' ) {
            # IPv6 is not currently supported.
            $rc = 3;
            #$out = `ping6 -c1 $ipAddr`;
            #$rc = $?;
            next;
        } else {
            push @{$rsp->{data}}, "Userid $activeSystem, IP address: $ipAddr has an unsupported IP version: $ips{$ipAddr}";
            xCAT::MsgUtils->message( "E", $rsp, $callback );
            next;
        }
        if ( $rc != 0 or $out !~ / 0% packet loss,/ ) {
            if ( $args{'verbose'} == 1 ) {
                push @{$rsp->{data}}, "For userid $activeSystem, ping failed for $ipAddr";
                xCAT::MsgUtils->message("I", $rsp, $callback);
            }
            push @failureInfo, "$ipAddr - Unable to ping, rc: $rc";
            next;
        }

        # SSH into the system to verify access.
        my $line = `ssh -q $ipAddr pwd 2>/dev/null`;
        $rc = $? >> 8;
        if ( $rc == 255 ) {
            if ( $args{'verbose'} == 1 ) {
                push @{$rsp->{data}}, "For userid  $activeSystem, Unable to ssh into: $ipAddr";
                xCAT::MsgUtils->message("I", $rsp, $callback);
            }
            push @failureInfo, "$ipAddr - Unable to ssh into system";
            next;
        }

        # Determine the fully qualified host name to use.
        my $fqdn = '';

        # Attempt to get it from the system's OS using one of a number of commands.
        # If we can't get a fully qualified DNS names (with periods) then accept the short name.
        my $shortName = '';
        foreach my $cmd ( @hostnameCmds ) {
            my $hostname = `ssh -q $ipAddr $cmd 2>/dev/null`;
            my $rc = $? >> 8;
            if ( $rc == 255 ) {
                if ( $args{'verbose'} == 1 ) {
                    my $rsp;
                    push @{$rsp->{data}}, "For userid $activeSystem, Unable to ssh into: $ipAddr";
                    xCAT::MsgUtils->message("I", $rsp, $callback);
                    push @failureInfo, "$ipAddr - Unable to ssh into system";
                    last;
                }
                last;
            } elsif ( $rc == 0 ) {
                # verify the hostname is a fully qualified name.
                chomp $hostname;
                if ( $hostname =~ /\./ ) {
                    $fqdn = $hostname;
                    last;
                } else {
                    $hostname =~ s/^\s+//;
                    if (( $hostname ne '' ) && ( $hostname !~ /\s/ )) {
                        # Single word returned without periods.  Must be a short name.
                        $shortName = $hostname;
                    }
                    # Keep looking for a long name but we will remember the short name
                    # in case we can't find a long name.
                }
            } else {
                if ( $args{'verbose'} == 1 ) {
                    my $rsp;
                    push @{$rsp->{data}}, "For userid  $activeSystem, \'$cmd\' returned, rc: $rc.";
                    xCAT::MsgUtils->message("I", $rsp, $callback);
                }
            }
        }
        if (( $shortName eq '' ) && ( $rc != 255 )) {
            push @failureInfo, "$ipAddr - hostname query commands failed to return required information";
        }

        if (( $fqdn eq '' ) && ( $shortName ne '' )) {
            if ( $args{'verbose'} == 1 ) {
                my $rsp;
                push @{$rsp->{data}}, "For userid  $activeSystem, Unable to determine the fully qualified domain name but found a short name.  The short name will be used.";
                xCAT::MsgUtils->message("I", $rsp, $callback);
            }
            $fqdn = $shortName;
        }

        # Found the last piece of info needed.
        # Note: If hostname is empty because we could not find it, the ultimate response will
        #       be a failing return code.
        $sysInfoRef->{$activeSystem}{'adapterAddr'} = $ips{$ipAddr}{'adapterAddr'};;
        $sysInfoRef->{$activeSystem}{'ipAddr'} = $ipAddr;
        $sysInfoRef->{$activeSystem}{'ipVersion'} = $ips{$ipAddr};
        $sysInfoRef->{$activeSystem}{'macAddr'} = $ips{$ipAddr}{'macAddr'};
        $sysInfoRef->{$activeSystem}{'switch'} = $ips{$ipAddr}{'lanName'};
        $sysInfoRef->{$activeSystem}{'hostname'} = $fqdn;
        last;
    }

FINISH_findAccessIP:
    if ( $sysInfoRef->{$activeSystem}{'hostname'} ) {
        $rc = 0;
    } else {
        $rc = 1;
        if ( @failureInfo ) {
            my $rsp;
            my $failureString = join( ',\n', @failureInfo );
            push @{$rsp->{data}}, "Unable to access $activeSystem for the following reasons:\n$failureString";
            xCAT::MsgUtils->message("I", $rsp, $callback);

            $failureString = join( ', ', @failureInfo );
            xCAT::zvmUtils->printSyslog( "findAccessIP() Unable to access $activeSystem for the following reasons: $failureString" );
        }
    }
    return $rc;
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
    my ( $class, $userId, $password, $memorySize, $privilege, $profileName, $cpuCount, $ipl) = @_;

    # If a file of this name already exists, just override it
    my $file = "/tmp/$userId.txt";
    my $content = "USER $userId $password $memorySize $memorySize $privilege\nINCLUDE $profileName\nCPU 00 BASE\n";

    # Add additional CPUs
    my $i;
    for ( $i = 1; $i < $cpuCount; $i++ ) {
        $content = $content.sprintf("CPU %02X\n", $i);
    }

    if ( $ipl != "") {
        # the caller need validate this $ipl param
        $content = $content.sprintf("IPL %04s\n", $ipl);
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
        #$out = `ssh $user\@$node "$cmd"`;
        $out = xCAT::zvmUtils->execcmdonVM($user, $node, $cmd); # caller sets $user to $::SUDOER
        return $out;
    }
    # Encapsulate command in single quotes
    $cmd = "'" . $cmd . "'";
    #$out = `ssh $user\@$node "$sudo sh -c $cmd"`;
    $cmd = "$sudo sh -c $cmd";
    $out = xCAT::zvmUtils->execcmdonVM($user, $node, $cmd); # caller sets $user to $::SUDOER
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
                  Install root directory
                  Local directory to remotely mount
                  Mount access ('ro' for read only, 'rw' for read write)
                  Directory as known to zHCP (out)
    Returns     : 0 - Mounted, or zHCP and MN are on the same system
                  1 - Mount failed
    Example     : establishMount( $callback, $::SUDOER, $::SUDO, $hcp, $installRoot, $provMethod, "ro", \$remoteDeployDir );

=cut

#-------------------------------------------------------
sub establishMount {
    # Get inputs
    my ($class, $callback, $sudoer, $sudo, $hcp, $installRoot, $localDir, $access, $mountedPt) = @_;
    my $out;

    # If the target system is not on this system then establish the NFS mount point.
    my $hcpIP = xCAT::NetworkUtils->getipaddr( $hcp );
    if (! defined $hcpIP) {
        xCAT::zvmUtils->printLn( $callback, "(Error) Unable to obtain the IP address of the hcp node" );
        return 1;
    }

    # Get internal master IP if xcat and zhcp are on a 10. network
    my $masterIp = xCAT::TableUtils->get_site_attribute("internalmaster");

    # Use "internalmaster", if it is set.  Otherwise, look at "master" property.
    if (!defined $masterIp) {

        $masterIp = xCAT::TableUtils->get_site_attribute("master");
        if (! defined $masterIp) {
            xCAT::zvmUtils->printLn( $callback, "$hcp: (Error) Unable to obtain the management node IP address from the site table" );
            return 1;
        }
    }

    if ($masterIp eq $hcpIP) {
        # xCAT MN and zHCP are on the same box and will use the same directory without the need for an NFS mount.
        $$mountedPt = "$installRoot/$localDir";
    } else {
        # Determine the hostname for this management node
        my $masterHostname = Sys::Hostname::hostname();
        if (! defined $masterHostname) {
            # For some reason, the xCAT MN's hostname is not known.  We pass along the IP address instead.
            $masterHostname = $masterIp;
        }

        $$mountedPt = "/mnt/$masterHostname$installRoot/$localDir";

        # If the mount point already exists then return because we are done.
        my $rc = `ssh $sudoer\@$hcp "$sudo mount | grep $$mountedPt > /dev/null; echo \\\$?"`;
        if ($rc == 0) {
            return 0;
        }

        xCAT::zvmUtils->printSyslog( "establishMount() Preparing the NFS mount point on zHCP ($hcpIP) to xCAT MN $masterHostname($masterIp) for $localDir" );

        # Prepare the staging mount point on zHCP, if they need to be established
        $rc = `ssh $sudoer\@$hcp "$sudo mkdir -p $$mountedPt && mount -t nfs -o $access $masterIp:/$localDir $$mountedPt; echo \\\$?"`;

        # Return code = 0 (mount succeeded)
        if ($rc != '0') {
            xCAT::zvmUtils->printLn( $callback, "$hcp: (Error) Unable to establish zHCP mount point: $$mountedPt" );
            xCAT::zvmUtils->printSyslog( "establishMount() Unable to establish zHCP mount point: $$mountedPt, rc: $rc" );
            return 1;
        }
    }

    return 0;
}

#-------------------------------------------------------

=head3   getFreeRepoSpace

    Description : Get the free space of image repository under /install.
    Arguments   : Node
    Returns     : The available space for /install (e.g. "2.1G ").
                  The value is returned as a perl string (e.g. "0 ") to
                  avoid perl returning null instead of "0" in the case
                  of no space available.
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

        # Comment out the horizontal whitespace escape, it was causing "Restarting xCATd Unrecognized escape"
        # $out =~ s/\h+/ /g;

        my @results = split(' ', $out);
        if ( $results[3] eq "0" ) {
            $results[3] = "0M";
        }
        return $results[3];
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
    if ($fcpDevice && ($fcpDevice !~ /^auto/i) && ($fcpDevice =~ /[^0-9a-f;]/i)) {
        xCAT::zvmUtils->printLn($callback, "$header: (Error) Invalid FCP channel address $fcpDevice.");
        return \%results;
    }

    # Owner must be specified if status is used
    if ($status =~ m/used/i && !$owner) {
        xCAT::zvmUtils->printLn( $callback, "$header: (Error) Owner must be specified if status is used." );
        return \%results;
    } elsif ($status =~ m/free/i && $owner) {
        xCAT::zvmUtils->printLn( $callback, "$header: (Error) Owner must not be specified if status is free." );
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

        # Check WWPN and LUN syntax
        if ( $wwpn && ($wwpn =~ /[^0-9a-f;]/i) ) {
            xCAT::zvmUtils->printLn( $callback, "$header: (Error) Invalid world wide portname $wwpn." );
            return \%results;
        } if ( $lun && ($lun =~ /[^0-9a-f]/i) ) {
            xCAT::zvmUtils->printLn( $callback, "$header: (Error) Invalid logical unit number $lun." );
            return \%results;
        }
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
        if (!$wwpn || !$lun) {
            xCAT::zvmUtils->printLn($callback, "$header: (Error) A suitable device of $size" . "M or larger could not be found");
            return \%results;
        }
    } else {
        # Find given WWPN and LUN. Do not continue if device is used
        my $select = `ssh $user\@$hcp "$sudo cat $zfcpDir/$pool.conf" | grep -i "$wwpn,$lun"`;
        chomp($select);
        if (!$select) {
            xCAT::zvmUtils->printLn($callback, "$header: (Error) zFCP device 0x$wwpn/0x$lun could not be found in zFCP pool $pool");
            return \%results;
        }

        @info = split(',', $select);

        if ($size) {
            if ($info[3] =~ m/G/i) {
                # Convert to MegaBytes
                $info[3] =~ s/\D//g;
                $info[3] = int($info[3]) * 1024
            } else {
                # Do nothing
                $info[3] =~ s/\D//g;
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

    xCAT::zvmUtils->printLn($callback, "$header: Found FCP device 0x$wwpn/0x$lun");

    if ( ($status =~ m/used/i) && ($fcpDevice =~ /^auto/i) ) {
        # select an eligible FCP device
        $fcpDevice = xCAT::zvmUtils->selectFcpDevice($callback, $header, $user, $hcp, $fcpDevice, $range, $owner);
        if (!$fcpDevice) {
            return \%results;
        }
    } elsif ($status =~ m/free/i) {
        # Owner and FCP channel make no sense when status is free
        $fcpDevice = "";
        $owner = "";
    }

    # Mark WWPN and LUN as used, free, or reserved and set the owner/channel appropriately
    # This config file keeps track of the owner of each device, which is useful in nodeset
    $size = $size . "M";
    my $select = `ssh $user\@$hcp "$sudo cat $zfcpDir/$pool.conf" | grep -i "$lun"`;
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
        $out = `ssh $user\@$hcp "$sudo echo \"$status,$wwpn,$lun,$size,,$owner,$fcpDevice,$tag\" >> $zfcpDir/$pool.conf"`;
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

=head3   selectFcpDevice

    Description : Select an eligible FCP device for attaching a zFCP device to a node
    Arguments   :   Message header
                    User (root or non-root)
                    zHCP
                    candidate FCP devices or auto
                    FCP device range
                    zFCP device owner
    Returns     : selected FCP device or empty if no one is selected
    Example     : my $fcpDevice = xCAT::zvmUtils->selectFcpDevice($callback, $header, $user, $hcp, $fcpDevice, $range, $owner);

=cut

#-------------------------------------------------------
sub selectFcpDevice {
    # Get inputs
    my ($class, $callback, $header, $user, $hcp, $fcpDevice, $range, $owner) = @_;

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

    # Check FCP device syntax
    if ($fcpDevice && ($fcpDevice !~ /^auto/i) && ($fcpDevice =~ /[^0-9a-f]/i)) {
        xCAT::zvmUtils->printLn($callback, "$header: (Error) Invalid FCP channel address $fcpDevice.");
        return;
    }

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
                my @info = split(' ', $_);
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
            my $out = `ssh $user\@$hcp "$sudo $dir/smcli System_WWPN_Query -T $hcpUserId" | egrep -i "FCP device number|Status"`;
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

                            # Use found FCP channel if not in use or allocated
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
            return;
        }
    }

    # If there are multiple devices (multipathing), take the 1st one
    if ($fcpDevice) {
        if ($fcpDevice =~ m/;/i) {
            my @info = split(';', $fcpDevice);
            $fcpDevice = xCAT::zvmUtils->trimStr($info[0]);
        }

        # Make sure channel has a length of 4
        while (length($fcpDevice) < 4) {
            $fcpDevice = "0" . $fcpDevice;
        }
    }

    return $fcpDevice;
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
    my @pools = split("\n", `ssh $user\@$hcp "$sudo grep -i -l \\\"$wwpn,$lun\\\" $zfcpDir/*.conf"`);
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
    Example     : my $deviceRef = xCAT::zvmUtils->findzFcpDeviceAttr($user, $hcp, $pool, $wwpn, $lun);

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
    my @info = split("\n", `ssh $user\@$hcp "$sudo grep -i \"$wwpn,$lun\" $zfcpDir/$pool.conf"`);
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

#-------------------------------------------------------

=head3   findUsablezHcpNetwork

    Description : Find a useable NIC shared with the zHCP for a given user Id
    Arguments   :   User (root or non-root)
                    zHCP
                    User Id to find a useable NIC on
                    DHCP is used or not (0 or 1)
    Returns     : NIC, device channel, and layer (2 or 3)
    Example     : my ($nic, $channel, $layer) = xCAT::zvmUtils->findUsablezHcpNetwork($user, $hcp, $userId, $dhcp);

=cut

#-------------------------------------------------------
sub findUsablezHcpNetwork {
        # Get inputs
    my ( $class, $user, $hcp, $userId, $dhcp ) = @_;

    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }

    my $nic = '';  # Usuable NIC on zHCP
    my $channel = '';  # Device channel where NIC is attached
    my $layer;
    my $i;
    my @words;

    # Get the networks used by the zHCP
    my @hcpNetworks = xCAT::zvmCPUtils->getNetworkNamesArray($user, $hcp);

    # Search directory entry for network name
    my $userEntry = `ssh $user\@$hcp "$sudo $::DIR/smcli Image_Query_DM -T $userId" | sed '\$d'`;
    xCAT::zvmUtils->printSyslog("findUsablezHcpNetwork() smcli Image_Query_DM -T $userId");
    xCAT::zvmUtils->printSyslog("findUsablezHcpNetwork() $userEntry");

    my $out = `echo "$userEntry" | grep "NICDEF"`;
    my @lines = split('\n', $out);

    # Go through each line
    for ($i = 0; $i < @lines; $i++) {
        # Go through each network device attached to zHCP
        foreach (@hcpNetworks) {

            # If network device is found
            if ($lines[$i] =~ m/ $_/i) {
                # Get network layer
                $layer = xCAT::zvmCPUtils->getNetworkLayer($user, $hcp, $_);
                xCAT::zvmUtils->printSyslog("findUsablezHcpNetwork() NIC:$_ layer:$layer");

                # If template using DHCP, layer must be 2
                if ((!$dhcp && $layer != 2) || (!$dhcp && $layer == 2) || ($dhcp && $layer == 2)) {
                    # Save network name
                    $nic = $_;

                    # Get network virtual address
                    @words = split(' ',  $lines[$i]);

                    # Get virtual address (channel)
                    # Convert subchannel to decimal
                    $channel = sprintf('%d', hex($words[1]));

                    xCAT::zvmUtils->printSyslog("findUsablezHcpNetwork() Candidate found NIC:$nic channel:$channel layer:$layer");
                    return ($nic, $channel, $layer);
                } else {
                    # Go to next network available
                    $nic = '';
                }
            }
        }
    }

    # If network device is not found
    if (!$nic) {
        # Check for user profile
        my $profileName = `echo "$userEntry" | grep "INCLUDE"`;
        if ($profileName) {
            @words = split(' ', xCAT::zvmUtils->trimStr($profileName));

            # Get user profile
            my $userProfile = xCAT::zvmUtils->getUserProfile($user, $hcp, $words[1]);
            xCAT::zvmUtils->printSyslog("findUsablezHcpNetwork() $userProfile");

            # Get the NICDEF statement
            $out = `echo "$userProfile" | grep "NICDEF"`;
            @lines = split('\n', $out);

            # Go through each line
            for ($i = 0; $i < @lines; $i++) {
                # Go through each network device attached to zHCP
                foreach (@hcpNetworks) {

                    # If network device is found
                    if ($lines[$i] =~ m/ $_/i) {
                        # Get network layer
                        $layer = xCAT::zvmCPUtils->getNetworkLayer($user, $hcp, $_);
                        xCAT::zvmUtils->printSyslog("findUsablezHcpNetwork() NIC:$_ layer:$layer");

                        # If template using DHCP, layer must be 2
                        if ((!$dhcp && $layer != 2) || (!$dhcp && $layer == 2) || ($dhcp && $layer == 2)) {
                            # Save network name
                            $nic = $_;

                            # Get network virtual address
                            @words = split(' ',  $lines[$i]);

                            # Get virtual address (channel)
                            # Convert subchannel to decimal
                            $channel = sprintf('%d', hex($words[1]));

                            xCAT::zvmUtils->printSyslog("findUsablezHcpNetwork() Candidate found NIC:$nic channel:$channel layer:$layer");
                            return ($nic, $channel, $layer);
                        } else {
                            # Go to next network available
                            $nic = '';
                        }
                    }
                } # End of foreach
            } # End of for
        } # End of if
    }

    return;
}

#-------------------------------------------------------

=head3   printInfo

    Description : Print a long string to stdout as information without checking anything
    Arguments   : String
    Returns     : Nothing
    Example     : xCAT::zvmUtils->printInfo($callback, $str);

=cut

#-------------------------------------------------------
sub printInfo {

    # Get inputs
    my ( $class, $callback, $str ) = @_;

    # Print string
    my $rsp;

    $rsp->{data}->[0] = "$str";
    xCAT::MsgUtils->message( "I", $rsp, $callback );

    return;
}

#-------------------------------------------------------

=head3   getSpecialCloneInfo

    Description : Look in the /var/opt/xcat/doclone.txt file (if exists) and return a
                  hash of the keys and values found that match the image name parameter
    Arguments   : User friendly image name

    Returns     : hash of keys and values found or empty hash
    Example     : my %cloneinfo = xCAT::zvmUtils->getSpecialCloneInfo($callback, $user, $node);
                  if (%cloneinfo) {
                      %cloneinfo has at least one key
                  } else {
                      %cloneinfo empty, no keys
                  }

=cut

#-------------------------------------------------------
sub getSpecialCloneInfo {

    # Get inputs
    my ( $class, $imagename ) = @_;
    my %cloneInfoHash = (); # create empty hash

    # Directory where doclone.txt is
    my $dir       = '/var/opt/xcat/';
    my $clonefile = 'doclone.txt';
    my $out;

    # Does the file exist? If so read and look for this image name
    if (-e "$dir$clonefile") {
        # look for this image name and ignore case
        $out = `cat $dir$clonefile | grep -v '^\\s*/[*]'| grep -v '^\\s*[*]'| grep -E -i -w "IMAGE_NAME[[:blank:]]*=[[:blank:]]*$imagename"`;

        my @lines = split( '\n', $out );
        my $count = @lines;

        # loop for any lines found
        for (my $i=0; $i < $count; $i++) {
            # Break out each key=value; item
            my @parms = split( ';', $lines[$i]);
            my $parmcount = @parms;
            # get the key and value for this item, store in hash
            for (my $j=0; $j < $parmcount; $j++) {
                my @keyvalue = split('=', $parms[$j]);
                my $key   = $keyvalue[0];
                $key =~ s/^\s+|\s+$//g; # get rid of leading and trailing blanks
                next if ( length( $key ) == 0 ); # Skip incorrect key=value data

                my $value = $keyvalue[1];
                $value =~ s/^\s+|\s+$//g;
                next if ( length( $value ) == 0 ); # Skip incorrect key=value data
                #uppercase both key and value;
                $key   = uc $key;
                $value = uc $value;
                $cloneInfoHash{ $key } = $value;
            }
        }
    }
    return (%cloneInfoHash);
}

#-------------------------------------------------------

=head3   pingNode

    Description : Execute a Perl ping for this node
    Arguments   : Node name

    Returns     : "ping" if found;  or "noping" (if not found)
    Example     : my $out = xCAT::zvmUtils->pingNode($node);

=cut

#-------------------------------------------------------
sub pingNode {

    # Get input node
    my ( $class, $node ) = @_;

    my $timeout = 2; # how many seconds to wait for response. Default was 5
    # call system ping and max count of pings 2
    my $out = `ping -W $timeout -c 2 -q $node`;
    if ($? != 0) {
        # Ping failed, try to get result with execcmdonVM.
        my $result = xCAT::zvmUtils->execcmdonVM($::SUDOER, $node, 'date');
        if (xCAT::zvmUtils->checkOutput( $result ) == -1) {
           return $result;
        }
        if ($result) {
            return ("ping");
        }
        return ("noping");
    }
    return ("ping");
}

#-------------------------------------------------------

=head3   onlineZhcpPunch

    Description : Online punch device and load VMCP module on zHCP
    Arguments   : User (root or non-root)
                  zHCP
    Returns     : Operation results (Done/Failed)
    Example     : my $out = xCAT::zvmUtils->onlineZhcpPunch($user, $hcp);

=cut

#-------------------------------------------------------
sub onlineZhcpPunch {

    # Get input node
    my ( $class, $user, $hcp ) = @_;

    my $out = "";
    my $subResp = "";
    my $rc = "";

    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }

    # Online zHCP's punch
    $out = `ssh $user\@$hcp "$sudo cat /sys/bus/ccw/drivers/vmur/0.0.000d/online" 2>&1`;
    $rc = $? >> 8;
    if ( $rc == 255 ) {
        # SSH failure to communicate with zHCP.
        $subResp = "Failed to communicate with the zHCP system to get the punch device status";
    } elsif ( $rc != 0 ) {
        # Generic failure of the command.
        chomp( $out );
        xCAT::zvmUtils->printSyslog( "onlineZhcpPunch() Failed to get the punch device status on zHCP rc: $rc, out: $out" );
        $subResp = "Failed to online the punch device on zHCP rc: $rc, out: $out";
    }

    if ( $subResp eq "" ) {
        if ($out != 1) {
            chomp( $out = `ssh $user\@$hcp "$sudo /sbin/cio_ignore -r 000d; /sbin/chccwdev -e 000d"`);
            $rc = $? >> 8;
            if ( $rc == 0 ) {
                $subResp = "Done";
            } elsif ( $rc == 255 ) {
                # SSH failure to communicate with zHCP.
                $subResp = "Failed to communicate with the zHCP system to online the punch device";
            } else {
                if ( !( $out =~ m/Done$/i ) ) {
                    xCAT::zvmUtils->printSyslog("onlineZhcpPunch() failed to online the zHCP's punch, cmd output: $out.");
                    $subResp = "Failed to online the zHCP's punch rc: $rc, out: $out";
                }
            }
            `ssh $user\@$hcp "$sudo which udevadm &> /dev/null && udevadm settle || udevsettle"`;
        } else {
            $subResp = "Done";
        }
    }
    return $subResp
}

#-------------------------------------------------------
=head3   genCfgdrive

    Description : Generate a final config drive to punch
    Arguments   : Configure file directory

    Returns     : Generated config drive file path
    Example     : my $out = xCAT::zvmUtils->genCfgdrive($path);

=cut

#-------------------------------------------------------
sub genCfgdrive {

    # Get input node
    my ( $class, $cfgpath ) = @_;
    my $node = basename($cfgpath);

    my $out = xCAT::zvmUtils->injectMNKey($cfgpath);
    if ( $out =~ m/Failed/i ) {
        xCAT::zvmUtils->printSyslog("genCfgdrive() Failed to generate the final cfgdrive.tgz for target node: $node, out: $out");
        return "";
    } else {
        xCAT::zvmUtils->printSyslog("genCfgdrive() Successfully generated the final cfgdrive.tgz for target node: $node");
        return "$cfgpath/cfgdrive.tgz";
    }
}

#-------------------------------------------------------
=head3   injectMNKey

    Description : Inject xCAT MN's public key to the meta_data.json for target vm
    Arguments   : Configure file directory

    Returns     : A message indicate whether the MN's key in injected success or not
    Example     : my $out = xCAT::zvmUtils->injectMNKey($path);

=cut

#-------------------------------------------------------

sub injectMNKey {

    # Get input node
    my ( $class, $cfgpath ) = @_;
    my $subResp = "";

    if ( -e "$cfgpath/cfgdrive.tgz" ) {
        system("tar -zxf $cfgpath/cfgdrive.tgz -C $cfgpath ");
    } else {
        $subResp = "injectMNKey() Failed to find the cfgdrive.tgz under $cfgpath for target node";
        return $subResp;
    }

    # Get xcat key, store it to a hash var for later use
    open(my $keyFile, '<', "/root/.ssh/id_rsa.pub");
    my $mnKey = <$keyFile>;
    close($keyFile);
    my @set = ('0' ..'9', 'A' .. 'F');
    my $mnKeyName = join '' => map $set[rand @set], 1 .. 8;
    my %mnKeyHash = ("name" => $mnKeyName, "type" => "ssh", "data" => $mnKey,);

    # Read the file content to a variable named md_json,and close the source file
    my $jsonText;
    my $MDfile;
    if(open($MDfile, '<', "$cfgpath/openstack/latest/meta_data.json")) {
        while(<$MDfile>) {
            $jsonText .= "$_";
        }
    } else {
        $subResp = "injectMNKey() Failed to open the meta data file for processing";
        close($MDfile);
        return $subResp;
    }
    close($MDfile);

    # Get the public_keys from meta_data.json, if it not exist, add xCAT's key to meta_data.json directly,
    # if already exist, compare if the xCAT's key is same or not with existing one, append xCAT key if not same
    my $md_json = decode_json($jsonText);
    if (exists $md_json->{"public_keys"}) {
        my $publicKeys = $md_json->{"public_keys"};
        # Check if xCAT key already exist , append it if not exist.
        foreach my $pubkey ( keys %$publicKeys ) {
            if ( $publicKeys->{$pubkey} eq $mnKey ) {
                last;
            }
        $publicKeys->{$mnKeyName} = $mnKey;
        my @tkeys = $md_json->{"keys"};
        push @tkeys, {%mnKeyHash};
        #push $md_json->{"keys"}, {%mnKeyHash};
        }
    } else {
        # Set the public_keys and keys with xCAT's key info in meta_data.json
        $md_json->{"public_keys"}->{$mnKeyName} = $mnKey;
        $md_json->{"keys"}[0] = {%mnKeyHash};
    }

    # Save the changed meta_data.json to new file
    open my $fh, ">", "$cfgpath/meta_data.json";
    print $fh encode_json($md_json);
    close $fh;

    # Replace the meta_data.json file in original config drive with the modified one 
    system( "find $cfgpath/openstack -name meta_data.json -print | xargs -i cp  $cfgpath/meta_data.json {}");
    `rm -f $cfgpath/meta_data.json`;

    # Tar the file generate the final one
    my $oldpath=cwd();
    chdir($cfgpath);
    system ( "tar -zcf cfgdrive.tgz openstack ec2");
    chdir($oldpath);

    $subResp = "Done";
    return $subResp;
}

#-------------------------------------------------------

=head3   execcmdthroughIUCV

    Description : Execute a command to node with IUCV client.
    Arguments   : User (root or non-root).
                  zHCP (opencloud user)
                  VM's userid
                  command [parms..] the comands and parms with the command which need to execute.
                  callback

    Returns     : command result, if success.
                  if an error:
                    and $callback then $callback gets error message
                    returns with string containing (Error) and message
    Example     : my $out = xCAT::zvmUtils->execcmdthroughIUCV($user, $hcp, $userid, $command);

=cut

#-------------------------------------------------------
sub execcmdthroughIUCV {
    my ($class, $user, $hcp, $userid, $commandwithparm, $callback) = @_;
    my $result = '';
    my $rsp;
    my $msg;
    my $iucvpath = '/opt/zhcp/bin/IUCV';
    my $isCallback = 0;
    if (defined $callback) {
        $isCallback = 1;
    }
    $result= `ssh $user\@$hcp $::SUDO $iucvpath/iucvclnt $userid "\'$commandwithparm\'" 2>&1`;

    my $rc = $? >> 8;
    $result = xCAT::zvmUtils->trimStr( $result );
    if ( $isCallback || $rc == 0 ){
        xCAT::zvmUtils->printSyslog("$userid: IUCV command: ssh $user\@$hcp $::SUDO $iucvpath/iucvclnt $userid $commandwithparm. return $rc\n $result");
    } else {
        xCAT::zvmUtils->printSyslog("$userid: IUCV command: ssh $user\@$hcp $::SUDO $iucvpath/iucvclnt $userid $commandwithparm.");
    }
    if ( $rc == 0 ) {
        if ($result eq ''){
            return "Done";
        }
        return $result;
    } elsif ( $rc == 1 ) {
            $msg = "IUCV authorized error, error details $result";
            push @{$rsp->{data}}, $msg;
    } elsif ( $rc == 2 ) {
            $msg = "parameter to iucvclient error, $result";
            push @{$rsp->{data}}, $msg
    } elsif ( $rc == 4 ) {
            $msg = "IUCV socket error, error details $result";
            push @{$rsp->{data}}, $msg;
    } elsif ( $rc == 8 ) {
            $msg = "Command executed failed, error details $result";
            push @{$rsp->{data}}, $msg;
    } elsif ( $rc == 16 ) {
            $msg = "File Transport failed, error details $result";
            push @{$rsp->{data}}, $msg;
    } elsif ( $rc == 32 ) {
            $msg = "File Transport failed, error details $result";
            push @{$rsp->{data}}, $msg;
    }

    # Error occurred
    if ($isCallback){
        xCAT::MsgUtils->message( "E", $rsp, $callback );
    }
    return "(Error) $msg";
}

#-------------------------------------------------------

=head3   cleanIUCV

    Description : rollback IUCV to clean all the files that copy to it.
    Arguments   : User (root or non-root).
                  VM's node
                  VM's system

    Returns     :
    Example     : xCAT::zvmUtils->cleanIUCV( $user, $hcp, $userid);

=cut

#-------------------------------------------------------
sub cleanIUCV {
    my ($class, $user, $node, $os) = @_;

    my $sudo = "sudo";
    if ($user eq "root") {
        $sudo = "";
    }

    my $result = '';
    my $outmsg = '';
    my $cmd = '';
    my $rc;
    my $trgtiucvpath = "/usr/bin/iucvserv";
    my $trgtiucvservicepath_rh6_sl11 = "/etc/init.d/iucvserd";
    my $trgtiucvservicepath_rh7 = "/lib/systemd/system/iucvserd.service";
    my $trgtiucvservicepath_ubuntu16 = "/lib/systemd/system/iucvserd.service";
    my $trgtiucvservicepath_sl12 = "/usr/lib/systemd/system/iucvserd.service";

    #clean iucv server file
    $cmd = "ssh -o ConnectTimeout=5 $user\@$node rm -rf $trgtiucvpath 2>&1";
    $result = `ssh -o ConnectTimeout=5 $user\@$node rm -rf $trgtiucvpath 2>&1`;
    ($rc, $outmsg) = xCAT::zvmUtils->checkSSHOutput( $?, "$cmd" );
    if ($rc == -1) {
       xCAT::zvmUtils->printSyslog("$node: SSH to VM to clean iucv server file failed. $result");
       # Continue processing even if an error.
    }

    #clean iucv server service file
    if ( $os =~ m/sles11/i or $os =~ m/rhel6/i ) {
        $cmd = "ssh -o ConnectTimeout=5 $user\@$node rm -rf $trgtiucvservicepath_rh6_sl11 2>&1";
        $result = `ssh -o ConnectTimeout=5 $user\@$node rm -rf $trgtiucvservicepath_rh6_sl11 2>&1`;
    }
    elsif ( $os =~ m/sles12/i ) {
        $cmd = "ssh -o ConnectTimeout=5 $user\@$node rm -rf $trgtiucvservicepath_sl12 2>&1";
        $result = `ssh -o ConnectTimeout=5 $user\@$node rm -rf $trgtiucvservicepath_sl12 2>&1`;
    }
    elsif ( $os =~ m/rhel7/i){
        $cmd = "ssh -o ConnectTimeout=5 $user\@$node rm -rf $trgtiucvservicepath_rh7 2>&1";
        $result = `ssh -o ConnectTimeout=5 $user\@$node rm -rf $trgtiucvservicepath_rh7 2>&1`;
    } elsif ( $os =~ m/ubuntu16/i){
        $cmd = "ssh -o ConnectTimeout=5 $user\@$node rm -rf $trgtiucvservicepath_ubuntu16 2>&1";
        $result = `ssh -o ConnectTimeout=5 $user\@$node rm -rf $trgtiucvservicepath_ubuntu16 2>&1`;
    }
    ($rc, $outmsg) = xCAT::zvmUtils->checkSSHOutput( $?, "$cmd" );
    if ($rc == -1) {
        xCAT::zvmUtils->printSyslog("$node: SSH to VM to clean iucv server serivce file failed. $result");
        # Continue processing even if an error.
    }

    #clean iucv server authorized file
    $cmd = "ssh -o ConnectTimeout=5 $user\@$node rm -rf $trgtiucvpath 2>&1";
    $result = `ssh -o ConnectTimeout=5 $user\@$node rm -rf $trgtiucvpath 2>&1`;
    ($rc, $outmsg) = xCAT::zvmUtils->checkSSHOutput( $?, "$cmd" );
    if ($rc == -1) {
        xCAT::zvmUtils->printSyslog("$node: SSH to VM to clean iucv server authorized file failed. $result");
        # Continue processing even if an error.
    }

    #clean iucv server service start
    if ( $os =~ m/sles11/i or $os =~ m/rhel6/i ){
        $cmd = "ssh -o ConnectTimeout=5 $user\@$node \"chkconfig --del iucvserd && service iucvserd stop 2>&1";
        $result = `ssh -o ConnectTimeout=5 $user\@$node "chkconfig --del iucvserd && service iucvserd stop 2>&1"`;
        ($rc, $outmsg) = xCAT::zvmUtils->checkSSHOutput( $?, "$cmd" );
        if ($rc == -1) {
           xCAT::zvmUtils->printSyslog("$node: SSH to VM to clean iucv server serivce start failed. $result");
           # Continue processing even if an error.
        }
    }else{
        $cmd = "ssh -o ConnectTimeout=5 $user\@$node \"systemctl disable iucvserd.service && systemctl stop iucvserd.service 2>&1";
        $result = `ssh -o ConnectTimeout=5 $user\@$node "systemctl disable iucvserd.service && systemctl stop iucvserd.service 2>&1"`;
        ($rc, $outmsg) = xCAT::zvmUtils->checkSSHOutput( $?, "$cmd" );
        if ($rc == -1) {
           xCAT::zvmUtils->printSyslog("$node: SSH to VM to clean iucv server serivce start failed. $result");
           # Continue processing even if an error.
        }
    }
}

#-------------------------------------------------------

=head3   setsshforvm

    Description : If IUCV communication failed, try to use ssh to make communication.
    Arguments   : User (root or non-root).
                  VM's node
                  VM's linux system type
                  command [parms..] the comands and parms with the command which need to execute.
                  error message which is got in setup IUCV
                  current VM's status in zvm table
                  callback

    Returns     : command result, if success.
                  if an error:
                    and $callback then $callback gets error message and routine returns with 1
                    if no $callback then routine returns with string containing Error: and message
    Example     : my $out = xCAT::zvmUtils->setsshforvm($user, $node, $os, $commandwithparm, $msg, $status, $callback);

=cut

#-------------------------------------------------------

sub setsshforvm {
    my ($class, $user, $node, $os, $commandwithparm, $msg, $status, $callback) = @_;
    my $result ='';
    my $rsp;
    my $isCallback = 0;
    my $outmsg =  '';
    my $rc;
    if (defined $callback) {
        $isCallback = 1;
    }

    #clean IUCV server first.
    $result = xCAT::zvmUtils->cleanIUCV($user, $node, $os);
    if (xCAT::zvmUtils->checkOutput( $result ) == -1) {
       return $result;
    }
    # check whether the vm can be ping, if so then set ssh to zvm table,
    # to indicate that it use ssh.
    my $ping = `ping -W 2 -c 2 -q $node`;
    if ($? == 0) {
        my $cmd = "ssh -o ConnectTimeout=5 $user\@$node \"$commandwithparm\"";
        $result = `ssh -o ConnectTimeout=5 $user\@$node "$commandwithparm"`;
        ($rc, $outmsg) = xCAT::zvmUtils->checkSSHOutput( $?, "$cmd" );
        if ($rc == -1) {
            if ($isCallback){
                xCAT::zvmUtils->printLn( $callback, "$node: $outmsg");
            }
            # Continue processing even if an error.
        }

        if ($status){
            $status = "$status;SSH=1";
        }else{
            $status = "SSH=1";
        }
        xCAT::zvmUtils->setNodeProp( 'zvm', $node, 'status', $status );
        xCAT::zvmUtils->printSyslog("$node: Set SSH=1 for node $node");
        if ($isCallback){
            xCAT::zvmUtils->printLn( $callback, "$node: Set SSH=1 for node $node.");
        }
        return $result;
    }

    # Error occurred on ping
    if ($callback){
        push @{$rsp->{data}}, $msg;
        xCAT::MsgUtils->message( "E", $rsp, $callback );
    }
    xCAT::zvmUtils->printSyslog("$node: $msg");
    return "$msg";
}

#-------------------------------------------------------

=head3   execcmdonVM

    Description : Execute a command to node.
    Arguments   : User (root or non-root).
                  VM's node
                  command [parms..] the comands and parms with the command which need to execute.
                  callback

    Returns     : command result, if success.
                  if an error:
                    and $callback then $callback gets error message
                    routine returns with string containing Error: and message

    Example     : my $out = xCAT::zvmUtils->execcmdonVM($user, $node, $commandwithparm, $callback);

=cut

#-------------------------------------------------------
sub execcmdonVM {
    my ($class, $user, $node, $commandwithparm, $callback) = @_;

    # get HCP and z/VM userid
    my @propNames = ( 'hcp', 'userid', 'status' );
    my $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $node, @propNames );
    my $status = $propVals->{'status'};
    if(!(defined($status))){
        $status = '';
    }
    my $hcp = $propVals->{'hcp'};
    my $userid = $propVals->{'userid'};
    my $isCallback = 0;
    if (defined $callback) {
        $isCallback = 1;
    }

    my $result = '';
    my $outmsg =  '';
    my $rsp;
    my $rc;
    my $msg = '';
    my $cmd = '';
    my $opnclouduserid='OPNCLOUD';

    # Create path string
    my $dest = "$user\@$node";
    my $srciucvpath = '/opt/zhcp/bin/IUCV';
    my $trgtiucvpath = "/usr/bin/iucvserv";
    my $trgtiucvservicepath_rh6_sl11 = "/etc/init.d/iucvserd";
    my $trgtiucvservicepath_rh7 = "/lib/systemd/system/iucvserd.service";
    my $trgtiucvservicepath_sl12 = "/usr/lib/systemd/system/iucvserd.service";
    my $trgtiucvservicepath_ubuntu16 = "/lib/systemd/system/iucvserd.service";
    my $authorizedfilepath = "/etc/iucv_authorized_userid";
    my $xcatuserid = `vmcp q userid | awk '{print \$1}'`;
    chomp($xcatuserid);

    # Add escape for IUCV and SSH commands.
    if ($commandwithparm =~ '\\\"'){
        $commandwithparm =~ s/"/\\"/g;
    }
    $commandwithparm =~ s/"/\\"/g;

    # For not xcat deployed node, use SSH to make communication.
    if (!(defined($userid)) || !(defined($hcp))){
        $cmd = "ssh -o ConnectTimeout=5 $user\@$node \"$commandwithparm\"";
        $result = `ssh -o ConnectTimeout=5 $user\@$node "$commandwithparm"`;
        ($rc, $outmsg) = xCAT::zvmUtils->checkSSHOutput( $?, "$cmd" );
        if ($rc == -1) {
            xCAT::zvmUtils->printSyslog("$node: $cmd $outmsg");
            if ($isCallback){
                xCAT::zvmUtils->printLn( $callback, "$node: $outmsg");
            }
        }
        # Remove IUCV=1 if it has been set
        if ($status =~ /IUCV=1/){
            $status =~ s/IUCV=1/SSH=1/g;
            xCAT::zvmUtils->setNodeProp( 'zvm', $node, 'status', $status );
        }
        return $result;
    }

    $userid =~ tr/a-z/A-Z/;
    # For normal managed nodes, ask zhcp to query the power state
    if (($userid ne $xcatuserid) && !($hcp =~ /$node/) && ($hcp ne '')){
        # Get VM's power stat first, if power stat is off, return error.
        my $max = 0;
        while ( !$result && $max < 10 ) {
            $cmd = "ssh $::SUDOER\@$hcp \"$::SUDO /sbin/vmcp q user $userid 2>/dev/null\" | sed 's/HCPCQU045E.*/off/' | sed 's/$userid.*/on/'";
            $result = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/vmcp q user $userid 2>/dev/null" | sed 's/HCPCQU045E.*/off/' | sed 's/$userid.*/on/'`;
            ($rc, $outmsg) = xCAT::zvmUtils->checkSSHOutput( $?, "$cmd" );
            if ($rc == -1) {
                if ($isCallback){
                    xCAT::zvmUtils->printLn( $callback, "$node: $outmsg");
                }
               return $outmsg;
            }
            $max++;
        }
        #xCAT::zvmUtils->printSyslog("$node: ssh $::SUDOER\@$hcp \"$::SUDO /sbin/vmcp q user $userid 2>/dev/null\" | sed 's/HCPCQU045E.*/off/' | sed 's/$userid.*/on/' ##$result##");
        if ("off" =~ $result) {
            my $msgText = "$node: (Error) VM $userid is powered off";
            xCAT::zvmUtils->printSyslog("$msgText");
            if ($isCallback) {
                xCAT::zvmUtils->printLn( $callback, "$msgText");
            }
            return "$msgText";
        }

        if (!($status =~ /SSH=1/) && !($status =~ /IUCV=1/)){
            # if zhcp direct entry does set "IUCV ANY", will set to SSH directly.
            my $hcpUserId = xCAT::zvmCPUtils->getUserId($user, $hcp);
            @propNames = ( 'status' );
            $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $hcp, @propNames );
            my $iucvanystatus = $propVals->{'status'};
            if (!($iucvanystatus =~ m/IUCVANY/i)){
                xCAT::zvmUtils->printSyslog("$node: zhcp's IUCVANY status is not set");
                my $out = `ssh $user\@$hcp "$::SUDO /opt/zhcp/bin/smcli Image_Query_DM -T $hcpUserId"| egrep -i "IUCV ANY"`;
                if ( $out =~ m/IUCV ANY/i){
                    if ($iucvanystatus){
                        $iucvanystatus = "$status;IUCVANY=1";
                    }else{
                        $iucvanystatus = "IUCVANY=1";
                    }
                }else{
                     if ($iucvanystatus){
                        $iucvanystatus = "$status;IUCVANY=0";
                    }else{
                        $iucvanystatus = "IUCVANY=0";
                    }
                }
                xCAT::zvmUtils->setNodeProp( 'zvm', $hcp, 'status', $iucvanystatus );
                xCAT::zvmUtils->printSyslog("$node: zhcp's status is $iucvanystatus");
            }
            if ($iucvanystatus =~ m/IUCVANY=0/i){
                xCAT::zvmUtils->printSyslog("$node: zhcp doesn't support to make communication with IUCV, set SSH=1 for $node");
                if ($status){
                    $status = "$status;SSH=1";
                }else{
                    $status = "SSH=1";
                }
                xCAT::zvmUtils->setNodeProp( 'zvm', $node, 'status', $status );
            }
        }
    }

    # If node userid is xcat or zhcp, only use SSH.
    if (($status =~ /SSH=1/) || ($userid eq $xcatuserid) || ($hcp =~ /$node/) || ($hcp eq '')){
        # SSH=1, Use ssh to make communication.
        $cmd = "ssh -o ConnectTimeout=5 $user\@$node \"$commandwithparm\"";
        $result = `ssh -o ConnectTimeout=5 $user\@$node "$commandwithparm"`;
        ($rc, $outmsg) = xCAT::zvmUtils->checkSSHOutput( $?, "$cmd" );
        if ($rc == -1) {
            if ($isCallback){
                xCAT::zvmUtils->printLn( $callback, "$node: $outmsg");
                xCAT::zvmUtils->printSyslog("$node: $cmd $outmsg");
            }
        }
        return $result;
    }elsif ($status =~ /IUCV=1/){
        #xCAT::zvmUtils->printSyslog("$node: IUCV command: $commandwithparm");
        # IUCV=1, Use IUCV to make communication.
        $result = xCAT::zvmUtils->execcmdthroughIUCV($user, $hcp, $userid, $commandwithparm, $callback);
        return $result;
    }

    xCAT::zvmUtils->printSyslog("$node: VM $userid doesn't set communicate type, will set it first." );
    my $releaseInfo = `ssh -qo ConnectTimeout=2 $user\@$node "$::SUDO ls /dev/null $locAllEtcVerFiles 2>/dev/null | xargs grep ''"`;
    if (xCAT::zvmUtils->checkOutput( $releaseInfo ) == -1) {
        return $releaseInfo;
    }
    my $os = buildOsVersion( $callback, $releaseInfo, 'all' );

    # For the existed VMs which are deployed with SSH, will try to copy IUCV files to them.
    # These VMs are not set communication type, try IUCV first and set the type after communication.
    # if IUCV server doesn't exist on xcat /var/lib/sspmod, first to copy from OPNCLOUD.
    if ( not (-e "$srciucvpath/iucvserv"  and -e "$srciucvpath/iucvserd"
             and -e "$srciucvpath/iucvserd.service" )) {
        $result= `mkdir -p $srciucvpath && scp -p $user\@$hcp:$srciucvpath/iucvser* $srciucvpath 2>&1`;
        $rc = $? >>8 ;
        xCAT::zvmUtils->printSyslog("$node: IUCV server files doesn't exist on xcat $srciucvpath, copy from OPNCLOUD.return $rc, $result");
        if ($rc != 0) {
            $msg = "Failed to copy $user\@$hcp:$srciucvpath/iucvser* to $srciucvpath. $result";
            return xCAT::zvmUtils->setsshforvm($user, $node, $os, $commandwithparm, $msg, $status, $callback);
        }
    }
    # Check whether IUCV server is installed.
    $result = xCAT::zvmUtils->execcmdthroughIUCV($user, $hcp, $userid, $commandwithparm, $callback);
    $rc = $? >> 8;
    xCAT::zvmUtils->printSyslog("$node: try to execute command through IUCV. $result return $?" );
    if ( $rc != 0 ){
        #IUCV server doesn't exist on node, copy file to it and restart service
        if ($result =~ "ERROR connecting socket") {
            xCAT::zvmUtils->printSyslog("$node: start to set iucv, first to copy iucv server files and start iucv server service" );
            #copy IUCV server files.
            $result = `/usr/bin/scp -p $srciucvpath/iucvserv $dest:$trgtiucvpath 2>&1`;
            $rc = $? >> 8;
            xCAT::zvmUtils->printSyslog("$node: /usr/bin/scp -p $srciucvpath/iucvserv $dest:$trgtiucvpath 2>&1 return $rc\n $result");
            if ($rc != 0) {
                $msg = "Failed to copy $srciucvpath/iucvserv to $dest:$trgtiucvpath. $result";
                return xCAT::zvmUtils->setsshforvm($user, $node, $os, $commandwithparm, $msg, $status, $callback);
            }
            if ( $os =~ m/sles11/i or $os =~ m/rhel6/i ) {
                $result = `/usr/bin/scp -p $srciucvpath/iucvserd $dest:$trgtiucvservicepath_rh6_sl11 2>&1`;
            }
            elsif ( $os =~ m/sles12/i ) {
                $result = `/usr/bin/scp -p $srciucvpath/iucvserd.service $dest:$trgtiucvservicepath_sl12 2>&1`;
            }
            elsif ( $os =~ m/rhel7/i){
                $result = `/usr/bin/scp -p $srciucvpath/iucvserd.service $dest:$trgtiucvservicepath_rh7 2>&1`;
            } elsif ( $os =~ m/ubuntu16/i){
                # Note: we should not encounter this line as we don't have ubuntu support before IUCV enablement
                $result = `/usr/bin/scp -p $srciucvpath/iucvserd.service $dest:$trgtiucvservicepath_ubuntu16 2>&1`;
            }
            $rc = $? >> 8;
            xCAT::zvmUtils->printSyslog("$node: /usr/bin/scp -p iucv service file return $rc $result");
            if ($rc != 0) {
                $msg = "Failed to copy iucvservice file. $result";
                return xCAT::zvmUtils->setsshforvm($user, $node, $os, $commandwithparm, $msg, $status, $callback);
            }
            $opnclouduserid = xCAT::zvmCPUtils->getUserId($user, $hcp);
            $opnclouduserid =~ tr/a-z/A-Z/;
            if ($rc !=0) {
                $msg = "failed to get OPNCLOUD userid. return $? \n$result";
                return xCAT::zvmUtils->setsshforvm($user, $node, $os, $commandwithparm, $msg, $status, $callback);
            }

            $cmd = "ssh -o ConnectTimeout=5 $user\@$node \"echo -n $opnclouduserid >$authorizedfilepath\" 2>&1";
            $result = `ssh -o ConnectTimeout=5 $user\@$node "echo -n $opnclouduserid >$authorizedfilepath" 2>&1`;
            ($rc, $outmsg) = xCAT::zvmUtils->checkSSHOutput( $?, "$cmd" );
            if ($rc != 0) {
                if ($isCallback){
                    xCAT::zvmUtils->printLn( $callback, "$node: $outmsg");
                }
                $msg = "echo -n $hcp >$authorizedfilepath, failed to create authorized userid for $node. return $rc $result";
                return xCAT::zvmUtils->setsshforvm($user, $node, $os, $commandwithparm, $msg, $status, $callback);
            }

            # Start service of IUCV server
            if ( $os =~ m/sles11/i or $os =~ m/rhel6/i ){
                $cmd = "ssh -o ConnectTimeout=5 $user\@$node \"chkconfig --add iucvserd && service iucvserd start 2>&1\"";
                $result = `ssh -o ConnectTimeout=5 $user\@$node "chkconfig --add iucvserd && service iucvserd start 2>&1"`;
                ($rc, $outmsg) = xCAT::zvmUtils->checkSSHOutput( $?, "$cmd" );
                if ($rc != 0) {
                    if ($isCallback){
                        xCAT::zvmUtils->printLn( $callback, "$node: $outmsg");
                    }
                    $msg = "echo -n $hcp >$authorizedfilepath, failed to create authorized userid for $node. return $rc $result";
                    return xCAT::zvmUtils->setsshforvm($user, $node, $os, $commandwithparm, $msg, $status, $callback);
                }
            }else{
                $cmd = "ssh -o ConnectTimeout=5 $user\@$node \"systemctl enable iucvserd.service && systemctl start iucvserd.service 2>&1\"";
                $result = `ssh -o ConnectTimeout=5 $user\@$node "systemctl enable iucvserd.service && systemctl start iucvserd.service 2>&1"`;
                ($rc, $outmsg) = xCAT::zvmUtils->checkSSHOutput( $?, "$cmd" );
                if ($rc != 0) {
                    if ($isCallback){
                        xCAT::zvmUtils->printLn( $callback, "$node: $outmsg");
                    }
                    $msg = "echo -n $hcp >$authorizedfilepath, failed to create authorized userid for $node. return $rc $result";
                    return xCAT::zvmUtils->setsshforvm($user, $node, $os, $commandwithparm, $msg, $status, $callback);
                }
            }
            $rc = $? >> 8;
            xCAT::zvmUtils->printSyslog("$node: start iucvserver service return $rc. $result");
            if ($rc == 0) {
                $result = xCAT::zvmUtils->execcmdthroughIUCV($user, $hcp, $userid, $commandwithparm, $callback);
                if ($? == 0){
                    xCAT::zvmUtils->printSyslog("$node: successfully initialized IUCV, Set IUCV=1 for $user");
                    if ($callback){
                        xCAT::zvmUtils->printLn( $callback, "$node: successfully initialized IUCV, Set IUCV=1 for $user");
                    }
                    if ($status){
                        $status = "$status;IUCV=1";
                    }else{
                        $status = "IUCV=1";
                    }
                    xCAT::zvmUtils->setNodeProp( 'zvm', $node, 'status', $status );
                    return $result;
                }else{
                    $msg = "$node: Failed to start iucvserver, result is $result";
                    return xCAT::zvmUtils->setsshforvm($user, $node, $os, $commandwithparm, $msg, $status, $callback);
                }
            } else {
                $msg = "$node: Failed to start iucvserver, result is $result";
                return xCAT::zvmUtils->setsshforvm($user, $node, $os, $commandwithparm, $msg, $status, $callback);
            }
        } else {
            $msg = "$node: IUCV server on VM doesn't start well, result is $result";
            return xCAT::zvmUtils->setsshforvm($user, $node, $os, $commandwithparm, $msg, $status, $callback);
        }
    } else {
        $msg = "IUCV has worked well, set IUCV=1 for $user .";
        if ($status) {
            $status = "$status;IUCV=1";
        } else {
            $status = "IUCV=1";
        }
        xCAT::zvmUtils->setNodeProp( 'zvm', $node, 'status', $status );
        return $result;
    }

}
