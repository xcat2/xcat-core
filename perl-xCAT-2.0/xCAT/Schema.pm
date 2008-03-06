# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::Schema;

#  When making additions or deletions to this file please be sure to
#       modify BOTH the tabspec and defspec definitions.  This includes
#       adding descriptions for any new attributes.


#Note that the SQL is far from imaginative.  Fact of the matter is that
#certain SQL backends don't ascribe meaning to the data types anyway.
#New format, not sql statements, but info enough to describe xcat tables
%tabspec = (
chain => {
    cols => [qw(node currstate currchain chain ondiscover comments disable)],
    keys => [qw(node)],
    table_desc => 'Controls what operations are done (and it what order) when a node is discovered and deployed.',
	descriptions => {
		node => 'The node name or group name.',
		currstate => 'The current chain state for this node.  Set by xCAT.',
		currchain => 'The current execution chain for this node.  Set by xCAT.  Initialized from chain and updated as chain is executed.',
		chain => 'A comma-delimited chain of actions to be performed automatically for this node. Valid values:  discover, boot or reboot, install or netboot, runcmd=<cmd>, runimage=<image>, shell, standby. (Default - same as no chain).  Example, for BMC machines use: runcmd=bmcsetup,standby.',
		ondiscover => 'What to do when a new node is discovered.  Valid values: nodediscover.',
    	comments => 'Any user-written notes.',
    	disable => "Set to 'yes' or '1' to comment out this row.",
	},
  },
deps => {
    cols => [qw(node nodedep msdelay cmd comments disable)],
    keys => [qw(node)],
    table_desc => 'Describes dependencies some nodes have on others.  This can be used, e.g., by rpower -d to power nodes on or off in the correct order.',
	descriptions => {
		node => 'The node name or group name.',
		nodedep => 'Comma-separated list of nodes it is dependent on.',
		msdelay => 'How long to wait between operating on the dependent nodes and the primary nodes.',
		cmd => 'Comma-seperated list of which operation this dependency applies to.',
    	comments => 'Any user-written notes.',
    	disable => "Set to 'yes' or '1' to comment out this row.",
	},
  },
hosts => {
    cols => [qw(node ip hostnames comments disable)],
    keys => [qw(node)],
    table_desc => 'IP address and hostnames of nodes.  This info can be used to populate /etc/hosts or DNS.',
	descriptions => {
		node => 'The node name or group name.',
		ip => 'The IP address of the node.',
		hostnames => 'Hostname aliases added to /etc/hosts for this node.',
    	comments => 'Any user-written notes.',
    	disable => "Set to 'yes' or '1' to comment out this row.",
	},
  },
ipmi => {
    cols => [qw(node bmc username password comments disable )],
    keys => [qw(node)],
    table_desc => 'Settings for nodes that are controlled by an on-board BMC via IPMI.',
	descriptions => {
		node => 'The node name or group name.',
		bmc => 'The hostname of the BMC adapater.',
		username => 'The BMC userid.  If not specified, the key=ipmi row in the passwd table is used as the default.',
		password => 'The BMC password.  If not specified, the key=ipmi row in the passwd table is used as the default.',
    	comments => 'Any user-written notes.',
    	disable => "Set to 'yes' or '1' to comment out this row.",
	},
  },
iscsi => {
    cols => [qw(node server target file userid passwd kernel kcmdline initrd comments disable)],
    keys => [qw(node)],
    table_desc => 'Contains settings that control how to boot a node from an iSCSI disk.',
	descriptions => {
		node => 'The node name or group name.',
		server => 'The server containing the iscsi boot device for this node.',
		target => '??The target of the iscsi disk used for the boot device for this node.',
		file => '??',
		userid => 'The userid of the iscsi server containing the boot device for this node.',
		passwd => 'The password for the iscsi server containing the boot device for this node.',
		kernel => 'The linux kernel version to use with iSCSI for this node.',
		kcmdline => 'The kernel command line to use with iSCSI for this node.',
		initrd => 'The initial ramdisk to use when network booting this node.',
    	comments => 'Any user-written notes.',
    	disable => "Set to 'yes' or '1' to comment out this row.",
	},
  },
mac => {
    cols => [qw(node interface mac comments disable)],
    keys => [qw(node)],
    table_desc => "The MAC address of the node's install adapter.  Normally this table is populated by getmacs or node discovery, but you can also add entries to it manually.",
	descriptions => {
		node => 'The node name or group name.',
		interface => 'The adapter interface name that will be used to install and manage the node. E.g. eth0 (for linux) or en0 (for AIX).)',
		mac => 'The MAC address of the network adapter that will be used to install the node, e.g. 00:D0:A8:00:05:F3 .',
    	comments => 'Any user-written notes.',
    	disable => "Set to 'yes' or '1' to comment out this row.",
	},
  },
monitoring => {
    cols => [qw(name nodestatmon comments disable)],
    keys => [qw(name)],
    required => [qw(name)],
    table_desc => 'Controls what external monitoring tools xCAT sets up and uses.  Entries should be added and removed from this table using the provided xCAT commands startmon and stopmon.',
	descriptions => {
		name => "The name of the mornitoring plug-in module.  The plug-in must be put in $ENV{XCATROOT}/lib/perl/xCAT_monitoring/.  See the man page for startmon for details.",
		nodestatmon => 'Specifies if the monitoring plug-in is used to feed the node status to the xCAT cluster.  Any one of the following values indicates "yes":  y, Y, yes, Yes, YES, 1.  Any other value or blank (default), indicates "no".',
		comments => 'Any user-written notes.',
		disable => "Set to 'yes' or '1' to comment out this row.",
	},
  },
monsetting => {
    cols => [qw(name key value comments disable)],
    keys => [qw(name key)],
    required => [qw(name key)],
    table_desc => 'Specifies the monitoring plug-in specific settings. These settings will be used by the monitoring plug-in to customize the behavior such as event filter, sample interval, responses etc. Entries should be added, removed or modified by chtab command. Entries can also be added or modified by the startmon command when a monitoring plug-in is brought up.',
	descriptions => {
		name => "The name of the mornitoring plug-in module.  The plug-in must be put in $ENV{XCATROOT}/lib/perl/xCAT_monitoring/.  See the man page for startmon for details.",
		key => 'Specifies the name of the attribute. The valid values are specified by each monitoring plug-in. Use "lsmon name -d" to get a list of valid keys.',
		value => 'Specifies the value of the attribute.',
		comments => 'Any user-written notes.',
		disable => "Set to 'yes' or '1' to comment out this row.",
	},
  },
mp => {
    cols => [qw(node mpa id comments disable)],
    keys => [qw(node)],
    table_desc => 'Contains the hardware control info specific to blades.  This table also refers to the mpa table, which contains info about each Management Module.',
	descriptions => {
		node => 'The blade node name or group name.',
		mpa => 'The managment module used to control this blade.',
		id => 'The slot number of this blade in the BladeCenter chassis.',
    	comments => 'Any user-written notes.',
    	disable => "Set to 'yes' or '1' to comment out this row.",
	},
  },
mpa => {
    cols => [qw(mpa username password comments disable)],
    keys => [qw(mpa)],
    table_desc => 'Contains info about each Management Module and how to access it.',
	descriptions => {
		mpa => 'Hostname of the management module.',
		username => 'Userid to use to access the management module.  If not specified, the key=blade row in the passwd table is used as the default.',
		password => 'Password to use to access the management module.  If not specified, the key=blade row in the passwd table is used as the default.',
    	comments => 'Any user-written notes.',
    	disable => "Set to 'yes' or '1' to comment out this row.",
	},
  },
networks => {
    cols => [qw(netname net mask mgtifname gateway dhcpserver tftpserver nameservers dynamicrange nodehostname comments disable)],
    keys => [qw(net mask)],
    table_desc => 'Describes the networks in the cluster and info necessary to set up nodes on that network.',
	descriptions => {
		netname => 'Name used to identify this network definition.',
		net => 'The network address.',
		mask => 'The network mask.',
		mgtifname => 'Default ethernet interface name used by nodes on this network??',
		gateway => 'The network gateway.',
		dhcpserver => 'The DHCP server that is servicing this network.',
		tftpserver => 'The TFTP server that is servicing this network.',
		nameservers => 'The nameservers for this network.  Used in creating the DHCP network definition.',
		dynamicrange => 'The IP address range used by DHCP to assign dynamic IP addresses for requests on this network.',
		nodehostname => '??',
    	comments => 'Any user-written notes.',
    	disable => "Set to 'yes' or '1' to comment out this row.",
	},
  },
nodegroup => {
	cols => [qw(groupname grouptype members wherevals comments disable)],
	keys => [qw(groupname)],
    table_desc => 'Not supported yet!  Contains group definitions, whose membership is dynamic depending on characteristics of the node.',
	descriptions => {
		groupname => 'Name of the group.',
		grouptype => 'The only current valid value is dynamic.  We will be looking at having the object def commands working with static group definitions in the nodelist table.',
		members => 'The value of the attribute is not used, but the attribute is necessary as a place holder for the object def commands.  (The membership for static groups is stored in the nodelist table.)',
		wherevals => 'A list of comma-separated "attr=val" pairs that can be used to determine the members of a dynamic group.',
    	comments => 'Any user-written notes.',
    	disable => "Set to 'yes' or '1' to comment out this row.",
	},
  },
nodehm => {
    cols => [qw(node power mgt cons termserver termport conserver serialspeed serialflow getmac comments disable)],
    keys => [qw(node)],
    table_desc => "Settings that control how each node's hardware is managed.  Typically, an additional table that is specific to the hardware type of the node contains additional info.  E.g. the ipmi, mp, and ppc tables.",
	descriptions => {
		node => 'The node name or group name.',
		power => 'The method to use to control the power of the node. If not set, the mgt attribute will be used.  Valid values: ipmi, blade, hmc, ivm, fsp.  If "ipmi", xCAT will search for this node in the ipmi table for more info.  If "blade", xCAT will search for this node in the mp table.  If "hmc", "ivm", or "fsp", xCAT will search for this node in the ppc table.',
		mgt => 'The method to use to do general hardware management of the node.  This attribute is used as the default if power, cons, or getmac is not set.  Valid values: ipmi, blade, hmc, ivm, fsp.  See the power attribute for more details.',
		cons => 'The console method. If not set, the mgt attribute will be used.  Valid values: cyclades, mrv, or the values valid for mgt??',
		termserver => 'The hostname of the terminal server.',
		termport => 'The port number on the terminal server that this node is connected to.',
		conserver => 'The hostname of the machine where the conserver daemon is running.  If not set, the default is the xCAT management node.',
		serialspeed => 'The speed of the serial port for this node.  For SOL on blades, this is typically 19200.',
		serialflow => "The flow value of the serial port for this node.  For SOL on blades, this is typically 'hard'.",
		getmac => 'The method to use to get MAC address of the node. If not set, the mgt attribute will be used.  Valid values: switch, blade, ivm, hmc??',
    	comments => 'Any user-written notes.',
    	disable => "Set to 'yes' or '1' to comment out this row.",
	},
  },
nodelist => {
    cols => [qw(node groups nodetype status comments disable)],
    keys => [qw(node)],
    table_desc => "The list of all the nodes in the cluster, including each node's current status and what groups it is in.",
    descriptions => {
    	node => 'The hostname of a node in the cluster.',
    	nodetype => 'A comma-delimited list of characteristics of this node.  Valid values: blade, vm (virtual machine), lpar, osi (OS image), hmc, fsp, ivm, bpa, mm, rsa, switch.',
    	groups => "A comma-delimited list of groups this node is a member of.  Group names are arbitrary, except all nodes should be part of the 'all' group.",
    	status => 'The current status of this node.  This attribute will be set by xCAT software.  Valid values: defined, booting, discovering, installing, installed, alive, off.',
    	comments => 'Any user-written notes.',
    	disable => "Set to 'yes' or '1' to comment out this row.",
    },
  },
nodepos => {
    cols => [qw(node rack u chassis slot room comments disable)],
    keys => [qw(node)],
    table_desc => 'Contains info about the physical location of each node.  Currently, this info is not used by xCAT, and therefore can be in whatevery format you want.  It will likely be used in xCAT in the future.',
	descriptions => {
		node => 'The node name or group name.',
		rack => 'The frame the node is in.',
		u => 'The vertical position of the node in the frame',
		chassis => 'The BladeCenter chassis the blade is in.',
		slot => 'The slot number of the blade in the chassis.',
		room => 'The room the node is in.',
    	comments => 'Any user-written notes.',
    	disable => "Set to 'yes' or '1' to comment out this row.",
	},
  },
noderes => {
    cols => [qw(node servicenode netboot tftpserver nfsserver monserver kernel initrd kcmdline nfsdir serialport installnic primarynic xcatmaster current_osimage next_osimage comments disable)],
    keys => [qw(node)],
    table_desc => 'Resources and settings to use when installing nodes.',
	descriptions => {
		node => 'The node name or group name.',
		servicenode => 'The node that provides most services for this node (as known by the management node).',
		netboot => 'The type of network booting supported by this node.  Valid values:  pxe, yaboot.',
		tftpserver => 'The TFTP server for this node (as known by this node).',
		nfsserver => 'The NFS server for this node (as known by this node).',
		monserver => 'The monitoring aggregation point for this node (as known by the management node).',
		kernel => 'The linux kernel version to install on the node.',
		initrd => 'The linux initial ramdisk image used to deploy the node.',
		kcmdline => 'The kernel command line used to deploy the node.',
		nfsdir => 'Not used??  The path that should be mounted from the NFS server.',
		serialport => 'The serial port for this node.  For SOL on blades, this is typically 1.  For IPMI, this is typically 0.',
		installnic => 'The network adapter on the node that will be used for OS deployment.  If not set, primarynic will be used.',
		primarynic => 'The network adapter on the node that will be used for xCAT management.  Default is eth0.',
		xcatmaster => 'The hostname of the xCAT service node (as known by this node).  This is the default value if nfsserver or tftpserver are not set.',
		current_osimage => 'Not currently used.  The name of the osimage data object that represents the OS image currently deployed on this node.',
		next_osimage => 'Not currently used.  The name of the osimage data object that represents the OS image that will be installed on the node the next time it is deployed.',
    	comments => 'Any user-written notes.',
    	disable => "Set to 'yes' or '1' to comment out this row.",
	},
  },
nodetype => {
    cols => [qw(node os arch profile comments disable)],
    keys => [qw(node)],
    table_desc => 'A few hardware and software characteristics of the nodes.',
	descriptions => {
		node => 'The node name or group name.',
		os => 'The operating system deployed on this node.  Valid values: rh*, centos*, fedora*, sles* (where * is the version #).',
		arch => 'The hardware architecture of this node.  Valid values: x86_64, ppc64, x86, ia64.',
		profile => 'The kickstart or autoyast template to use for OS deployment of this node.',
    	comments => 'Any user-written notes.',
    	disable => "Set to 'yes' or '1' to comment out this row.",
	},
  },
notification => {
    cols => [qw(filename tables tableops comments disable)],
    keys => [qw(filename)],
    required => [qw(tables filename)],
    table_desc => 'Contains registrations to be notified when a table in the xCAT database changes.  Users can add entries to have additional software notified of changes.  Add and remove entries using the provided xCAT commands regnotif and unregnotif.',
	descriptions => {
		filename => 'The path name of a file that implements the callback routine when the monitored table changes.  Can be a perl module or a command.  See the regnotif man page for details.',
		tables => 'Comma-separated list of xCAT database tables to monitor.',
		tableops => 'Specifies the table operation to monitor for. Valid values:  "d" (rows deleted), "a" (rows added), "u" (rows updated).',
    	comments => 'Any user-written notes.',
    	disable => "Set to 'yes' or '1' to comment out this row.",
	},
  },
osimage  => {
	cols => [qw(imagename osname osvers osdistro osarch comments disable)],
	keys => [qw(imagename)],
    table_desc => 'Not used yet!  All the info that specifies a particular operating system image that can be used on nodes.',
	descriptions => {
		imagename => 'User given name of the OS image.',
		osname => '',
		osvers => '',
		osdistro => '',
		osarch => '',
    	comments => 'Any user-written notes.',
    	disable => "Set to 'yes' or '1' to comment out this row.",
	},
  },
passwd => {
    cols => [qw(key username password comments disable)],
    keys => [qw(key)],
    table_desc => 'Contains default userids and passwords for xCAT to access cluster components.  Userids/passwords for specific cluster components can be overidden in other tables, e.g. mpa, ipmi, ppchcp, etc.',
	descriptions => {
		key => 'The type of component this user/pw is for.  Valid values: blade (management module), ipmi (BMC), system (nodes??), omapi (DHCP), hmc, ivm, fsp.',
		username => 'The default userid for this type of component',
		password => 'The default password for this type of component',
    	comments => 'Any user-written notes.',
    	disable => "Set to 'yes' or '1' to comment out this row.",
	},
  },
policy => {
    cols => [qw(priority name host commands noderange parameters time rule comments disable)],
    keys => [qw(priority)],
    table_desc => 'Not fully implemented!  Controls who has authority to run specific xCAT operations.',
	descriptions => {
		priority => 'The priority value for this rule.  This value is used to identify this policy data object (i.e. this rule).',
		name => 'The username that is allowed to perform the commands specified by this rule.  Default is "*" (all users).',
		host => 'The host from which users may issue the commands specified by this rule.  Default is "*" (all hosts).',
		commands => 'The list of commands that this rule applies to.  Default is "*" (all commands).',
		noderange => 'The Noderange that this rule applies to.  Default is "*" (all nodes).',
		parameters => 'Command parameters that this rule applies to.  Default??',
		time => 'Time ranges that this command may be executed in.  Default is any time.',
		rule => 'Specifies how this rule should be applied.  Valid values are: allow, accept.  Either of these values will allow the user to run the commands.  Any other value will deny the user access to the commands.',
    	comments => 'Any user-written notes.',
    	disable => "Set to 'yes' or '1' to comment out this row.",
	},
  },
postscripts => {
    cols => [qw(node postscripts comments disable)],
    keys => [qw(node)],
    table_desc => 'Not used yet!  The scripts that should be run on each node after installation or diskless boot.',
	descriptions => {
		node => 'The node name or group name.',
		postscripts => 'Comma separated list of scripts that should be run on this node after installation or diskless boot.',
    	comments => 'Any user-written notes.',
    	disable => "Set to 'yes' or '1' to comment out this row.",
	},
  },
ppc => {
    cols => [qw(node hcp id profile parent comments disable)],
    keys => [qw(node)],
    table_desc => 'List of system p hardware: HMCs, IVMs, FSPs, BPCs.',
	descriptions => {
		node => 'The node name or group name.',
		hcp => 'The hardware control point for this node (HMC, IVM, or FSP).  If ',
		id => 'For LPARs: the LPAR numeric id; for FSPs: the cage number; for BPAs: the frame number.',
		profile => 'The LPAR profile that will be used the next time the LPAR is powered on with rpower.',
		parent => 'For LPARs: the FSP/CEC; for FSPs: the BPA (if one exists).',
    	comments => 'Any user-written notes.',
    	disable => "Set to 'yes' or '1' to comment out this row.",
	},
  },
ppcdirect => {
    cols => [qw(hcp username password comments disable)],
    keys => [qw(hcp)],
    table_desc => 'Info necessary to use FSPs to control system p CECs.',
	descriptions => {
		hcp => 'Hostname of the FSP.',
		username => 'Userid of the FSP.  If not filled in, xCAT will look in the passwd table for key=fsp.  If not in the passwd table, the default used is admin.',
		password => 'Password of the FSP.  If not filled in, xCAT will look in the passwd table for key=fsp.  If not in the passwd table, the default used is admin.',
    	comments => 'Any user-written notes.',
    	disable => "Set to 'yes' or '1' to comment out this row.",
	},
  },
ppchcp => {
    cols => [qw(hcp username password comments disable)],
    keys => [qw(hcp)],
    table_desc => 'Info necessary to use HMCs and IVMs as hardware control points for LPARs.',
	descriptions => {
		hcp => 'Hostname of the HMC or IVM.',
		username => 'Userid of the HMC or IVM.  If not filled in, xCAT will look in the passwd table for key=hmc or key=ivm.  If not in the passwd table, the default used is hscroot for HMCs and padmin for IVMs.',
		password => 'Password of the HMC or IVM.  If not filled in, xCAT will look in the passwd table for key=hmc or key=ivm.  If not in the passwd table, the default used is abc123 for HMCs and padmin for IVMs.',
    	comments => 'Any user-written notes.',
    	disable => "Set to 'yes' or '1' to comment out this row.",
	},
  },
site => {
    cols => [qw(key value comments disable)],
    keys => [qw(key)],
    table_desc => 'Global settings for the whole cluster.  This table is different from the other tables in that each attribute is just named in the key column, rather than having a separate column for each attribute.',
	descriptions => {
		key => "Name of the attribute.  Valid values:\n".
			"\t master (xCAT management node)\n".
			"\t xcatconfdir (default /etc/xcat)\n".
			"\t domain (DNS domain name used for the cluster)\n".
			"\t installdir (directory that holds the node deployment pkgs)\n".
			"\t xcatdport (port used by xcatd daemon for client/server communication)\n".
			"\t xcatiport (port used by xcatd to receive install status updates from nodes)\n".
			"\t timezone (e.g. America/New_York)\n".
			"\t nameservers (list of DNS servers for the cluster)\n".
			"\t rsh (path of remote shell command)\n".
			"\t rcp (path of remote copy command)\n".
			"\t blademaxp (max # of processes for blade hw ctrl)\n".
			"\t ppcmaxp (max # of processes for PPC hw ctrl)\n".
			"\t ipmimaxp\n".
			"\t ipmitimeout\n".
			"\t ipmiretries\n".
			"\t ipmisdrcache\n".
			"\t iscsidir\n".
			"\t xcatservers (service nodes??)\n".
			"\t dhcpinterfaces (network interfaces DHCP should listen on??)\n".
			"\t forwarders (DNS forwarders??)\n".
			"\t genpasswords (generate BMC passwords??)\n".
			"\t defserialport (default if not specified in noderes table)\n".
			"\t defserialspeed (default if not specified in nodehm table)\n".
			"\t defserialflow (default if not specified in nodehm table)",
		value => 'The value of the attribute specified in the "key" column.',
    	comments => 'Any user-written notes.',
    	disable => "Set to 'yes' or '1' to comment out this row.",
	},
  },
#  site => {
#    cols => [qw(sitename domain master rsh rcp xcatdport installdir comments disable)],
#    keys => [qw(sitename)]
#  },
switch =>  {
    cols => [qw(node switch port vlan interface comments disable)],
    keys => [qw(node switch port)],
    table_desc => 'Contains what switch port numbers each node is connected to.',
	descriptions => {
		node => 'The node name or group name.',
		switch => 'The switch hostname.',
		port => 'The port number in the switch that this node is connected to. On a simple 1U switch, an administrator can generally enter the number as printed next to the ports, and xCAT will understand switch representation differences.  On stacked switches or switches with line cards, administrators should usually use the CLI representation (i.e. 2/0/1 or 5/8).  One notable exception is stacked SMC 8848M switches, in which you must add 56 for the proceeding switch, then the port number.  For example, port 3 on the second switch in an SMC8848M stack would be 59',
		vlan => 'xCAT currently does not make use of this field, however it may do so in the future.  For now, it can be used by administrators for their own purposes, but keep in mind some xCAT feature later may try to enforce this if set',
		interface => 'The interface name from the node perspective.  This is not currently used by xCAT, but administrators may wish to use this for their own purposes',
    	comments => 'Any user-written notes.',
    	disable => "Set to 'yes' or '1' to comment out this row.",
	},
  },
vpd => {
    cols => [qw(node serial mtm comments disable)],
    keys => [qw(node)],
    table_desc => 'The Machine type, Model, and Serial numbers of each node.',
	descriptions => {
		node => 'The node name or group name.',
		serial => 'The serial number of the node.',
		mtm => 'The machine type and model number of the node.  E.g. 7984-6BU',
    	comments => 'Any user-written notes.',
    	disable => "Set to 'yes' or '1' to comment out this row.",
	},
  },
);        # end of tabspec definition



