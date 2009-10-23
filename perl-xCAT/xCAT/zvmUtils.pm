# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head1

	This is a utility plugin for the z/VM.

=cut

#-------------------------------------------------------
package xCAT::zvmUtils;
use xCAT::MsgUtils;
use xCAT::Utils;
use xCAT::Table;
use strict;
use warnings;
1;

#-------------------------------------------------------

=head3   getTabProp
	Description	: Get node property from specified table
    Arguments	: 	Table
    				Node
    				Property
    Returns		: Property from specifed table
    Example		: my $prop = xCAT::zvmUtils->getTabProp($tabName, $node, $propName);
    
=cut

#-------------------------------------------------------
sub getTabProp {

	# Get inputs
	my ( $class, $tabName, $node, $propName ) = @_;

	# Get specified table
	my $tab = xCAT::Table->new($tabName);

	# Get value from column
	my $entry = $tab->getNodeAttribs( $node, [$propName] );
	my $propVal = $entry->{$propName};
	return ($propVal);
}

#-------------------------------------------------------

=head3   setTabProp

	Description	: Set node property from specified table
    Arguments	: 	Table
    				Node
    				Property
    Returns		: Nothing
    Example		: xCAT::zvmUtils->setTabProp($tabName, $node, $propName, $propVal);
    
=cut

#-------------------------------------------------------
sub setTabProp {

	# Get inputs
	my ( $class, $tabName, $node, $propName, $propVal ) = @_;

	# Get specified table
	my $tab = xCAT::Table->new( $tabName, -create => 1, -autocommit => 0 );

	# Set property
	$tab->setAttribs( { 'node' => $node }, { $propName => $propVal } );

	# Save table
	$tab->commit;

	return;
}

#-------------------------------------------------------

=head3   delTabNode

	Description	: Delete node from specified table
    Arguments	: 	Table
    				Node 
    Returns		: Nothing
    Example		: xCAT::zvmUtils->delTabNode($tabName, $node);
    
=cut

#-------------------------------------------------------
sub delTabNode {

	# Get inputs
	my ( $class, $tabName, $node ) = @_;

	# Get specified table
	my $tab = xCAT::Table->new( $tabName, -create => 1, -autocommit => 0 );

	# Delete node from table
	my %key = ( 'node' => $node );
	$tab->delEntries( \%key );

	# Save table
	$tab->commit;

	return;
}

#-------------------------------------------------------

=head3   tabStr

	Description	: Tab string 4 spaces
    Arguments	: String
    Returns		: Tabbed string
    Example		: my $str = xCAT::zvmUtils->tabStr($str);
    
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

=head3   trim

	Description	: Trim whitespaces in string
    Arguments	: String
    Returns		: Trimmed string
    Example		: my $str = xCAT::zvmUtils->trim($str);
    
=cut

#-------------------------------------------------------
sub trim {

	# Get string
	my ( $class, $str ) = @_;

	# Trim right
	$str =~ s/\s*$//;

	# Trim left
	$str =~ s/^\s*//;

	return ($str);
}

#-------------------------------------------------------

=head3   printLn

	Description	: Print string
    Arguments	: String
    Returns		: Nothing
    Example		: xCAT::zvmUtils->printLn($callback, $str);
    
=cut

#-------------------------------------------------------
sub printLn {

	# Get inputs
	my ( $class, $callback, $str ) = @_;

	# Print string
	my $rsp;
	$rsp->{data}->[0] = "$str";
	xCAT::MsgUtils->message( "I", $rsp, $callback );

	return;
}

#-------------------------------------------------------

=head3   isZvmNode

	Description	: Determine if specified node is in 'zvm' table
    Arguments	: Node
    Returns		: 	TRUE	Node exists
    				FALSE	Node does not exists
    Example		: my $out = xCAT::zvmUtils->isZvmNode($node);
    
=cut

