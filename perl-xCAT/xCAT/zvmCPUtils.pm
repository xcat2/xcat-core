# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
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

	Description	: Get userID for specified node
    Arguments	: Node name
    Returns		: UserID
    Example		: my $userID = xCAT::zvmCPUtils->getUserId($node);
    
=cut

#-------------------------------------------------------
sub getUserId {

	# Get inputs
	my ( $class, $node ) = @_;

	# Get userId using VMCP
	my $out = `ssh -o ConnectTimeout=5 $node "vmcp q userid"`;
	my @results = split( ' ', $out );
	return ( $results[0] );
}

#-------------------------------------------------------

=head3   getSn

	Description	: Get serial number for specified node
    Arguments	: Node name
    Returns		: Serial number
    Example		: my $sn = xCAT::zvmCPUtils->getSn($node);
    
=cut

#-------------------------------------------------------
sub getSn {

	# Get inputs
	my ( $class, $node ) = @_;

	# Get node properties from 'zvm' table
	my @propNames = ('hcp');
	my $propVals  = xCAT::zvmUtils->getNodeProps( 'zvm', $node, @propNames );

	# Get HCP
	my $hcp = $propVals->{'hcp'};

	# Look in /proc/sysinfo to get serial number
	my $out   = `ssh $hcp "cat /proc/sysinfo" | egrep -i "manufacturer|type|model|sequence code|plant"`;
	my @props = split( '\n', $out );
	my $man   = $props[0];
	my $type  = $props[1];
	my $model = $props[2];
	my $sn    = $props[3];
	my $plant = $props[4];

	# Trim and get property value
	# Get manufacturer
	@props = split( ':', $man );
	$man   = xCAT::zvmUtils->trimStr( $props[1] );

	# Get machine type
	@props = split( ':', $type );
	$type  = xCAT::zvmUtils->trimStr( $props[1] );

	# Get model
	@props = split( ': ', $model );
	$model = xCAT::zvmUtils->trimStr( $props[1] );
	@props = split( ' ', $model );
	$model = xCAT::zvmUtils->trimStr( $props[0] );

	# Get sequence number
	@props = split( ':', $sn );
	$sn    = xCAT::zvmUtils->trimStr( $props[1] );

	# Get plant
	@props = split( ':', $plant );
	$plant = xCAT::zvmUtils->trimStr( $props[1] );

	return ("$man-$type-$model-$plant-$sn");
}

#-------------------------------------------------------

=head3   getHost

	Description	: Get z/VM host for specified node
    Arguments	: Node name
    Returns		: z/VM host
    Example		: my $host = xCAT::zvmCPUtils->getHost($node);
    
=cut

#-------------------------------------------------------
sub getHost {

	# Get inputs
	my ( $class, $node ) = @_;

	# Get host using VMCP
	my $out     = `ssh -o ConnectTimeout=5 $node "vmcp q userid"`;
	my @results = split( ' ', $out );
	my $host    = $results[2];

	return ($host);
}

#-------------------------------------------------------

=head3   getOs

	Description	: Get operating system name of specified node
    Arguments	: Node name
    Returns		: Operating system name
    Example		: my $osName = xCAT::zvmCPUtils->getOs($node);
    
=cut

#-------------------------------------------------------
sub getOs {

	# Get inputs
	my ( $class, $node ) = @_;

	# Get operating system
	my $out = `ssh -o ConnectTimeout=10 $node "cat /etc/*release"`;
	my @results = split( '\n', $out );
	return ( xCAT::zvmUtils->trimStr( $results[0] ) );
}

#-------------------------------------------------------

=head3   getArch

	Description	: Get architecture of specified node
    Arguments	: Node name
    Returns		: Architecture of node
    Example		: my $arch = xCAT::zvmCPUtils->getArch($node);
    
=cut

#-------------------------------------------------------
sub getArch {

	# Get inputs
	my ( $class, $node ) = @_;

	# Get host using VMCP
	my $arch = `ssh $node "uname -p"`;

	return ( xCAT::zvmUtils->trimStr($arch) );
}