####################################################
#
#  Data abstraction definitions
#    For each table entry added to the database schema,
#    a corresponding attribute should be added to one of
#    the data objects below, or new data objects should
#    be created as needed.
#
#  Definition format:
#    List of data object hashes:
#       <dataobject_name> =>
#          {attrs =>
#             [ {attr_name => '<attribute_name>',
#                only_if => '<attr>=<value>',
#                         # optional, used to define conditional attributes.
#                         # <attr> is a previously resolved attribute from
#                         # this data object.
#                tabentry => '<table.attr>',
#                         # where the data is stored in the database
#                access_tabentry => '<table.attr>=<value>',
#		 	  # how to look up tabentry.  For <value>,
#                         # if "attr:<attrname>", use a previously resolved
#                         #    attribute value from the data object
#                         # if "str:<value>" use the value directly
#                description => '<description of this attribute>',
#                },
#                {attr_name => <attribute_name>,
#                    ...
#                } ],
#           attrhash => {}, # internally generated hash of attrs array
#                           # to allow code direct access to an attr def
#           objkey => 'attribute_name'  # key attribute for this data object
#          }
#
#
####################################################
%defspec = (
  node =>    { attrs => [], attrhash => {}, objkey => 'node' },
  osimage => { attrs => [], attrhash => {}, objkey => 'imagename' },
  network => { attrs => [], attrhash => {}, objkey => 'netname' },
  group => { attrs => [], attrhash => {}, objkey => 'groupname' },
  site =>    { attrs => [], attrhash => {}, objkey => 'master' },
#site =>    { attrs => [], attrhash => {}, objkey => 'sitename' },
  policy => { attrs => [], attrhash => {}, objkey => 'priority' },
  monitoring => { attrs => [], attrhash => {}, objkey => 'name' },
  notification => { attrs => [], attrhash => {}, objkey => 'filename' }
);