#-------------------------------------------------------
sub isZvmNode {

	# Get inputs
	my ( $class, $node ) = @_;

	# zVM guest ID
	my $id;

	# Look in 'zvm' table
	my $tab = xCAT::Table->new( 'zvm', -create => 1, -autocommit => 0 );

	my @results = $tab->getAllAttribsWhere( "node like '%" . $node . "%'", 'userid' );
	foreach (@results) {
		$id = $_->{'userid'};

		# Get userID if one is not in the table
		if ($id) {
			return ('TRUE');
		}
	}

	return ('FALSE');
}

#-------------------------------------------------------

=head3   getIp

	Description	: Get IP address of specified node
    Arguments	: Node
    Returns		: IP address
    Example		: my $ip = xCAT::zvmUtils->getIp($node);
    
=cut

#-------------------------------------------------------
sub getIp {

	# Get inputs
	my ( $class, $node ) = @_;

	# Get IP address
	my $out   = `ssh $node ifconfig | grep 'inet addr:'| grep -v '127.0.0.1' | cut -d: -f2`;
	my @parms = split( ' ', $out );

	return ( $parms[0] );
}

#-------------------------------------------------------

=head3   getIfcfg

	Description	: Get /etc/sysconfig/network/ifcfg-qeth file name for specified node
    Arguments	: Node
    Returns		: /etc/sysconfig/network/ifcfg-qeth file name
    Example		: my $ifcfg = xCAT::zvmUtils->getIfcfg($node);
    
=cut

#-------------------------------------------------------
sub getIfcfg {

	# Get inputs
	my ( $class, $node ) = @_;

	# Get /etc/sysconfig/network/ifcfg-qeth file name
	my $out   = `ssh $node ls /etc/sysconfig/network/ifcfg-qeth*`;
	my @parms = split( '\n', $out );

	return ( $parms[0] );
}

#-------------------------------------------------------

=head3   getBroadcastIP

	Description	: Get IP broadcast of specified node
    Arguments	: Node
    Returns		: IP broadcast
    Example		: my $broadcast = xCAT::zvmUtils->getBroadcastIP($node);
    
=cut

#-------------------------------------------------------
sub getBroadcastIP {

	# Get inputs
	my ( $class, $node ) = @_;

	# Get IP address
	my $out   = `ssh $node ifconfig | grep 'Bcast:'| cut -d: -f3`;
	my @parms = split( ' ', $out );

	return ( $parms[0] );
}

#-------------------------------------------------------

=head3   getDns

	Description	: Get DNS server of specified node
    Arguments	: Node
    Returns		: DNS server
    Example		: my $dns = xCAT::zvmUtils->getDns($node);
    
=cut

#-------------------------------------------------------
sub getDns {

	# Get inputs
	my ( $class, $node ) = @_;

	# Get IP address
	my $out   = `ssh $node cat /etc/resolv.conf | grep 'nameserver'`;
	my @parms = split( ' ', $out );

	return ( $parms[1] );
}

#-------------------------------------------------------

=head3   getGateway

	Description	: Get default gateway of specified node
    Arguments	: Node
    Returns		: Default gateway
    Example		: my $gw = xCAT::zvmUtils->getGateway($node);
    
=cut

#-------------------------------------------------------
sub getGateway {

	# Get inputs
	my ( $class, $node ) = @_;

	# Get IP address
	my $out = `ssh $node cat /etc/sysconfig/network/routes`;
	my @parms = split( ' ', $out );
	return ( $parms[1] );
}

#-------------------------------------------------------

=head3   sendFile

	Description	: SCP file to specified node
    Arguments	: 	Node 
    				File
    Returns		: Nothing
    Example		: my $out = xCAT::zvmUtils->sendFile($node, $file);
    
=cut

#-------------------------------------------------------
sub sendFile {

	# Get inputs
	my ( $class, $node, $file ) = @_;

	# Create destination string
	my $dest = "root@";
	$dest .= $node;

	# SCP directory entry file over to HCP
	my $out = `scp $file $dest:$file`;

	return;
}

