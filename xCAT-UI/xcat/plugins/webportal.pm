# IBM(c) 2011 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head 1

    xCAT plugin to handle xCAT UI service portal commands

=cut

#-------------------------------------------------------

package xCAT_plugin::webportal;
use strict;
require xCAT::Utils;
require xCAT::MsgUtils;
require xCAT::DBobjUtils;
require IO::Socket::INET;
use Getopt::Long;
use Data::Dumper;
use xCAT::Table;
use xCAT::NodeRange;
use XML::Simple;
require XML::Parser;

sub handled_commands {

# In order for this to work, you need to run: ln -s /opt/xcat/bin/xcatclientnnr /opt/xcat/bin/webportal
# xcatclientnnr allows command to run without a node range
	return { webportal => "webportal" };
}

sub process_request {
	my $request         = shift;
	my $callback        = shift;
	my $sub_req         = shift;
	my %authorized_cmds = (
		'lszvm'       => \&lszvm,
		'provzlinux'  => \&provzlinux,
		'clonezlinux' => \&clonezlinux
	);

	# Check if the request is authorized
	split ' ', $request->{arg}->[0];
	my $cmd = $_[0];
	if ( grep { $_ eq $cmd } keys %authorized_cmds ) {
		my $func = $authorized_cmds{$cmd};
		$func->( $request, $callback, $sub_req );
	}
	else {
		$callback->(
			{ error => "$cmd is not authorized!\n", errorcode => [1] } );
	}
}

sub println {
	my $callback = shift;
	my $msg      = shift;
	my %rsp;
	push @{ $rsp{info} }, $msg;
	xCAT::MsgUtils->message( 'I', \%rsp, $callback );
	return;
}

sub lszvm {
	my ( $request, $callback, $sub_req ) = @_;

	# List the zVM and their respective HCP
	my $out = "";
	my %pair;

	# Look in 'zvm' table
	my $tab = xCAT::Table->new( 'zvm', -create => 1, -autocommit => 0 );
	my @results = $tab->getAllAttribsWhere( "nodetype='vm'", 'hcp', 'parent' );
	foreach (@results) {
		if ( $_->{'hcp'} && $_->{'parent'} && !$pair{ $_->{'hcp'} } ) {

			# Save zVM:HCP pairing
			$pair{ $_->{'hcp'} } = $_->{'parent'};

			# Print out zVM:HCP
			$out .= $_->{'parent'} . ":" . $_->{'hcp'} . "\n";
		}
	}

	$callback->( { data => $out } );
}