###############
#   @nodeattrs ia a list of node attrs that can be used for
#		BOTH node and group definitions
##############

my @nodeattrs = (
####################
# postscripts table#
####################
        {attr_name => 'postscripts',
                 tabentry => 'postscripts.postscripts',
                 access_tabentry => 'postscripts.node=attr:node',
		},
####################
#  noderes table   #
####################
        {attr_name => 'xcatmaster',
                 tabentry => 'noderes.xcatmaster',
                 access_tabentry => 'noderes.node=attr:node',
		},
###
# TODO:  Need to check/update code to make sure it really uses servicenode as
#        default if other server value not set
###
        {attr_name => 'servicenode',
                 tabentry => 'noderes.servicenode',
                 access_tabentry => 'noderes.node=attr:node',
		},
        {attr_name => 'tftpserver',
                 only_if => 'nodetype=osi',
                 tabentry => 'noderes.tftpserver',
                 access_tabentry => 'noderes.node=attr:node',
		},
        {attr_name => 'nfsserver',
                 only_if => 'nodetype=osi',
                 tabentry => 'noderes.nfsserver',
                 access_tabentry => 'noderes.node=attr:node',
		},
###
# TODO:  Is noderes.nfsdir used anywhere?  Could not find any code references
#        to this attribute.
###
        {attr_name => 'nfsdir',
                 only_if => 'nodetype=osi',
                 tabentry => 'noderes.nfsdir',
                 access_tabentry => 'noderes.node=attr:node',
		},
        {attr_name => 'monserver',
                 only_if => 'nodetype=osi',
                 tabentry => 'noderes.monserver',
                 access_tabentry => 'noderes.node=attr:node',
		},
	{attr_name => 'kernel',
                 tabentry => 'noderes.kernel',
                 access_tabentry => 'noderes.node=attr:node',
                },
	{attr_name => 'initrd',
                 tabentry => 'noderes.initrd',
                 access_tabentry => 'noderes.node=attr:node',
                },
	{attr_name => 'kcmdline',
                 tabentry => 'noderes.kcmdline',
                 access_tabentry => 'noderes.node=attr:node',
                },
        # Note that the serialport attr is actually defined down below
        # with the other serial*  attrs from the nodehm table
        #{attr_name => 'serialport',
        #         tabentry => 'noderes.serialport',
        #         access_tabentry => 'noderes.node=attr:node',
        #	},
        {attr_name => 'primarynic',
                 only_if => 'nodetype=osi',
                 tabentry => 'noderes.primarynic',
                 access_tabentry => 'noderes.node=attr:node',
		},
        {attr_name => 'installnic',
                 only_if => 'nodetype=osi',
                 tabentry => 'noderes.installnic',
                 access_tabentry => 'noderes.node=attr:node',
		},
        {attr_name => 'netboot',
                 only_if => 'nodetype=osi',
                 tabentry => 'noderes.netboot',
                 access_tabentry => 'noderes.node=attr:node',
		},
        {attr_name => 'current_osimage',
                 only_if => 'nodetype=osi',
                 tabentry => 'noderes.current_osimage',
                 access_tabentry => 'noderes.node=attr:node',
		},
        {attr_name => 'next_osimage',
                 only_if => 'nodetype=osi',
                 tabentry => 'noderes.next_osimage',
                 access_tabentry => 'noderes.node=attr:node',
		},

######################
#  nodetype table    #
######################
        {attr_name => 'arch',
                 tabentry => 'nodetype.arch',
                 access_tabentry => 'nodetype.node=attr:node',
		},
# TODO:  need to decide what to do with the os attr once the osimage stuff is
#        implemented.  The nodetype.os attr may be moved to the osimage table.
        {attr_name => 'os',
                 only_if => 'nodetype=osi',
                 tabentry => 'nodetype.os',
                 access_tabentry => 'nodetype.node=attr:node',
		},
# TODO:  need to decide what to do with the profile attr once the osimage
#        stuff is implemented.  May want to move this to the osimage table.
        {attr_name => 'profile',
                 only_if => 'nodetype=osi',
                 tabentry => 'nodetype.profile',
                 access_tabentry => 'nodetype.node=attr:node',
		},
####################
#  iscsi table     #
####################
	{attr_name => iscsiserver,
                 only_if => 'nodetype=osi',
                 tabentry => 'iscsi.server',
                 access_tabentry => 'iscsi.node=attr:node',
                },
	{attr_name => iscsitarget,
                 only_if => 'nodetype=osi',
                 tabentry => 'iscsi.target',
                 access_tabentry => 'iscsi.node=attr:node',
                },
	{attr_name => iscsiuserid,
                 only_if => 'nodetype=osi',
                 tabentry => 'iscsi.userid',
                 access_tabentry => 'iscsi.node=attr:node',
                },
	{attr_name => iscsipassword,
                 only_if => 'nodetype=osi',
                 tabentry => 'iscsi.passwd',
                 access_tabentry => 'iscsi.node=attr:node',
                },
####################
#  nodehm table    #
####################
        {attr_name => 'mgt',
                 tabentry => 'nodehm.mgt',
                 access_tabentry => 'nodehm.node=attr:node',
		},
        {attr_name => 'power',
                 tabentry => 'nodehm.power',
                 access_tabentry => 'nodehm.node=attr:node',
		},
        {attr_name => 'cons',
                 tabentry => 'nodehm.cons',
                 access_tabentry => 'nodehm.node=attr:node',
		},
        {attr_name => 'termserver',
                 tabentry => 'nodehm.termserver',
                 access_tabentry => 'nodehm.node=attr:node',
		},
        {attr_name => 'termport',
                 tabentry => 'nodehm.termport',
                 access_tabentry => 'nodehm.node=attr:node',
		},
###
# TODO:  is nodehm.conserver used anywhere?  I couldn't find any code references
###
        {attr_name => 'conserver',
                 tabentry => 'nodehm.conserver',
                 access_tabentry => 'nodehm.node=attr:node',
		},
###
# TODO:  is nodehm.getmac used anywhere?  I couldn't find any code references
###
        {attr_name => 'getmac',
                 tabentry => 'nodehm.getmac',
                 access_tabentry => 'nodehm.node=attr:node',
		},
        # Note that serialport is in the noderes table.  Keeping it here in
        # the defspec so that it gets listed with the other serial* attrs
        {attr_name => 'serialport',
                 tabentry => 'noderes.serialport',
                 access_tabentry => 'noderes.node=attr:node',
		},
        {attr_name => 'serialspeed',
                 tabentry => 'nodehm.serialspeed',
                 access_tabentry => 'nodehm.node=attr:node',
		},
        {attr_name => 'serialflow',
                 tabentry => 'nodehm.serialflow',
                 access_tabentry => 'nodehm.node=attr:node',
		},
##################
#  vpd table     #
##################
        {attr_name => 'serial',
                 tabentry => 'vpd.serial',
                 access_tabentry => 'vpd.node=attr:node',
		},
        {attr_name => 'mtm',
                 tabentry => 'vpd.mtm',
                 access_tabentry => 'vpd.node=attr:node',
		},
##################
#  mac table     #
##################
	{attr_name => 'interface',
                 tabentry => 'mac.interface',
                 access_tabentry => 'mac.node=attr:node',
                },
	{attr_name => 'mac',
                 tabentry => 'mac.mac',
                 access_tabentry => 'mac.node=attr:node',
                },
##################
#  chain table   #
##################
###
# TODO:  Need user documentation from Jarrod on how to use chain, what each
#        action does, valid ordering, etc.
###
	{attr_name => 'chain',
                 tabentry => 'chain.chain',
                 access_tabentry => 'chain.node=attr:node',
                },
###
# TODO:  What is chain.ondiscover used for?  Could not find any code references
#        to this table entry
###
	{attr_name => 'ondiscover',
                 tabentry => 'chain.ondiscover',
                 access_tabentry => 'chain.node=attr:node',
                },
	{attr_name => 'currstate',
                 tabentry => 'chain.currstate',
                 access_tabentry => 'chain.node=attr:node',
                },
	{attr_name => 'currchain',
                 tabentry => 'chain.currchain',
                 access_tabentry => 'chain.node=attr:node',
                },
####################
#  ppchcp table    #
####################
	{attr_name => username,
                 only_if => 'nodetype=ivm',
                 tabentry => 'ppchcp.username',
                 access_tabentry => 'ppchcp.hcp=attr:node',
                },
	{attr_name => password,
                 only_if => 'nodetype=ivm',
                 tabentry => 'ppchcp.password',
                 access_tabentry => 'ppchcp.hcp=attr:node',
                },
	{attr_name => username,
                 only_if => 'nodetype=hmc',
                 tabentry => 'ppchcp.username',
                 access_tabentry => 'ppchcp.hcp=attr:node',
                },
	{attr_name => password,
                 only_if => 'nodetype=hmc',
                 tabentry => 'ppchcp.password',
                 access_tabentry => 'ppchcp.hcp=attr:node',
                },
####################
#  ppc table       #
####################
        {attr_name => hcp,
                 only_if => 'mgt=hmc',
                 tabentry => 'ppc.hcp',
                 access_tabentry => 'ppc.node=attr:node',
		},
        {attr_name => hcp,
                 only_if => 'mgt=ivm',
                 tabentry => 'ppc.hcp',
                 access_tabentry => 'ppc.node=attr:node',
		},
	{attr_name => id,
                 only_if => 'mgt=hmc',
                 tabentry => 'ppc.id',
                 access_tabentry => 'ppc.node=attr:node',
                },
	{attr_name => id,
                 only_if => 'mgt=ivm',
                 tabentry => 'ppc.id',
                 access_tabentry => 'ppc.node=attr:node',
                },
	{attr_name => profile,
                 only_if => 'nodetype=lpar',
                 tabentry => 'ppc.profile',
                 access_tabentry => 'ppc.node=attr:node',
                },
	{attr_name => parent,
                 only_if => 'mgt=hmc',
                 tabentry => 'ppc.parent',
                 access_tabentry => 'ppc.node=attr:node',
                },
	{attr_name => parent,
                 only_if => 'mgt=ivm',
                 tabentry => 'ppc.parent',
                 access_tabentry => 'ppc.node=attr:node',
                },
#######################
#  ppcdirect table    #
#######################
        {attr_name => username,
                 only_if => 'mgt=fsp',
                 tabentry => 'ppcdirect.username',
                 access_tabentry => 'ppcdirect.hcp=attr:node',
		},
        {attr_name => password,
                 only_if => 'mgt=fsp',
                 tabentry => 'ppcdirect.password',
                 access_tabentry => 'ppcdirect.hcp=attr:node',
		},
##################
#  ipmi table    #
##################
        {attr_name => bmc,
                 only_if => 'mgt=ipmi',
                 tabentry => 'ipmi.bmc',
                 access_tabentry => 'ipmi.node=attr:node',
		},
        {attr_name => bmcusername,
                 only_if => 'mgt=ipmi',
                 tabentry => 'ipmi.username',
                 access_tabentry => 'ipmi.node=attr:node',
		},
        {attr_name => bmcpassword,
                 only_if => 'mgt=ipmi',
                 tabentry => 'ipmi.password',
                 access_tabentry => 'ipmi.node=attr:node',
		},
################
#  mp table    #
################
        {attr_name => mpa,
                 only_if => 'mgt=blade',
                 tabentry => 'mp.mpa',
                 access_tabentry => 'mp.node=attr:node',
		},
        {attr_name => id,
                 only_if => 'mgt=blade',
                 tabentry => 'mp.id',
                 access_tabentry => 'mp.node=attr:node',
		},
#################
#  mpa table    #
#################
        {attr_name => username,
                 only_if => 'nodetype=mm',
                 tabentry => 'mpa.username',
                 access_tabentry => 'mpa.mpa=attr:node',
		},
        {attr_name => password,
                 only_if => 'nodetype=mm',
                 tabentry => 'mpa.password',
                 access_tabentry => 'mpa.mpa=attr:node',
		},
######################
#  nodepos table     #
######################
        {attr_name => 'rack',
                 tabentry => 'nodepos.rack',
                 access_tabentry => 'nodepos.node=attr:node',
		},
        {attr_name => 'unit',
                 tabentry => 'nodepos.u',
                 access_tabentry => 'nodepos.node=attr:node',
		},
        {attr_name => 'chassis',
                 tabentry => 'nodepos.chassis',
                 access_tabentry => 'nodepos.node=attr:node',
		},
        {attr_name => 'slot',
                 tabentry => 'nodepos.slot',
                 access_tabentry => 'nodepos.node=attr:node',
		},
        {attr_name => 'room',
                 tabentry => 'nodepos.room',
                 access_tabentry => 'nodepos.node=attr:node',
		});