#-------------------------------------------------------

=head3   getRootDiskAddr

	Description	: Get root disk address
    Arguments	: 	Node name
    Returns		: 	Root disk address
    Example		: my $deviceNode = xCAT::zvmUtils->getRootDiskAddr($node);
    
=cut

#-------------------------------------------------------
sub getRootDiskAddr {

	# Get inputs
	my ( $class, $node ) = @_;

	# Get device node mounted on (/)
	my $out = `ssh $node  mount | grep "/ type" | sed 's/1//'`;
	my @parms = split( " ", $out );
	@parms = split( "/", xCAT::zvmUtils->trim( $parms[0] ) );
	my $devNode = $parms[0];

	# Get minidisk address
	$out = `ssh $node cat /proc/dasd/devices | grep "$devNode" | sed 's/(ECKD)//'| sed 's/(FBA )//' | sed 's/0.0.//'`;
	@parms = split( " ", $out );

	return ( $parms[0] );
}

#-------------------------------------------------------

=head3   disableEnableDisk

	Description	: Disable or enable disk for specified node
    Arguments	: 	Device address
    				Option [-d | -e]
    Returns		: Nothing
    Example		: my $out = xCAT::zvmUtils->disableEnableDisk($callback, $node, $option, $devAddr);
    
=cut

#-------------------------------------------------------
sub disableEnableDisk {

	# Get inputs
	my ( $class, $callback, $node, $option, $devAddr ) = @_;

	# --- Disable or enable disk ---
	if ( $option eq "-d" || $option eq "-e" ) {
		my $out = `ssh $node chccwdev $option $devAddr`;
	}

	return;
}

#-------------------------------------------------------

=head3   getMdisks

	Description	: Get MDisk statements in user directory entry
    Arguments	: Node
    Returns		: MDisk statements
    Example		: my @mdisks = xCAT::zvmUtils->getMdisks($callback, $node);
    
=cut

#-------------------------------------------------------
sub getMdisks {

	# Get inputs
	my ( $class, $callback, $node ) = @_;

	# Directory where executables are
	my $dir = '/opt/zhcp/bin';

	# Get HCP
	my $hcp = xCAT::zvmUtils->getTabProp( 'zvm', $node, 'hcp' );
	if ( !$hcp ) {
		xCAT::zvmUtils->printLn( $callback, "Error: No HCP defined for this node" );
		return;
	}

	# Get node userID
	my $userId = xCAT::zvmUtils->getTabProp( 'zvm', $node, 'userid' );
	if ( !$userId ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing node ID" );
		return;
	}

	my $out = `ssh $hcp $dir/getuserentry $userId`;

	# Get MDISK statements
	my @lines = split( '\n', $out );
	my @disks;
	foreach (@lines) {
		$_ = xCAT::zvmUtils->trim($_);

		if ( $_ =~ m/MDISK/i ) {

			# Save MDISK statements
			push( @disks, $_ );
		}
	}
	return (@disks);
}

#-------------------------------------------------------

=head3   readConfigFile

	Description	: Read in configuration file
    Arguments	: 	Node
    				Configuration file
    Returns		: 	Hash arrary containing node configuration
    Example		: my %nodeConfig = xCAT::zvmUtils->readConfigFile($callback, $node, $file);
    
=cut

