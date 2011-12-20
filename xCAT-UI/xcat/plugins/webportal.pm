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
		'clonezlinux' => \&clonezlinux,
		'genhostip'   => \&genhostip,
		'getmaxvm'    => \&getmaxvm
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
	
	# Exit if missing inputs
	if ( !$group || !$hcp || !$img || !$owner ) {
		println( $callback, '(Error) Missing group, HCP, image, or owner' );
		return;
	}

	# Get node OS base
	my $profile;
	my $arch;
	my $os;
	my @tmp;
	( $profile, $arch, $os ) = getosimagedef( $callback, $img );
	if ( $os =~ m/sp/i ) {
		@tmp = split( /sp/, $os );
	} else {
		@tmp = split( /\./, $os );
	}
	my $os_base = $tmp[0];
	
	# Read in default disk pool and disk size /opt/zhcp/conf/default.conf on zHCP
	#	pool = POOL3
	#	eckd_size = 10016
	my $disk_pool;
	my $eckd_size;
	my $fba_size;
	my $default_conf   = '/opt/zhcp/conf/default.conf';
	my $default_direct = "/opt/zhcp/conf/profiles/$profile.direct";

	# Check if a group based directory entry exists, else use default one
	if ( !(`ssh $hcp "test -e /opt/zhcp/conf/profiles/$profile.direct && echo Exists"`) ) {
		println( $callback, "$profile.direct does not exist.  Using default.direct to generate directory entry." );
		
		# Exit if default.direct does not exist
		$default_direct = '/opt/zhcp/conf/profiles/default.direct';	
		if ( !(`ssh $hcp "test -e /opt/zhcp/conf/profiles/default.direct && echo Exists"`) ) {
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
	@tmp = split( /\n/, $out );
	# default.conf should contain:
	
	# Default configuration for virtual machines handled by this zHCP
	#	default_diskpool=POOL3
	#	default_eckd_size=10016
	#	compute_diskpool=POOL3
	#	compute_eckd_size=10016	
	my $profile_diskpool_parm = $profile . "_diskpool";
	my $profile_eckd_size_parm = $profile . "_eckd_size";
	my $profile_fba_size_parm = $profile . "_fba_size";
	my $default_disk_pool;
	my $default_eckd_size;
	my $default_fba_size;
	foreach (@tmp) {
		# Get disk pool (default)
		if ( $_ =~ m/default_diskpool=/i ) {
			$default_disk_pool = $_;
			$default_disk_pool =~ s/default_diskpool=//g;
		}		
		# Get disk size (default)
		elsif ( $_ =~ m/default_eckd_size=/i ) {
			$default_eckd_size = $_;
			$default_eckd_size =~ s/default_eckd_size=//g;
		}
		elsif ( $_ =~ m/default_fba_size=/i ) {
			$default_fba_size = $_;
			$default_fba_size =~ s/default_fba_size=//g;
		}
		
		# Get profile disk pool (default)
		elsif ( $_ =~ m/$profile_diskpool_parm=/i ) {
			$disk_pool = $_;
			$disk_pool =~ s/$profile_diskpool_parm=//g;
		}
		# Get profile disk size (default)
		elsif ( $_ =~ m/$profile_eckd_size_parm=/i ) {
			$eckd_size = $_;
			$eckd_size =~ s/$profile_eckd_size_parm=//g;
		}
		elsif ( $_ =~ m/$profile_fba_size_parm=/i ) {
			$fba_size = $_;
			$fba_size =~ s/$profile_fba_size_parm=//g;
		}
	}
	
	# Use default configuration if profile configuration does not exist
	if (!$disk_pool && (!$eckd_size || !$fba_size)) {
		println( $callback, "$profile configuration for disk pool and size does not exist.  Using default configuration." );
		
		$disk_pool = $default_disk_pool;
		$eckd_size = $default_eckd_size;
		$fba_size = $default_fba_size;
	}

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
	my ($node, $ip, $base_digit) = gennodename( $callback, $group );
	if (!$base_digit) {
		println( $callback, "(Error) Failed to generate node name" );
		return;
	}
	
	my $userid = 'XCAT' . $base_digit;

	# Set node definitions
	# Also put node into all group
	$out = `mkdef -t node -o $node userid=$userid hcp=$hcp mgt=zvm groups=$group,all`;
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

	# Only use the 1st group
	if ($group =~ m/,/) {
		my @groups = split(',', $group);
		$group = @groups[0];
	}	
	
	# Hostname and IP address regular expressions
	my $hostname_regex;
	my $ipaddr_regex;
	
	my @comments;
	my $base_digit = 0;
	my $base_hostname;
	my $base_ipaddr;
	
	# Network, submask, submask prefix, and host ranges
	my $network = "";
	my $mask;
	my $prefix;
	my $hosts_count;
	my $range_low = 1;
	my $range_high = 254;
	
	 # Hostname and IP address generated
	my $hostname;
	my $ipaddr;
	my $tmp;
	
	my @args;

	# Get regular expression for hostname in 'hosts' table
	my $tab = xCAT::Table->new( 'hosts', -create => 1, -autocommit => 0 );
	my @results = $tab->getAllAttribsWhere( "node='" . $group . "'", 'ip', 'comments' );
	foreach (@results) {

		# It should return: |gpok(\d+)|10.1.100.($1+0)|		
		@args = split( /\|/, $_->{'ip'} );
		$hostname_regex = $args[1];
		$ipaddr_regex = $args[2];
		
		$base_hostname = $args[1];		
		$base_hostname =~ s/\(\S*\)/#/g;
		
		# Get the 10.1.100.
		$base_ipaddr = $args[2];
		$base_ipaddr =~ s/\(\S*\)//g;
		
		# Get the ($1+0)
		$ipaddr_regex =~ s/$base_ipaddr//g;
		
		# Get the network within comments
		# It should return: "description: All machines; network: 10.1.100.0/24;"
		# This will help determine the 1st node in the group if none exists
		@comments = split( /;/, $_->{'comments'} );
		foreach (@comments) {
			if ($_ =~ m/network:/i) {
				$network = $_;
				
				# Remove network header
				$network =~ s/network://g;
				
				# Trim network section
				$network =~ s/\s*$//;
				$network =~ s/^\s*//;

				# Extract network
				$tmp = rindex($network, '/');
				if ($tmp > -1) {
					# Get submask prefix
					$prefix = substr($network, $tmp);
					$prefix =~ s|/||g;
					
					# Get the number of hosts possible using submask
					$hosts_count = 32 - int($prefix);
					# Minus network and broadcast addresses
					$hosts_count = 2 ** $hosts_count - 2;
					
					# Get network
					$network = substr($network, 0, $tmp);
				}
				
				# Extract base digit, which depends on the netmask used
				$base_digit = substr($network, rindex($network, '.') + 1);
				# 1st number in range is network
				$range_low = $base_digit + 1;
				
				# Get hosts range
				if ($tmp > -1) {
					$range_high = $base_digit + $hosts_count;
				}
			}
		} # End of foreach
	} # End of foreach
					
	# Are there nodes in this group already?
	# If so, use the existing nodes as a base
	my $out = `nodels $group`;
	@args = split( /\n/, $out );
	foreach (@args) {
		$_ =~ s/$hostname_regex/$1/g;

		# Take the greatest digit
		if ( int($_) > $base_digit ) {
			$base_digit = int($_);
		}
	}

	# +1 to base digit to obtain next hostname
	$base_digit = $base_digit + 1;
	
	# Generate hostname
	$hostname = $base_hostname;
	$hostname =~ s/#/$base_digit/g;
	
	# Generate IP address
	$ipaddr = $hostname;
	$ipaddr =~ s/$hostname_regex/$ipaddr_regex/gee;
	$ipaddr = $base_ipaddr . $ipaddr;
	
	# Get networks in 'networks' table
	$tab = xCAT::Table->new( 'networks', -create => 1, -autocommit => 0 );
	my $entries = $tab->getAllEntries();

	# Go through each network
	my $iprange;
	foreach (@$entries) {

		# Get network, mask, and range
		$network = $_->{'net'};
		$mask = $_->{'mask'};
		$iprange = $_->{'dynamicrange'};
			
		# If the host IP address is in this subnet, return
		if (xCAT::NetworkUtils->ishostinsubnet($ipaddr, $mask, $network)) {

			# Exit loop
			last;
		} else {
			$network = "";
		}
	}
	
	# Exit if no network exist for group
	if (!$network) {
		return;
	}
	
	# Find the network range for this group based on networks table
	my @ranges;
	if ($iprange) {
		@args = split( /;/, $iprange );
		foreach (@args) {
			# If a network range exists
			if ($_ =~ m/-/) {
				@ranges = split( /-/, $_ );
				$range_low = $ranges[0];				
				$range_high = $ranges[1];
				
				# Get the low and high ends digit
				$range_low =~ s/$base_ipaddr//g;
				$range_high =~ s/$base_ipaddr//g;
			}
		}
	} # End of if ($iprange)
	
	# If no nodes exist in group
	# Set the base digit to the low end of the network range
	if ($range_low && $base_digit == 1) {
		$base_digit = $range_low;
		
		# Generate hostname
		$hostname = $base_hostname;
		$hostname =~ s/#/$base_digit/g;
		
		# Generate IP address
		$ipaddr = $hostname;
		$ipaddr =~ s/$hostname_regex/$ipaddr_regex/gee;
		$ipaddr = $base_ipaddr . $ipaddr;
	}
				
	# Check xCAT tables, /etc/hosts, and ping to see if hostname is already used
	while (`nodels $hostname` || `cat /etc/hosts | grep "$ipaddr "` || !(`ping -c 4 $ipaddr` =~ m/100% packet loss/)) {		
		# Base digit invalid if over 254
		if ($base_digit > $range_high) {
			last;
		}
		
		# +1 to base digit to obtain next hostname
		$base_digit = $base_digit + 1;
		
		$hostname = $base_hostname;
		$hostname =~ s/#/$base_digit/g;
		
		$ipaddr = $hostname;
		$ipaddr =~ s/$hostname_regex/$ipaddr_regex/gee;
		$ipaddr = $base_ipaddr . $ipaddr;
	}
		
	# Range must be within network range
	if ($base_digit > $range_high) {
		return;
	} else {
		return ($hostname, $ipaddr, $base_digit);
	}
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
	my ($node, $ip, $base_digit) = gennodename( $callback, $group );
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

sub genhostip {
	my ( $request, $callback, $sub_req ) = @_;
	my $group = $request->{arg}->[1];
	
	my ($node, $ip, $base_digit) = gennodename( $callback, $group );
	println( $callback, "$node: $ip" );
}

sub getmaxvm {
	my ( $request, $callback, $sub_req ) = @_;
	my $user = $request->{arg}->[1];
	
	my @args;
	my $max;
	
	# Look in 'policy' table
	my $tab = xCAT::Table->new( 'policy', -create => 1, -autocommit => 0 );
	my @results = $tab->getAllAttribsWhere( "name='" . $user . "'", 'comments' );
	foreach (@results) {
		if ( $_->{'comments'} ) {
			@args = split( ';', $_->{'comments'} );
			
			# Extract max VM
			foreach (@args) {
				if ($_ =~ m/max-vm:/i) {
					$_ =~ s/max-vm://g;
					$max = $_;
					last;
				}
			}
		}
	}
	
	$callback->( { data => "Max allowed: $max" } );
}
1;