####################
#  node definition  - nodelist & hosts table parts #
####################
@{$defspec{node}->{'attrs'}} = (
####################
#  nodelist table  #
####################
        {attr_name => 'node',
                 tabentry => 'nodelist.node',
                 access_tabentry => 'nodelist.node=attr:node',
			},
        {attr_name => 'nodetype',
                 tabentry => 'nodelist.nodetype',
                 access_tabentry => 'nodelist.node=attr:node',
			},
###
# TODO:  need to implement nodelist.nodetype as a comma-separated list.
#        right now, all references to attr:nodetype are for single values.
#        will need to globally change the def to make this work...
##
        {attr_name => 'groups',
                 tabentry => 'nodelist.groups',
                 access_tabentry => 'nodelist.node=attr:node',
             },
	{attr_name => 'status',
                 tabentry => 'nodelist.status',
                 access_tabentry => 'nodelist.node=attr:node',
             },
####################
#  hosts table    #
####################
        {attr_name => 'ip',
                 tabentry => 'hosts.ip',
                 access_tabentry => 'hosts.node=attr:node',
             },
        {attr_name => 'hostnames',
                 tabentry => 'hosts.hostnames',
                 access_tabentry => 'hosts.node=attr:node',
             },
	{attr_name => 'usercomment',
                 tabentry => 'nodelist.comments',
                 access_tabentry => 'nodelist.node=attr:node',
             },
          );