#-------------------------------------------------------

=head3   getPrivileges

	Description	: Get privilege class of specified node
    Arguments	: Node name
    Returns		: Privilege class
    Example		: my $memory = xCAT::zvmCPUtils->getPrivileges($node);
    
=cut

#-------------------------------------------------------
sub getPrivileges {

	# Get inputs
	my ( $class, $node ) = @_;

	# Get privilege class
	my $out = `ssh -o ConnectTimeout=5 $node "vmcp q priv"`;
	my @out = split( '\n', $out );
	$out[1] = xCAT::zvmUtils->trimStr( $out[1] );
	$out[2] = xCAT::zvmUtils->trimStr( $out[2] );
	my $str = "    $out[1]\n    $out[2]\n";
	return ($str);
}

#-------------------------------------------------------

=head3   getMemory

	Description	: Get memory of specified node
    Arguments	: Node name
    Returns		: Memory
    Example		: my $memory = xCAT::zvmCPUtils->getMemory($node);
    
=cut

#-------------------------------------------------------
sub getMemory {

	# Get inputs
	my ( $class, $node ) = @_;

	# Get memory
	my $out = `ssh -o ConnectTimeout=5 $node "vmcp q virtual storage"`;
	my @out = split( '=', $out );
	return ( xCAT::zvmUtils->trimStr( $out[1] ) );
}

#-------------------------------------------------------

=head3   getCpu

	Description	: Get processor of specified node
    Arguments	: Node name
    Returns		: Processor
    Example		: my $proc = xCAT::zvmCPUtils->getCpu($node);
    
=cut

#-------------------------------------------------------
sub getCpu {

	# Get inputs
	my ( $class, $node ) = @_;

	# Get processors
	my $out = `ssh -o ConnectTimeout=5 $node "vmcp q virtual cpus"`;
	my $str = xCAT::zvmUtils->tabStr($out);

	return ($str);
}

#-------------------------------------------------------

=head3   getNic

	Description	: Get network interface card (NIC) of specified node
    Arguments	: Node name
    Returns		: NIC
    Example		: my $nic = xCAT::zvmCPUtils->getNic($node);
    
=cut

#-------------------------------------------------------
sub getNic {

	# Get inputs
	my ( $class, $node ) = @_;

	# Get NIC
	my $out = `ssh -o ConnectTimeout=5 $node "vmcp q virtual nic"`;
	my $str = xCAT::zvmUtils->tabStr($out);
	return ($str);
}

#-------------------------------------------------------

=head3   getDisks

	Description	: Get disk of specified node
    Arguments	: Node name
    Returns		: Disk
    Example		: my $storage = xCAT::zvmCPUtils->getDisks($node);
    
=cut

#-------------------------------------------------------
sub getDisks {

	# Get inputs
	my ( $class, $node ) = @_;

	# Get disks
	my $out = `ssh -o ConnectTimeout=5 $node "vmcp q virtual dasd"`;
	my $str = xCAT::zvmUtils->tabStr($out);
	return ($str);
}

#-------------------------------------------------------

=head3   loadVmcp

	Description	: Load VMCP module on specified node
    Arguments	: Node name
    Returns		: Nothing
    Example		: my $out = xCAT::zvmCPUtils->loadVmcp($node);
    
=cut

#-------------------------------------------------------
sub loadVmcp {

	# Get inputs
	my ( $class, $node ) = @_;

	# Load Linux VMCP module
	my $out = `ssh -o ConnectTimeout=5 $node "modprobe vmcp"`;
	return;
}

#-------------------------------------------------------

=head3   getVswitchId

	Description	: Get VSwitch ID of specified node
    Arguments	: Node name
    Returns		: VSwitch IDs
    Example		: my @vswitch = xCAT::zvmCPUtils->getVswitchId($node);
    
=cut