sub provzlinux {
	my ( $request, $callback, $sub_req ) = @_;

	my $group = $request->{arg}->[1];
	my $hcp   = $request->{arg}->[2];
	my $img   = $request->{arg}->[3];
	my $owner = $request->{arg}->[4];

	# Read in default disk pool and disk size /opt/zhcp/conf/default.conf on zHCP
	#	pool = POOL3
	#	eckd_size = 10016
	my $disk_pool;
	my $eckd_size;
	my $fba_size;
	my $default_conf   = '/opt/zhcp/conf/default.conf';
	my $default_direct = "/opt/zhcp/conf/$group.direct";

	# Check if a group based directory entry exists, else use default one
	if ( !(`ssh $hcp "test -e /opt/zhcp/conf/$group.direct && echo Exists"`) ) {
		$default_direct = '/opt/zhcp/conf/default.direct';
		println( $callback, "$group.direct does not exist.  Using default.direct to generate directory entry." );
		
		# Exit if default.direct does not exist
		if ( !(`ssh $hcp "test -e /opt/zhcp/conf/default.direct && echo Exists"`) ) {
			println( $callback, '(Error) $default_direct does not exists' );
			return;
		}
	}

	# Exit if default.conf does not exist
	if ( !(`ssh $hcp "test -e $default_conf && echo Exists"`) ) {
		println( $callback, '(Error) $default_conf does not exists' );
		return;
	}

	# Exit if default.direct does not exist
	if ( !(`ssh $hcp "test -e $default_direct && echo Exists"`) ) {
		println( $callback, '(Error) $default_direct does not exists' );
		return;
	}

	my $out = `ssh $hcp "cat $default_conf"`;
	my @tmp = split( /\n/, $out );
	foreach (@tmp) {
		# Get disk pool
		if ( $_ =~ m/pool =/i ) {
			$disk_pool = $_;
			$disk_pool =~ s/pool =//g;
		}

		# Get disk size
		elsif ( $_ =~ m/eckd_size =/i ) {
			$eckd_size = $_;
			$eckd_size =~ s/eckd_size =//g;
		}
		elsif ( $_ =~ m/fba_size = /i ) {
			$fba_size = $_;
			$fba_size =~ s/fba_size = //g;
		}
	}

	# Get node OS base
	my $profile;
	my $arch;
	my $os;
	( $profile, $arch, $os ) = getosimagedef( $callback, $img );
	if ( $os =~ m/sp/i ) {
		@tmp = split( /sp/, $os );
	}
	else {
		@tmp = split( /\./, $os );
	}
	my $os_base = $tmp[0];

	my $site_tab    = xCAT::Table->new('site');
	my $hash        = $site_tab->getAttribs( { key => "installdir" }, 'value' );
	my $install_dir = $hash->{'value'};

	# Get autoyast/kickstart template
	# Count the number of disks needed
	my $tmpl;
	if ( $os =~ m/sles/i ) {
		$tmpl = "$install_dir/custom/install/sles/$profile.$os_base.$arch.tmpl";
	} elsif ( $os =~ m/rhel/i ) {
		$tmpl = "$install_dir/custom/install/rh/$profile.$os_base.$arch.tmpl";
	}

	# Create VM
	# e.g. webportal provzlinux [group] [hcp] [image]
	my ($node, $base_digit) = gennodename( $callback, $group );
	my $userid = 'XCAT' . $base_digit;

	# Set node definitions
	$out = `mkdef -t node -o $node userid=$userid hcp=$hcp mgt=zvm groups=$group`;
	println( $callback, "$out" );

	# Set nodetype definitions
	$out = `chtab node=$node noderes.netboot=zvm nodetype.nodetype=osi nodetype.provmethod=install nodetype.os=$os nodetype.arch=$arch nodetype.profile=$profile nodetype.comments="owner:$owner"`;

	# Update hosts table and DNS
	`makehosts`;
	`makedns`;

	# Create user directory entry replacing LXUSR with user ID
	# Use /opt/zhcp/conf/default.direct on zHCP as the template
	#	USER LXUSR PSWD 512M 1G G
	#	INCLUDE LNXDFLT
	#	COMMAND SET VSWITCH VSW2 GRANT LXUSR
	$out = `ssh $hcp "sed $default_direct -e s/LXUSR/$userid/g" > /tmp/$node-direct.txt`;
	$out = `mkvm $node /tmp/$node-direct.txt`;
	`rm -rf /tmp/$node-direct.txt`;
	println( $callback, "$out" );
	if ( $out =~ m/Error/i ) {
		return;
	}

	# Add MDISKs to user directory entry
	# Use /opt/zhcp/conf/default.conf on zHCP to determine disk pool and disk size
	#	pool = POOL3
	#	eckd_size = 10016

	my $type;
	my $virt_addr;
	if ( $os =~ m/sles/i ) {
		# Create XML object
		my $xml = new XML::Simple;
	
		# Read XML file
		my $data = $xml->XMLin($tmpl);
		
		my $devices = $data->{'dasd'}->{'devices'}->{'listentry'};
		foreach (@$devices) {
	
			# Get disk virtual address and disk type
			$type = $_->{'drivers'}->{'listentry'}->{'modules'}->{'module_entry'}->{'listentry'};
			$virt_addr = $_->{'sysfs_bus_id'};
			$virt_addr =~ s/0\.0\.//g;
			foreach (@$type) {
				# Add ECKD disk
				if ( $_ =~ m/dasd_eckd_mod/i ) {
					$out = `chvm $node --add3390 $disk_pool $virt_addr $eckd_size MR`;
					println( $callback, "$out" );
					if ( $out =~ m/Error/i ) {
						return;
					}
				}
	
				# Add FBA disk
				elsif ( $_ =~ m/dasd_fba_mod/i ) {
					# To be continued
					# $out = `chvm $node --add9336 $disk_pool $virt_addr $fba_size MR`;
				}
			}
		}    # End of foreach
	} elsif ( $os =~ m/rhel/i ) {
		my %devices;
		my $dev;
		$virt_addr = 100;
		
		# Read in kickstart file
		$out = `cat $tmpl | egrep "part /"`;
		@tmp = split( /\n/, $out );
		foreach (@tmp) {
			$out = substr( $out, index( $out, '--ondisk=' )+9 );	
			$out =~ s/\s*$//;	# Trim right
			$out =~ s/^\s*//;	# Trim left
			$devices{$out} = 1;
		}
		
		# Add ECKD disk for each device found
		for $dev ( keys %devices ) {
			$out = `chvm $node --add3390 $disk_pool $virt_addr $eckd_size MR`;
			println( $callback, "$out" );
			if ( $out =~ m/Error/i ) {
				return;
			}
			
			# Increment virtual address
			$virt_addr = $virt_addr + 1;
		}
	}

	# Update DHCP
	`makedhcp -a`;

	# Toggle node power so COMMAND SET will get executed
	`rpower $node on`;
	`rpower $node off`;

	# Punch kernel, initrd, and ramdisk to node reader
	$out = `nodeset $node install`;
	println( $callback, "$out" );
	if ( $out =~ m/Error/i ) {
		return;
	}

	# IPL reader and begin installation
	$out = `rnetboot $node ipl=00C`;
	println( $callback, "$out" );
	if ( $out =~ m/Error/i ) {
		return;
	}
	
	# Configure Ganglia monitoring
	$out = `moncfg gangliamon $node -r`;
	
	# Show node information, e.g. IP, hostname, and root password
	$out = `lsdef $node | egrep "ip=|hostnames="`;
	my $rootpw = getsysrootpw();
	println( $callback, "Your virtual machine is ready. It may take a few minutes before you can logon using VNC ($node:1). Below is your VM attributes." );
	println( $callback, "$out" );
	println( $callback, "    rootpw = $rootpw" );
}