# add on the node attrs from other tables
push(@{$defspec{node}->{'attrs'}}, @nodeattrs);


#########################
#  osimage data object  #
#########################
#     osimage table     #
#########################
###
# TODO:  The osimage table is currently not used by any xCAT code.
#        Need full implementation
###
@{$defspec{osimage}->{'attrs'}} = (
        {attr_name => 'imagename',
                 tabentry => 'osimage.imagename',
                 access_tabentry => 'osimage.imagename=attr:imagename',
#                 description => 'The name of this operating system image.'},
                 },
	{attr_name => 'osdistro',
                 tabentry => 'osimage.osdistro',
                 access_tabentry => 'osimage.imagename=attr:imagename',
#                 description => 'The Linux distribution name to be deployed. The valid values are RedHat, and SLES.'},
                 },
        {attr_name => 'osname',
                 tabentry => 'osimage.osname',
                 access_tabentry => 'osimage.imagename=attr:imagename',
#                description => 'The name of the operating system to be deployed. The expected values are AIX or Linux.'},
                 },
	{attr_name => 'osvers',
                 tabentry => 'osimage.osvers',
                 access_tabentry => 'osimage.imagename=attr:imagename',
#                 description => 'The operating system version to be deployed. The formats for the values are "version.release.mod" for AIX and "version" for Linux. (ex. AIX: "5.3.0", Linux: "5").'},
                 },
	{attr_name => 'osarch',
                 tabentry => 'osimage.osarch',
                 access_tabentry => 'osimage.imagename=attr:imagename',
#                 description => 'The node machine architecture.'},
                 },
	{attr_name => 'usercomment',
                 tabentry => 'osimage.comments',
                 access_tabentry => 'osimage.imagename=attr:imagename',
#                description => 'User comment.'},
                 },
             );