#-------------------------------------------------------
sub getVswitchId {

	# Get inputs
	my ( $class, $node ) = @_;

	# Get VSwitch
	my $out = `ssh -o ConnectTimeout=5 $node "vmcp q nic" | grep "VSWITCH"`;
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

	Description	: Grant access to VSwitch for specified userID
    Arguments	: 	zHCP node
    				User ID 
    				Vswitch ID
    Returns		: Output string
    Example		: my $out = xCAT::zvmCPUtils->grantVswitch($callback, $hcp, $userId, $vswitchId);
    
=cut

#-------------------------------------------------------
sub grantVSwitch {

	# Get inputs
	my ( $class, $callback, $hcp, $userId, $vswitchId ) = @_;

	# Grant VSwitch for specified userID
	my $out = `ssh $hcp "vmcp set vswitch $vswitchId grant $userId"`;
	$out = xCAT::zvmUtils->trimStr($out);

	# If return string contains 'Command complete'
	my $retStr;
	if ( $out =~ m/Command complete/i ) {
		$retStr = "Done\n";
	}
	else {
		$retStr = "Failed\n";
		return ($retStr);
	}

	return ($retStr);
}

#-------------------------------------------------------

=head3   flashCopy

	Description	: Flash copy
    Arguments	: 	Node
    				Source address
    				Target address
    Returns		: Output string
    Example		: my $out = xCAT::zvmCPUtils->flashCopy($node, $srcAddr, $targetAddr);
    
=cut

#-------------------------------------------------------
sub flashCopy {

	# Get inputs
	my ( $class, $node, $srcAddr, $targetAddr ) = @_;

	# Flash copy
	my $out = `ssh $node "vmcp flashcopy $srcAddr 0 end to $targetAddr 0 end"`;
	$out = xCAT::zvmUtils->trimStr($out);

	# If return string contains 'Command complete'
	my $retStr;
	if ( $out =~ m/Command complete/i ) {

		# Done
		$retStr = "Done\n";
	}
	else {
		$retStr = "Failed\n";
		return ($retStr);
	}

	return ($retStr);
}

#-------------------------------------------------------

=head3   punch2Reader

	Description	: 	Write file to z/VM punch and transfer it to reader
    Arguments	: 	HCP node
    				UserID to receive file
    				File to transfer
    				File name and type to be created by punch (e.g. sles.parm)
    				Options (e.g. -t -- Convert EBCDIC to ASCII)
    Returns		: 	Nothing
    Example		: my $rc = xCAT::zvmCPUtils->punch2Reader($hcp, $userId, $file, $fileName, $options);
    
=cut

#-------------------------------------------------------
sub punch2Reader {
	my ( $class, $hcp, $userId, $file, $fileName, $options ) = @_;

	# Punch to reader
	my $out = `ssh -o ConnectTimeout=5 $hcp "vmur punch $options -u $userId  -r $file -N $fileName"`;

	return $out;
}

#-------------------------------------------------------

=head3   purgeReader

	Description	: 	Purge reader (Class D users only)
    Arguments	: 	HCP node
    				UserID to purge reader for
    Returns		: 	Nothing
    Example		: my $rc = xCAT::zvmCPUtils->purgeReader($hcp, $userId);
    
=cut

#-------------------------------------------------------
sub purgeReader {
	my ( $class, $hcp, $userId ) = @_;

	# Punch to reader
	my $out = `ssh -o ConnectTimeout=5 $hcp "vmcp purge $userId rdr all"`;

	return;
}

#-------------------------------------------------------

=head3   sendCPCmd

	Description	: 	Send CP command to given userID (Class C users only)
    Arguments	: 	HCP node
    				UserID to send CP command
    Returns		: 	Nothing
    Example		: my $rc = xCAT::zvmCPUtils->sendCPCmd($hcp, $userId, $cmd);
    
=cut

#-------------------------------------------------------
sub sendCPCmd {
	my ( $class, $hcp, $userId, $cmd ) = @_;

	# Send CP command to given userID
	my $out = `ssh $hcp "vmcp send cp $userId $cmd"`;

	return;
}