sub getsysrootpw {
	# Get the default root password for all xCAT provisioned VM
	my ( $callback ) = @_;
	
	my $tab    = xCAT::Table->new('passwd');
	my $hash   = $tab->getAttribs( { key => "system" }, 'password' );
	my $passwd = $hash->{'password'};
	
	return $passwd;
}

sub getosimagedef {

	# Get osimage definitions based on image name
	my ( $callback, $img_name ) = @_;

	my $profile;
	my $arch;
	my $os;

	# Get profile, osarch, and osver in 'osimage' table based on imagename
	my $tab = xCAT::Table->new( 'osimage', -create => 1, -autocommit => 0 );
	my @results = $tab->getAllAttribsWhere( "imagename='" . $img_name . "'",
		'profile', 'osarch', 'osvers' );
	foreach (@results) {

		# It should return: |gpok(\d+)|10.1.100.($1+0)|
		$profile = $_->{'profile'};
		$arch    = $_->{'osarch'};
		$os      = $_->{'osvers'};
	}

	return ( $profile, $arch, $os );
}

sub gennodename {

	# Generate node name based on given group
	my ( $callback, $group ) = @_;

	my $base_digit = 0;
	my $base_hostname;
	my $hostname;
	my @args;

	# Get regular expression for hostname in 'hosts' table
	my $tab = xCAT::Table->new( 'hosts', -create => 1, -autocommit => 0 );
	my @results = $tab->getAllAttribsWhere( "node='" . $group . "'", 'ip' );
	foreach (@results) {

		# It should return: |gpok(\d+)|10.1.100.($1+0)|
		@args = split( /\|/, $_->{'ip'} );
		$base_hostname = $args[1];
	}

	# Are there nodes in this group already?
	my $out = `nodels $group`;
	@args = split( /\n/, $out );
	foreach (@args) {
		$_ =~ s/$base_hostname/$1/g;

		# Take the greatest digit
		if ( int($_) > $base_digit ) {
			$base_digit = int($_);
		}
	}

	# +1 to base digit to obtain next hostname
	$base_digit = $base_digit + 1;
	
	# Generate hostname
	$hostname = $base_hostname;
	$base_hostname =  substr( $hostname, 0, index( $hostname, '(\d+)' ) );
	$hostname = substr( $hostname, 0, index( $hostname, '(\d+)' ) ) . $base_digit;
	 
	# Check if hostname is already used
	while (`nodels $hostname`) {		
		# +1 to base digit to obtain next hostname
		$base_digit = $base_digit + 1;
		$hostname = $base_hostname . $base_digit;
	}
	 
	return ($hostname, $base_digit);
}