#########################
#  network data object  #
#########################
#     networks table    #
#########################
@{$defspec{network}->{'attrs'}} = (
###
# TODO:  when creating networks table entries, create a default netname
#        See makenetworks command and networks.pm plugin
###
        {attr_name => 'netname',
                 tabentry => 'networks.netname',
                 access_tabentry => 'networks.netname=attr:netname',
                 },
        {attr_name => 'net',
                 tabentry => 'networks.net',
                 access_tabentry => 'networks.netname=attr:netname',
		},
        {attr_name => 'mask',
                 tabentry => 'networks.mask',
                 access_tabentry => 'networks.netname=attr:netname',
		},
        {attr_name => 'gateway',
                 tabentry => 'networks.gateway',
                 access_tabentry => 'networks.netname=attr:netname',
		},
        {attr_name => 'dhcpserver',
                 tabentry => 'networks.dhcpserver',
                 access_tabentry => 'networks.netname=attr:netname',
		},
        {attr_name => 'tftpserver',
                 tabentry => 'networks.tftpserver',
                 access_tabentry => 'networks.netname=attr:netname',
		},
        {attr_name => 'nameservers',
                 tabentry => 'networks.nameservers',
                 access_tabentry => 'networks.netname=attr:netname',
		},
        {attr_name => 'dynamicrange',
                 tabentry => 'networks.dynamicrange',
                 access_tabentry => 'networks.netname=attr:netname',
		},
	{attr_name => 'usercomment',
                 tabentry => 'networks.comments',
                 access_tabentry => 'networks.netname=attr:netname',
                },
             );