#-------------------------------------------------------
sub readConfigFile {

	# Get inputs
	my ( $class, $callback, $node, $file ) = @_;

	# Hash array containing new node configuration
	my %target;

	# Get configuration file
	if ( !$file ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing configuration file" );
		return;
	}
	else {

		# Open configuration file
		open( CONFIG, $file ) || die("Error: Could not open file");
		my @configFile = <CONFIG>;
		close(CONFIG);

		# Read configuration file
		my @parms;
		my $pattern = $node . ":";
		my $save    = 0;
		foreach (@configFile) {
			$_ = xCAT::zvmUtils->trim($_);

			# If the line contains specified node
			if ( $_ =~ m/$pattern/i ) {

				# Save configuration
				$save = 1;

				# Find ':' and replace with ''
				$_ =~ s/://g;
				$target{"Hostname"} = $_;
			}

			# Stop saving at next line containing ':'
			if ( $save == 1 && $_ =~ m/:/i ) {
				$save = 0;
			}

			# Save configuration
			if ( $save == 1 ) {

				# Create hash array
				@parms = split( "=", $_ );
				$target{"$parms[0]"} = "$parms[1]";
			}

		}    # End of foreach
	}    # End of else

	# If there is not a new node configuration
	if ( !$target{"Hostname"} ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Node configuration not found" );
		return;
	}

	return %target;
}

#-------------------------------------------------------

=head3   saveDirEntryNoDisk

	Description	: 	Get user directory entry for specified node,
					remove the MDISK statments, and save it to a file
    Arguments	: 	Node name
    				File name
    Returns		: 	Nothing
    Example		: my $out = xCAT::zvmUtils->saveDirEntryNoDisk($callback, $node, $file);
    
=cut

#-------------------------------------------------------
sub saveDirEntryNoDisk {

	# Get inputs
	my ( $class, $callback, $node, $file ) = @_;

	# Directory where executables are
	my $dir = '/opt/zhcp/bin';

	# Get HCP
	my $hcp = xCAT::zvmUtils->getTabProp( 'zvm', $node, 'hcp' );
	if ( !$hcp ) {
		xCAT::zvmUtils->printLn( $callback, "Error: No HCP defined for this node" );
		return;
	}

	# Get node userID
	my $userId = xCAT::zvmUtils->getTabProp( 'zvm', $node, 'userid' );
	if ( !$userId ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing node ID" );
		return;
	}

	my $out = `ssh $hcp $dir/getuserentry $userId`;

	# Create a file to save output
	open( DIRENTRY, ">$file" );

	# Remove MDISK statement
	my @lines = split( '\n', $out );
	foreach (@lines) {

		# Trim line
		$_ = xCAT::zvmUtils->trim($_);

		if ( $_ =~ m/MDISK/i ) {

			# Do nothing
		}
		else {

			# Write directory entry into file
			print DIRENTRY "$_\n";
		}
	}
	close(DIRENTRY);

	return;
}

#-------------------------------------------------------

=head3   appendHostname

	Description	: 	Append specified hostname in front of every line
    Arguments	: 	Hostname
    				String
    Returns		: 	String with hostname in front
    Example		: my $str = xCAT::zvmUtils->appendHostname($hostname, $str);
    
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

=head3   isOutputGood

	Description	: 	Check output
    Arguments	: 	Output string
    Returns		: 	0	Good output
    				-1	Bad output
    Example		: my $ans = xCAT::zvmUtils->isOutputGood($callback, $out);
    
=cut

#-------------------------------------------------------
sub isOutputGood {
	my ( $class, $callback, $out ) = @_;

	# Check output string
	my @outLn = split( "\n", $out );
	foreach (@outLn) {

		# If output contains 'Failed' return -1
		if ( $_ =~ m/Failed/i ) {
			return -1;
		}
	}

	return 0;
}

#-------------------------------------------------------

=head3   isAddressUsed

	Description	: 	Check if specified address is used
    Arguments	: 	Node
    				Disk address
    Returns		: 	0	Address used
    				-1	Address not used
    Example		: my $ans = xCAT::zvmUtils->isAddressUsed($node, $address);
    
=cut

#-------------------------------------------------------
sub isAddressUsed {
	my ( $class, $node, $address ) = @_;

	# Search for disk address
	my $out = `ssh -o ConnectTimeout=5 $node vmcp q v dasd | grep "DASD $address"`;
	if ($out) {
		return 0;
	}

	return -1;
}