sub clonezlinux {
	my ( $request, $callback, $sub_req ) = @_;

	# webportal clonezlinux [src node] [group] [owner]
	my $src_node = $request->{arg}->[1];
	my $group = $request->{arg}->[2];
	my $owner = $request->{arg}->[3];
	
	# Get source node's HCP
	my $props = xCAT::zvmUtils->getNodeProps( 'zvm', $src_node, ('hcp') );
	my $hcp = $props->{'hcp'};
	
	# Get source node's nodetype
	$props = xCAT::zvmUtils->getNodeProps( 'nodetype', $src_node, ('os', 'arch', 'profile') );
	my $os = $props->{'os'};
	my $arch = $props->{'arch'};
	my $profile = $props->{'profile'};

	# Read in default disk pool from /opt/zhcp/conf/default.conf on zHCP
	#	pool = POOL3
	#	eckd_size = 10016
	my $disk_pool;
	my $default_conf   = '/opt/zhcp/conf/default.conf';
	my $default_direct = '/opt/zhcp/conf/default.direct';

	# Exit if default.conf does not exist
	if ( !(`ssh $hcp "test -e $default_conf && echo Exists"`) ) {
		println( $callback, '(Error) $default_conf does not exists' );
		return;
	}

	# Exit if default.direct does not exist
	if ( !(`ssh $hcp "test -e $default_direct && echo Exists"`) ) {
		println( $callback, '(Error) $default_direct does not exists' );
		return;
	}

	my $out = `ssh $hcp "cat $default_conf"`;
	my @tmp = split( /\n/, $out );
	foreach (@tmp) {
		# Get disk pool
		if ( $_ =~ m/pool =/i ) {
			$disk_pool = $_;
			$disk_pool =~ s/pool =//g;
			$disk_pool =~ s/\s*$//;	# Trim right
			$disk_pool =~ s/^\s*//;	# Trim left
		}
	}
		
	# Create VM
	# e.g. webportal provzlinux [group] [hcp] [image]
	my ($node, $base_digit) = gennodename( $callback, $group );
	my $userid = 'XCAT' . $base_digit;
	
	# Set node definitions
	$out = `mkdef -t node -o $node userid=$userid hcp=$hcp mgt=zvm groups=$group`;
	println( $callback, "$out" );

	# Set nodetype definitions
	$out = `chtab node=$node noderes.netboot=zvm nodetype.nodetype=osi nodetype.provmethod=install nodetype.os=$os nodetype.arch=$arch nodetype.profile=$profile nodetype.comments="owner:$owner"`;

	# Update hosts table and DNS
	`makehosts`;
	`makedns`;

	# Update DHCP
	`makedhcp -a`;
	println( $callback, "hosts table, DHCP, and DNS updated" );

	# Clone virtual machine	
	$out = `mkvm $node $src_node pool=$disk_pool`;
	println( $callback, "$out" );
	if ( $out =~ m/Error/i || $out =~ m/Failed/i ) {
		return;
	}
	
	# Configure Ganglia monitoring
	$out = `moncfg gangliamon $node -r`;
	
	# Show node information, e.g. IP, hostname, and root password
	$out = `lsdef $node | egrep "ip=|hostnames="`;
	my $rootpw = getsysrootpw();
	println( $callback, "Your virtual machine is ready. It may take a few minutes before you can logon. Below is your VM attributes." );
	println( $callback, "$out" );
	println( $callback, "    rootpw = Same as source node" );
}
1;