#####################
#  site data object #
#####################
#     site table    #
#####################
##############
# TODO:  need to figure out how to handle a key for the site table.
#        since this is really implemented differently than all the other
#        data objects, it doesn't map as cleanly.
#        change format of site table so each column is an attr and there
#        is only a single row in the table keyed by xcatmaster name?
#############
@{$defspec{site}->{'attrs'}} = (
        {attr_name => 'master',
                 tabentry => 'site.value',
                 access_tabentry => 'site.key=str:master',
                 description => 'The management node'},
        {attr_name => 'installdir',
                 tabentry => 'site.value',
                 access_tabentry => 'site.key=str:installdir',
                 description => 'The installation directory'},
        {attr_name => 'xcatdport',
                 tabentry => 'site.value',
                 access_tabentry => 'site.key=str:xcatdport',
                 description => 'Port used by xcatd daemon on master'},
             );

#@{$defspec{site}->{'attrs'}} = (
#        {attr_name => 'sitename',
#                 tabentry => 'site.sitename',
#                 access_tabentry => 'site.sitename=attr:sitename',
#                 description => 'Name of this xCAT cluster site definition.'},
#        {attr_name => 'master',
#                 tabentry => 'site.master',
#                 access_tabentry => 'site.sitename=attr:sitename',
#                 description => 'The name of the xCAT management node.'},
#        {attr_name => 'domain',
#                 tabentry => 'site.domain',
#                 access_tabentry => 'site.sitename=attr:sitename',
#                 description => 'The DNS domain name for this cluster.'},
#        {attr_name => 'installdir',
#                 tabentry => 'site.installdir',
#                 access_tabentry => 'site.sitename=attr:sitename',
#                 description => 'The installation directory.'},
#        {attr_name => 'rsh',
#                 tabentry => 'site.rsh',
#                 access_tabentry => 'site.sitename=attr:sitename',
#                 description => 'Specifies the path of the remote shell command to use.'},
#        {attr_name => 'rcp',
#                 tabentry => 'site.rcp',
#                 access_tabentry => 'site.sitename=attr:sitename',
#                 description => 'Specifies the path of the remote copy command to use.'},
#        {attr_name => 'xcatdport',
#                 tabentry => 'site.xcatdport',
#                 access_tabentry => 'site.sitename=attr:sitename',
#                 description => 'The port used by xcatd daemon running on the xCAT management node.'},
#		{attr_name => 'usercomment',
#                 tabentry => 'site.comments',
#                 access_tabentry => 'site.sitename=attr:sitename',
#                description => 'User comment.'},
#             );


#######################
#  groups data object #
#######################
#     groups table    #
#######################
@{$defspec{group}->{'attrs'}} = (
        {attr_name => 'groupname',
                 tabentry => 'nodegroup.groupname',
                 access_tabentry => 'nodegroup.groupname=attr:groupname',
                 },
	{attr_name => 'grouptype',
      		 tabentry => 'nodegroup.grouptype',
		 access_tabentry => 'nodegroup.groupname=attr:groupname',
		 },
        {attr_name => 'members',
                 tabentry => 'nodegroup.members',
                 access_tabentry => 'nodegroup.groupname=attr:groupname',
                 },
	{attr_name => 'wherevals',
                 tabentry => 'nodegroup.wherevals',
                 access_tabentry => 'nodegroup.groupname=attr:groupname',
                 },
	{attr_name => 'usercomment',
                 tabentry => 'nodegroup.comments',
                 access_tabentry => 'nodegroup.groupname=attr:groupname',
                },

###
# TODO:  Need to copy attrs that are common between nodes and static groups
#        Ideas:  make a separate data structure that is linked/copied here.
#                need to figure out the perl dereferencing to make that work.
###
			);

# add on the generic node attrs
push(@{$defspec{group}->{'attrs'}}, @nodeattrs);

#######################
#  policy data object #
#######################
#     policy table    #
#######################
@{$defspec{policy}->{'attrs'}} = (
###
# TODO:  The policy validate subroutine in the xcatd daemon code does not
#        sort the rules in the policy table in priority order before
#        processing.  Talk to Jarrod - I think it should.
###
        {attr_name => 'priority',
                tabentry => 'policy.priority',
                access_tabentry => 'policy.priority=attr:priority',
		},
        {attr_name => 'name',
                 tabentry => 'policy.name',
                 access_tabentry => 'policy.priority=attr:priority',
		},
        {attr_name => 'host',
                 tabentry => 'policy.host',
                 access_tabentry => 'policy.priority=attr:priority',
		},
        {attr_name => 'commands',
                 tabentry => 'policy.commands',
                 access_tabentry => 'policy.priority=attr:priority',
		},
        {attr_name => 'noderange',
                 tabentry => 'policy.noderange',
                 access_tabentry => 'policy.priority=attr:priority',
		},
        {attr_name => 'parameters',
                 tabentry => 'policy.parameters',
                 access_tabentry => 'policy.priority=attr:priority',
		},
        {attr_name => 'time',
                 tabentry => 'policy.time',
                 access_tabentry => 'policy.priority=attr:priority',
		},
        {attr_name => 'rule',
                tabentry => 'policy.rule',
		access_tabentry => 'policy.priority=attr:priority' ,
		},
	{attr_name => 'usercomment',
                 tabentry => 'policy.comments',
                 access_tabentry => 'policy.priority=attr:priority',
                },
             );

#############################
#  notification data object #
#############################
#     notification table    #
#############################
@{$defspec{notification}->{'attrs'}} = (
        {attr_name => 'filename',
                 tabentry => 'notification.filename',
                 access_tabentry => 'notification.filename=attr:filename',
                 },
        {attr_name => 'tables',
                 tabentry => 'notification.tables',
                 access_tabentry => 'notification.filename=attr:filename',
                 },
        {attr_name => 'tableops',
                 tabentry => 'notification.tableops',
                 access_tabentry => 'notification.filename=attr:filename',
                 },
        {attr_name => 'comments',
                 tabentry => 'notification.comments',
                 access_tabentry => 'notification.filename=attr:filename',
                 },
         );

###########################
#  monitoring data object #
###########################
#     monitoring table    #
###########################
@{$defspec{monitoring}->{'attrs'}} = (
        {attr_name => 'name',
                 tabentry => 'monitoring.name',
                 access_tabentry => 'monitoring.name=attr:name',
                 },
        {attr_name => 'nodestatmon',
                 tabentry => 'monitoring.nodestatmon',
                 access_tabentry => 'monitoring.name=attr:name',
                 },
        {attr_name => 'comments',
                 tabentry => 'monitoring.comments',
                 access_tabentry => 'monitoring.name=attr:name',
                 },
);

# Build a corresponding hash for the attribute names to make
# definition access easier
foreach (keys %xCAT::Schema::defspec) {
   my $dataobj = $xCAT::Schema::defspec{$_};
   my $this_attr;
   foreach $this_attr (@{$dataobj->{'attrs'}}){
      $dataobj->{attrhash}->{$this_attr->{attr_name}} = $this_attr;
   }
};
1;

