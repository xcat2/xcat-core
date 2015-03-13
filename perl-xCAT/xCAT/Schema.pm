# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::Schema;
BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : -d '/opt/xcat' ? '/opt/xcat' : '/usr';
}
use lib "$::XCATROOT/lib/perl";
use xCAT::ExtTab;

# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
#
#  When making additions or deletions to this file please be sure to
#       modify BOTH the tabspec and defspec definitions.  This includes
#       adding descriptions for any new attributes.
#
#  Make sure any new attributes are not SQL reserved words by checking
#  on this site:http://www.petefreitag.com/tools/sql_reserved_words_checker/
#  For Postgresql: check the following site for names that cannot be used
#  as attributes under any conditions:
#  http://www.postgresql.org/docs/8.3/static/sql-keywords-appendix.html
#
#  Current SQL reserved words being used in this Schema with special 
#  processing are the
#  following:
#   
#Word     Table                   Databases that will not allow 
# key      site,passwd,prodkey,monsetting      MySQL, DB2,SQL Server 2000
# dump     nimimage                            SQL Server 2000 (microsoft)
# power    nodehm                              SQL Server 2000
# host     policy,ivm                          SQL Server Future Keywords
# parameters  policy              DB2,SQL Server Future Keywords,ISO/ANSI,SQL99
# time        policy              DB2,SQL Server Future Keywords,ISO/ANSI,SQL99
# rule        policy              SQL Server 2000
# value       site,monsetting     ODBC, DB2, SQL Server 
#                                 Future Keywords,ISO/ANSI,SQL99
#
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!


#Note that the SQL is far from imaginative.  Fact of the matter is that
#certain SQL backends don't ascribe meaning to the data types anyway.
#New format, not sql statements, but info enough to describe xcat tables
%tabspec = (
statelite => {
	cols => [qw(node image statemnt mntopts comments disable)],
	keys => [qw(node)],
	required => [qw(node statemnt)],
	table_desc => 'The location on an NFS server where a nodes persistent files are stored.  Any file marked persistent in the litefile table will be stored in the location specified in this table for that node.',
	descriptions => {
		node => 'The name of the node or group that will use this location.',
		image => "Reserved for future development, not used. ",
		statemnt => "The persistant read/write area where a node's persistent files will be written to, e.g: 10.0.0.1/state/.  The node name will be automatically added to the pathname, so 10.0.0.1:/state, will become 10.0.0.1:/state/<nodename>.",
		mntopts => "A comma-separated list of options to use when mounting the persistent directory.  (Ex. 'soft') The default is to do a 'hard' mount. ",
		comments => 'Any user-written notes.',
		disable => "Set to 'yes' or '1' to comment out this row.",
	},
},

#If we support multiple domains managed in a single xCAT instance, the following
#tables come into play.  Given no explicit request to span domains and no effort to
#seriously evaluate wider support of multi-domain environments, will leave them 
#commented rather than tempt people to try with an expectation that it could work.
domain => {
    cols => [qw(node ou authdomain adminuser adminpassword type comments disable)],
    keys => ['node'],
    table_desc => 'Mapping of nodes to domain attributes',
    descriptions => {
        node => 'The node or group the entry applies to',
#        domain => 'The name of the domain it is a member of, such as "example.com".  Defaults to domain value from the site table',
# the above column is unimplemented by anything, so leave it out for this pass
        ou => 'For an LDAP described machine account (i.e. Active Directory), the orginaztional unit to place the system.  If not set, defaults to cn=Computers,dc=your,dc=domain',
	authdomain => 'If a node should participate in an AD domain or Kerberos realm distinct from domain indicated in site, this field can be used to specify that',
	adminuser => 'Allow a node specific indication of Administrative user.  Most will want to just use passwd table to indicate this once rather than by node.',
	adminpassword => 'Allow a node specific indication of Administrative user password for the domain.  Most will want to ignore this in favor of passwd table.',
	type => 'Type, if any, of authentication domain to manipulate.  The only recognized value at the moment is activedirectory.',
		comments => 'Any user-written notes.',
		disable => "Set to 'yes' or '1' to comment out this row.",      
	},
},
###############################################################################
# The next two are for kvm plugin to use to maintain persistent config data
# not feasibly determined from contextual data
###############################################################################
kvm_nodedata => {      
	cols => [qw(node xml comments disable)], 
	keys => [qw(node)],
        required => [qw(node)],
	table_desc => 'Persistant store for KVM plugin, not intended for manual modification.',
    types => {
	xml => 'VARCHAR(16000)',   
    },
	descriptions => {
        node => 'The node corresponding to the virtual machine',
        xml => 'The XML description generated by xCAT, fleshed out by libvirt, and stored for reuse',
	    comments => 'Any user-written notes.',
	    disable => "Set to 'yes' or '1' to comment out this row.",
	},
},
kvm_masterdata => {
    cols => [qw(name xml comments disable)],
    keys => [qw(name)],
    nodecol => 'name', 
    table_desc=>'Persistant store for KVM plugin for masters',
    types => {
        xml => 'VARCHAR(16000)', 
    },
    descriptions => {
        name => 'The name of the relevant master',
        xml => 'The XML description to be customized for clones of this master',
        disable => "Set to 'yes' or '1' to comment out this row.",
    },
},


#domains => {
#    cols => [qw(domain nameserver authserver realm comments disable)],
#    keys => ['domain'],
#    table_desc => 'Parameters concerning domain-wide management',
#    descriptions => {
#        domain => 'The name of the domain, such as "example.com"',
#        nameserver => 'The address of the server that is responsible for updating DNS records',
#        authserver => 'The provider of authentication and authorization data, which may be a generic LDAP server as well as a Kerberos KDC, or specifically an active directory domain controller'.
#        realm => 'The kerberos realm name associated with the domain.  Defaults to uppercase of the domain name',
#		comments => 'Any user-written notes.',
#		disable => "Set to 'yes' or '1' to comment out this row.",      
#	},
#},
        

litetree => {
	cols => [qw(priority image directory mntopts comments disable)],
	keys => [qw(priority)],
	required => [qw(priority directory)],
	table_desc => 'Directory hierarchy to traverse to get the initial contents of node files.  The files that are specified in the litefile table are searched for in the directories specified in this table.',        
	descriptions => {
		priority => 'This number controls what order the directories are searched.  Directories are searched from smallest priority number to largest.',
        image => "The name of the image (as specified in the osimage table) that will use this directory. You can also specify an image group name that is listed in the osimage.groups attribute of some osimages. 'ALL' means use this row for all images.",
		directory => 'The location (hostname:path) of a directory that contains files specified in the litefile table.  Variables are allowed.  E.g: $noderes.nfsserver://xcatmasternode/install/$node/#CMD=uname-r#/',
		mntopts => "A comma-separated list of options to use when mounting the litetree directory.  (Ex. 'soft') The default is to do a 'hard' mount.",
		comments => 'Any user-written notes.',
		disable => "Set to 'yes' or '1' to comment out this row.",      
	},
},

litefile => {
	cols => [qw(image file options comments disable)],
	keys => [qw(image file)],
	required => [qw(image file)], # default type is rw nfsroot   
	table_desc => 'The litefile table specifies the directories and files on the statelite nodes that should be readwrite, persistent, or readonly overlay.  All other files in the statelite nodes come from the readonly statelite image.',        
	descriptions => {
		image => "The name of the image (as specified in the osimage table) that will use these options on this dir/file. You can also specify an image group name that is listed in the osimage.groups attribute of some osimages. 'ALL' means use this row for all images.",
		file => "The full pathname of the file. e.g: /etc/hosts.  If the path is a directory, then it should be terminated with a '/'. ",
		options => "Options for the file:\n\n".
            qq{ tmpfs - It is the default option if you leave the options column blank. It provides a file or directory for the node to use when booting, its permission will be the same as the original version on the server. In most cases, it is read-write; however, on the next statelite boot, the original version of the file or directory on the server will be used, it means it is non-persistent. This option can be performed on files and directories..\n\n}.
            qq{ rw - Same as Above.Its name "rw" does NOT mean it always be read-write, even in most cases it is read-write. Please do not confuse it with the "rw" permission in the file system. \n\n}.
            qq{ persistent - It provides a mounted file or directory that is copied to the xCAT persistent location and then over-mounted on the local file or directory. Anything written to that file or directory is preserved. It means, if the file/directory does not exist at first, it will be copied to the persistent location. Next time the file/directory in the persistent location will be used. The file/directory will be persistent across reboots. Its permission will be the same as the original one in the statelite location. It requires the statelite table to be filled out with a spot for persistent statelite. This option can be performed on files and directories. \n\n}.
            qq{ con - The contents of the pathname are concatenated to the contents of the existing file. For this directive the searching in the litetree hierarchy does not stop when the first match is found. All files found in the hierarchy will be concatenated to the file when found. The permission of the file will be "-rw-r--r--", which means it is read-write for the root user, but readonly for the others. It is non-persistent, when the node reboots, all changes to the file will be lost. It can only be performed on files. Please do not use it for one directory.\n\n}.
            qq{ ro - The file/directory will be overmounted read-only on the local file/directory. It will be located in the directory hierarchy specified in the litetree table. Changes made to this file or directory on the server will be immediately seen in this file/directory on the node. This option requires that the file/directory to be mounted must be available in one of the entries in the litetree table. This option can be performed on files and directories.\n\n}.
            qq{ link - It provides one file/directory for the node to use when booting, it is copied from the server, and will be placed in tmpfs on the booted node. In the local file system of the booted node, it is one symbolic link to one file/directory in tmpfs. And the permission of the symbolic link is "lrwxrwxrwx", which is not the real permission of the file/directory on the node. So for some application sensitive to file permissions, it will be one issue to use "link" as its option, for example, "/root/.ssh/", which is used for SSH, should NOT use "link" as its option. It is non-persistent, when the node is rebooted, all changes to the file/directory will be lost. This option can be performed on files and directories. \n\n}.
            qq{ link,con -  It works similar to the "con" option. All the files found in the litetree hierarchy will be concatenated to the file when found. The final file will be put to the tmpfs on the booted node. In the local file system of the booted node, it is one symbolic link to the file/directory in tmpfs. It is non-persistent, when the node is rebooted, all changes to the file will be lost. The option can only be performed on files. \n\n}.
            qq{  link,persistent - It provides a mounted file or directory that is copied to the xCAT persistent location and then over-mounted to the tmpfs on the booted node, and finally the symbolic link in the local file system will be linked to the over-mounted tmpfs file/directory on the booted node. The file/directory will be persistent across reboots. The permission of the file/directory where the symbolic link points to will be the same as the original one in the statelite location. It requires the statelite table to be filled out with a spot for persistent statelite. The option can be performed on files and directories.\n\n}.
            qq{ link,ro - The file is readonly, and will be placed in tmpfs on the booted node. In the local file system of the booted node, it is one symbolic link to the tmpfs. It is non-persistent, when the node is rebooted, all changes to the file/directory will be lost. This option requires that the file/directory to be mounted must be available in one of the entries in the litetree table. The option can be performed on files and directories.},
		comments => 'Any user-written notes.',
		disable => "Set to 'yes' or '1' to comment out this row.",
        }
},

vmmaster => {
#will add columns as approriate, for now:
#os arch profile to populate the corresponding nodetype fields of a cloned vm
#storage to indicate where the master data is actually stored (i.e. virtual disk images)
#storagemodel to allow chvm on a clone to be consistent with the master by default
#nics to track the network mapping that may not be preserved by the respective plugin's specific cfg info
#nicmodel same as storagemodel, except omitting for now until chvm actually does nics...
    cols => [qw(name os arch profile storage storagemodel nics vintage originator virttype specializeparameters comments disable)],
    keys => [qw(name)],
    nodecol => 'name', #well what do you know, I used it...
    table_desc => 'Inventory of virtualization images for use with clonevm.  Manual intervention in this table is not intended.',
    descriptions => {
        'name' => 'The name of a master',
        'os' => 'The value of nodetype.os at the time the master was captured',
        'arch' => 'The value of nodetype.arch at the time of capture',
        'profile' => 'The value of nodetype.profile at time of capture',
        'storage' => 'The storage location of bulk master information',
        'storagemodel' => 'The default storage style to use when modifying a vm cloned from this master',
        'nics' => 'The nic configuration and relationship to vlans/bonds/etc',
        'vintage' => "When this image was created",
        'originator' => 'The user who created the image',
	'specializeparameters' => 'Implementation specific arguments, currently only "autoLogonCount=<number" for ESXi clonevme',
        'virttype' => 'The type of virtualization this image pertains to (e.g. vmware, kvm, etc)',
    }
},
vm => {
    cols => [qw(node mgr host migrationdest storage storagemodel storagecache storageformat cfgstore memory cpus nics nicmodel bootorder clockoffset virtflags master vncport textconsole powerstate beacon datacenter cluster guestostype othersettings physlots vidmodel vidproto vidpassword comments disable)],
    keys => [qw(node)],
    tablespace =>'XCATTBS32K',
    table_desc => 'Virtualization parameters',
    descriptions => {
        'node' => 'The node or static group name',
        'mgr' => 'The function manager for the virtual machine',
        'host' => 'The system that currently hosts the VM',
        'migrationdest' => 'A noderange representing candidate destinations for migration (i.e. similar systems, same SAN, or other criteria that xCAT can use',
        'storage' => 'A list of storage files or devices to be used.  i.e. dir:///cluster/vm/<nodename> or nfs://<server>/path/to/folder/',
        'storagemodel' => 'Model of storage devices to provide to guest',
        'cfgstore' => 'Optional location for persistant storage separate of emulated hard drives for virtualization solutions that require persistant store to place configuration data',
        'memory' => 'Megabytes of memory the VM currently should be set to.',
        'master' => 'The name of a master image, if any, this virtual machine is linked to.  This is generally set by clonevm and indicates the deletion of a master that would invalidate the storage of this virtual machine',
        'cpus' => 'Number of CPUs the node should see.',
        'nics' => 'Network configuration parameters.  Of the general form [physnet:]interface,.. Generally, interface describes the vlan entity (default for native, tagged for tagged, vl[number] for a specific vlan.  physnet is a virtual switch name or port description that is used for some virtualization technologies to construct virtual switches.  hypervisor.netmap can map names to hypervisor specific layouts, or the descriptions described there may be used directly here where possible.',
        'nicmodel' => 'Model of NICs that will be provided to VMs (i.e. e1000, rtl8139, virtio, etc)',
        'bootorder' => 'Boot sequence (i.e. net,hd)',
        'clockoffset' => 'Whether to have guest RTC synced to "localtime" or "utc"  If not populated, xCAT will guess based on the nodetype.os contents.',
        'virtflags' => 'General flags used by the virtualization method.  For example, in Xen it could, among other things, specify paravirtualized setup, or direct kernel boot.  For a hypervisor/dom0 entry, it is the virtualization method (i.e. "xen").  For KVM, the following flag=value pairs are recognized:
            imageformat=[raw|fullraw|qcow2]
                raw is a generic sparse file that allocates storage on demand
                fullraw is a generic, non-sparse file that preallocates all space
                qcow2 is a sparse, copy-on-write capable format implemented at the virtualization layer rather than the filesystem level
            clonemethod=[qemu-img|reflink]
                qemu-img allows use of qcow2 to generate virtualization layer copy-on-write
                reflink uses a generic filesystem facility to clone the files on your behalf, but requires filesystem support such as btrfs 
            placement_affinity=[migratable|user_migratable|pinned]',
        'vncport' => 'Tracks the current VNC display port (currently not meant to be set',
        'textconsole' => 'Tracks the Psuedo-TTY that maps to the serial port or console of a VM',
        'powerstate' => "This flag is used by xCAT to track the last known power state of the VM.",
        'othersettings' => "This allows specifying a semicolon delimited list of key->value pairs to include in a vmx file of VMware. For partitioning on normal power machines, this option is used to specify the hugepage and/or bsr information, the value is like:'hugepage:1,bsr=2'.",
        'guestostype' => "This allows administrator to specify an identifier for OS to pass through to virtualization stack.  Normally this should be ignored as xCAT will translate from nodetype.os rather than requiring this field be used\n",
        'beacon' => "This flag is used by xCAT to track the state of the identify LED with respect to the VM.",
        'datacenter' => "Optionally specify a datacenter for the VM to exist in (only applicable to VMWare)",
        'cluster' => 'Specify to the underlying virtualization infrastructure a cluster membership for the hypervisor.',
	'vidproto' => "Request a specific protocol for remote video access be set up.  For example, spice in KVM.",
    'physlots' => "Specify the physical slots drc index that will assigned to the partition, the delimiter is ',', and the drc index must started with '0x'. For more details, please reference to manpage of 'lsvm'.",
	'vidmodel' => "Model of video adapter to provide to guest.  For example, qxl in KVM",
	'vidpassword' => "Password to use instead of temporary random tokens for VNC and SPICE access",
    'storagecache' => "Select caching scheme to employ.  E.g. KVM understands 'none', 'writethrough' and 'writeback'",
    'storageformat' => "Select disk format to use by default (e.g. raw versus qcow2)",
    }
},
hypervisor => {
        cols => [qw(node type mgr interface netmap defaultnet cluster datacenter preferdirect comments disable)],
        keys => [qw(node)],
        table_desc => 'Hypervisor parameters',
        descriptions => {
            'node' => 'The node or static group name',
            'type' => 'The plugin associated with hypervisor specific commands such as revacuate',
            'mgr' => 'The virtualization specific manager of this hypervisor when applicable',
            'interface' => 'The definition of interfaces for the hypervisor. The format is [networkname:interfacename:bootprotocol:IP:netmask:gateway] that split with | for each interface',
            'netmap' => 'Optional mapping of useful names to relevant physical ports.  For example, 10ge=vmnic_16.0&vmnic_16.1,ge=vmnic1 would be requesting two virtual switches to be created, one called 10ge with vmnic_16.0 and vmnic_16.1 bonded, and another simply connected to vmnic1.  Use of this allows abstracting guests from network differences amongst hypervisors',
            'defaultnet' => 'Optionally specify a default network entity for guests to join to if they do not specify.',
            'cluster' => 'Specify to the underlying virtualization infrastructure a cluster membership for the hypervisor.',
            'datacenter' => 'Optionally specify a datacenter for the hypervisor to exist in (only applicable to VMWare)',
            'preferdirect' => 'If a mgr is declared for a hypervisor, xCAT will default to using the mgr for all operations.  If this is field is set to yes or 1, xCAT will prefer to directly communicate with the hypervisor if possible'
        }
},
virtsd => {
        cols => [qw(node sdtype stype location host cluster datacenter comments disable)],
        keys => [qw(node)],
        table_desc => 'The parameters which used to create the Storage Domain',
        descriptions => {
            'node' => 'The name of the storage domain',
            'sdtype' => 'The type of storage domain. Valid values: data, iso, export',
            'stype' => 'The type of storge. Valid values: nfs, fcp, iscsi, localfs',
            'location' => 'The path of the storage',
            'host' => 'For rhev, a hypervisor host needs to be specified to manage the storage domain as SPM (Storage Pool Manager). But the SPM role will be failed over to another host when this host down.',
            'cluster' => 'A cluster of hosts',
            'datacenter' => 'A collection for all host, vm that will shared the same storages, networks.',
        }
},

storage => {
    cols => [qw(node osvolume size state storagepool hypervisor fcprange volumetag type controller comments disable)],
    keys => [qw(node)],
    table_descr => 'Node storage resources',
    descriptions => {
        node => 'The node name',
        controller => 'The management address to attach/detach new volumes.
                       In the scenario involving multiple controllers, this data must be
                       passed as argument rather than by table value',
        osvolume => "Specification of what storage to place the node OS image onto.  Examples include:
                localdisk (Install to first non-FC attached disk)
                usbdisk (Install to first USB mass storage device seen)
                wwn=0x50000393c813840c (Install to storage device with given WWN)",
        size => 'Size of the volume. Examples include: 10G, 1024M.',
        state => 'State of the volume. The valid values are: free, used, and allocated',
        storagepool => 'Name of storage pool where the volume is assigned.',
        hypervisor => 'Name of the hypervisor where the volume is configured.',
        fcprange => 'A range of acceptable fibre channels that the volume can use. Examples include: 3B00-3C00;4B00-4C00.',
        type => 'The plugin used to drive storage configuration (e.g. svc)',
        volumetag => 'A specific tag used to identify the volume in the autoyast or kickstart template.',
        comments => 'Any user-written notes.',
        disable => "Set to 'yes' or '1' to comment out this row.",
    }
},
websrv => { 
    cols => [qw(node port username password comments disable)],
    keys => [qw(node)],
    table_desc => 'Web service parameters',
	descriptions => {
		'node' => 'The web service hostname.',
		'port' => 'The port of the web service.',
		'username' => 'Userid to use to access the web service.',
		'password' => 'Password to use to access the web service.',
		'comments' => 'Any user-written notes.',
		'disable' => "Set to 'yes' or '1' to comment out this row.",
	 },
  },
boottarget => {
   cols => [qw(bprofile kernel initrd kcmdline comments disable)],
   keys => [qw(bprofile)],
   table_desc => 'Specify non-standard initrd, kernel, and parameters that should be used for a given profile.',
   descriptions => {
      'bprofile' => 'All nodes with a nodetype.profile value equal to this value and nodetype.os set to "boottarget", will use the associated kernel, initrd, and kcmdline.',
      'kernel' => 'The kernel that network boot actions should currently acquire and use.  Note this could be a chained boot loader such as memdisk or a non-linux boot loader',
      'initrd' => 'The initial ramdisk image that network boot actions should use (could be a DOS floppy or hard drive image if using memdisk as kernel)',
      'kcmdline' => 'Arguments to be passed to the kernel',
      comments => 'Any user-written notes.',
      disable => "Set to 'yes' or '1' to comment out this row."
    }
},
bootparams => {
   cols => [qw(node kernel initrd kcmdline addkcmdline dhcpstatements adddhcpstatements comments disable)],
   keys => [qw(node)],
   tablespace =>'XCATTBS16K',
   table_desc => 'Current boot settings to be sent to systems attempting network boot for deployment, stateless, or other reasons.  Mostly automatically manipulated by xCAT.',
   descriptions => {
      'node' => 'The node or group name',
      'kernel' => 'The kernel that network boot actions should currently acquire and use.  Note this could be a chained boot loader such as memdisk or a non-linux boot loader',
      'initrd' => 'The initial ramdisk image that network boot actions should use (could be a DOS floppy or hard drive image if using memdisk as kernel)',
      'kcmdline' => 'Arguments to be passed to the kernel',
      'addkcmdline' => 'User specified one or more parameters to be passed to the kernel',
      'dhcpstatements' => 'xCAT manipulated custom dhcp statements (not intended for user manipulation)',
      'adddhcpstatements' => 'Custom dhcp statements for administrator use (not implemneted yet)',
     comments => 'Any user-written notes.',
     disable => "Set to 'yes' or '1' to comment out this row.",
   }
},
prodkey => {
    cols => [qw(node product key comments disable)],
    keys => [qw(node product)],
    table_desc => 'Specify product keys for products that require them',
    descriptions => {
        node => "The node name or group name.",
        product => "A string to identify the product (for OSes, the osname would be used, i.e. wink28",
        key => "The product key relevant to the aforementioned node/group and product combination",
     comments => 'Any user-written notes.',
     disable => "Set to 'yes' or '1' to comment out this row.",
    }
},
chain => {
    cols => [qw(node currstate currchain chain ondiscover comments disable)],
    keys => [qw(node)],
    table_desc => 'Controls what operations are done (and it what order) when a node is discovered and deployed.',
 descriptions => {
  node => 'The node name or group name.',
  currstate => 'The current or next chain step to be executed on this node by xCAT-genesis.  Set by xCAT during node discovery or as a result of nodeset.',
  currchain => 'The chain steps still left to do for this node.  This attribute will be automatically adjusted by xCAT while xCAT-genesis is running on the node (either during node discovery or a special operation like firmware update).  During node discovery, this attribute is initialized from the chain attribute and updated as the chain steps are executed.',
  chain => 'A comma-delimited chain of actions to be performed automatically when this node is discovered. ("Discovered" means a node booted, but xCAT and DHCP did not recognize the MAC of this node. In this situation, xCAT initiates the discovery process, the last step of which is to run the operations listed in this chain attribute, one by one.) Valid values:  boot or reboot, install or netboot, runcmd=<cmd>, runimage=<URL>, shell, standby. (Default - same as no chain - it will do only the discovery.).  Example, for BMC machines use: runcmd=bmcsetup,shell.',
  ondiscover => 'This attribute is currently not used by xCAT.  The "nodediscover" operation is always done during node discovery.',
     comments => 'Any user-written notes.',
     disable => "Set to 'yes' or '1' to comment out this row.",
 },
  },
deps => {
    cols => [qw(node nodedep msdelay cmd comments disable)],
    keys => [qw(node cmd)],
    required => [qw(node cmd)],
    table_desc => 'Describes dependencies some nodes have on others.  This can be used, e.g., by rpower -d to power nodes on or off in the correct order.',
 descriptions => {
  node => 'The node name or group name.',
  nodedep => 'Comma-separated list of nodes or node groups it is dependent on.',
  msdelay => 'How long to wait between operating on the dependent nodes and the primary nodes.',
  cmd => 'Comma-seperated list of which operation this dependency applies to.',
     comments => 'Any user-written notes.',
     disable => "Set to 'yes' or '1' to comment out this row.",
 },
  },
hosts => {
    cols => [qw(node ip hostnames otherinterfaces comments disable)],
    keys => [qw(node)],
    table_desc => 'IP addresses and hostnames of nodes.  This info is optional and is only used to populate /etc/hosts and DNS via makehosts and makedns.  Using regular expressions in this table can be a quick way to populate /etc/hosts.',
 descriptions => {
  node => 'The node name or group name.',
  ip => 'The IP address of the node. This is only used in makehosts.  The rest of xCAT uses system name resolution to resolve node names to IP addresses.',
  hostnames => 'Hostname aliases added to /etc/hosts for this node. Comma or blank separated list.',
  otherinterfaces => 'Other IP addresses to add for this node.  Format: -<ext>:<ip>,<intfhostname>:<ip>,...',
     comments => 'Any user-written notes.',
     disable => "Set to 'yes' or '1' to comment out this row.",
 },
  },
ipmi => {
    cols => [qw(node bmc bmcport taggedvlan bmcid username password comments disable )],
    keys => [qw(node)],
    table_desc => 'Settings for nodes that are controlled by an on-board BMC via IPMI.',
 descriptions => {
  node => 'The node name or group name.',
  bmc => 'The hostname of the BMC adapater.',
  bmcport => ' In systems with selectable shared/dedicated ethernet ports,
           this parameter can be used to specify the preferred port.  0
           means use the shared port, 1 means dedicated, blank is to not
           assign.

           The following special cases exist for IBM System x servers:

           For x3755 M3 systems, 0 means use the dedicated port, 1 means
           shared, blank is to not assign.

       For certain systems which have a mezzaine or ML2 adapter, there is a second
       value to include:


           For x3750 M4 (Model 8722):


           0 2   1st 1Gbps interface for LOM

           0 0   1st 10Gbps interface for LOM

           0 3   2nd 1Gbps interface for LOM

           0 1   2nd 10Gbps interface for LOM


           For  x3750 M4 (Model 8752), x3850/3950 X6, dx360 M4, x3550 M4, and x3650 M4:


           0     Shared (1st onboard interface)

           1     Dedicated

           2 0   First interface on ML2 or mezzanine adapter

           2 1   Second interface on ML2 or mezzanine adapter

           2 2   Third interface on ML2 or mezzanine adapter

           2 3   Fourth interface on ML2 or mezzanine adapter',
  taggedvlan => 'Have bmcsetup place the BMC on the specified vlan tag on a shared netwirk interface.  Some network devices may be incompatible with this option',
  bmcid => 'Unique identified data used by discovery processes to distinguish known BMCs from unrecognized BMCs',
  username => 'The BMC userid.  If not specified, the key=ipmi row in the passwd table is used as the default.',
  password => 'The BMC password.  If not specified, the key=ipmi row in the passwd table is used as the default.',
     comments => 'Any user-written notes.',
     disable => "Set to 'yes' or '1' to comment out this row.",
 },
  },
iscsi => {
    cols => [qw(node server target lun iname file userid passwd kernel kcmdline initrd comments disable)],
    keys => [qw(node)],
    tablespace =>'XCATTBS16K',
    table_desc => 'Contains settings that control how to boot a node from an iSCSI target',
 descriptions => {
  node => 'The node name or group name.',
  server => 'The server containing the iscsi boot device for this node.',
  target => 'The iscsi disk used for the boot device for this node.  Filled in by xCAT.',
  lun => 'LUN of boot device.  Per RFC-4173, this is presumed to be 0 if unset.  tgtd often requires this to be 1',
  iname => 'Initiator name.  Currently unused.',
  file => 'The path on the server of the OS image the node should boot from.',
  userid => 'The userid of the iscsi server containing the boot device for this node.',
  passwd => 'The password for the iscsi server containing the boot device for this node.',
  kernel => 'The path of the linux kernel to boot from.',
  kcmdline => 'The kernel command line to use with iSCSI for this node.',
  initrd => 'The initial ramdisk to use when network booting this node.',
     comments => 'Any user-written notes.',
     disable => "Set to 'yes' or '1' to comment out this row.",
 },
  },
mac => {
    cols => [qw(node interface mac comments disable)],
    keys => [qw(node)],
    tablespace =>'XCATTBS16K',
    table_desc => "The MAC address of the node's install adapter.  Normally this table is populated by getmacs or node discovery, but you can also add entries to it manually.",
 descriptions => {
  node => 'The node name or group name.',
  interface => 'The adapter interface name that will be used to install and manage the node. E.g. eth0 (for linux) or en0 (for AIX).)',
  mac => 'The mac address or addresses for which xCAT will manage static bindings for this node.  This may be simply a mac address, which would be bound to the node name (such as "01:02:03:04:05:0E").  This may also be a "|" delimited string of "mac address!hostname" format (such as "01:02:03:04:05:0E!node5|01:02:03:05:0F!node6-eth1").',
     comments => 'Any user-written notes.',
     disable => "Set to 'yes' or '1' to comment out this row.",
 },
  },
monitoring => {
    cols => [qw(name nodestatmon comments disable)],
    keys => [qw(name)],
    required => [qw(name)],
    table_desc => 'Controls what external monitoring tools xCAT sets up and uses.  Entries should be added and removed from this table using the provided xCAT commands monstart and monstop.',
 descriptions => {
  name => "The name of the mornitoring plug-in module.  The plug-in must be put in $ENV{XCATROOT}/lib/perl/xCAT_monitoring/.  See the man page for monstart for details.",
  nodestatmon => 'Specifies if the monitoring plug-in is used to feed the node status to the xCAT cluster.  Any one of the following values indicates "yes":  y, Y, yes, Yes, YES, 1.  Any other value or blank (default), indicates "no".',
  comments => 'Any user-written notes.',
  disable => "Set to 'yes' or '1' to comment out this row.",
 },
  },
monsetting => {
    cols => [qw(name key value comments disable)],
    keys => [qw(name key)],
    required => [qw(name key)],
    table_desc => 'Specifies the monitoring plug-in specific settings. These settings will be used by the monitoring plug-in to customize the behavior such as event filter, sample interval, responses etc. Entries should be added, removed or modified by chtab command. Entries can also be added or modified by the monstart command when a monitoring plug-in is brought up.',
 descriptions => {
  name => "The name of the mornitoring plug-in module.  The plug-in must be put in $ENV{XCATROOT}/lib/perl/xCAT_monitoring/.  See the man page for monstart for details.",
  key => 'Specifies the name of the attribute. The valid values are specified by each monitoring plug-in. Use "monls name -d" to get a list of valid keys.',
  value => 'Specifies the value of the attribute.',
  comments => 'Any user-written notes.',
  disable => "Set to 'yes' or '1' to comment out this row.",
 },
  },
mp => {
    cols => [qw(node mpa id nodetype comments disable)],
    keys => [qw(node)],
    table_desc => 'Contains the hardware control info specific to blades.  This table also refers to the mpa table, which contains info about each Management Module.',
 descriptions => {
  node => 'The blade node name or group name.',
  mpa => 'The managment module used to control this blade.',
  id => 'The slot number of this blade in the BladeCenter chassis.',
  nodetype => 'The hardware type for mp node. Valid values: mm,cmm, blade.',
  comments => 'Any user-written notes.',
  disable => "Set to 'yes' or '1' to comment out this row.",
 },
  },
mpa => {
    cols => [qw(mpa username password displayname slots urlpath comments disable)],
	keys => [qw(mpa username)],
    nodecol => "mpa",
    table_desc => 'Contains info about each Management Module and how to access it.',
 descriptions => {
  mpa => 'Hostname of the management module.',
  username => 'Userid to use to access the management module.',
  password => 'Password to use to access the management module.  If not specified, the key=blade row in the passwd table is used as the default.',
  displayname => 'Alternative name for BladeCenter chassis. Only used by PCM.',
  slots => 'The number of available slots in the chassis. For PCM, this attribute is used to store the number of slots in the following format:  <slot rows>,<slot columns>,<slot orientation>  Where:
   <slot rows>  = number of rows of slots in chassis
   <slot columns> = number of columns of slots in chassis
   <slot orientation> = set to 0 if slots are vertical, and set to 1 if slots of horizontal
',
  urlpath => 'URL path for the Chassis web interface. The full URL is built as follows: <hostname>/<urlpath> ',
     comments => 'Any user-written notes.',
     disable => "Set to 'yes' or '1' to comment out this row.",
 },
  },
networks => {
    cols => [qw(netname net mask mgtifname gateway dhcpserver tftpserver nameservers ntpservers logservers dynamicrange staticrange staticrangeincrement nodehostname ddnsdomain vlanid domain  comments disable)],
    keys => [qw(net mask)],
    tablespace =>'XCATTBS16K',
    table_desc => 'Describes the networks in the cluster and info necessary to set up nodes on that network.',
 descriptions => {
  netname => 'Name used to identify this network definition.',
  net => 'The network address.',
  mask => 'The network mask.',
  mgtifname => 'The interface name of the management/service node facing this network.  !remote!<nicname> indicates a non-local network on a specific nic for relay DHCP.',
  gateway => 'The network gateway. It can be set to an ip address or the keyword <xcatmaster>, the keyword <xcatmaster> indicates the cluster-facing ip address configured on this management node or service node. Leaving this field blank means that there is no gateway for this network.',
  dhcpserver => 'The DHCP server that is servicing this network.  Required to be explicitly set for pooled service node operation.',
  tftpserver => 'The TFTP server that is servicing this network.  If not set, the DHCP server is assumed.',
  nameservers => 'A comma delimited list of DNS servers that each node in this network should use. This value will end up in the nameserver settings of the /etc/resolv.conf on each node in this network. If this attribute value is set to the IP address of an xCAT node, make sure DNS is running on it. In a hierarchical cluster, you can also set this attribute to "<xcatmaster>" to mean the DNS server for each node in this network should be the node that is managing it (either its service node or the management node).  Used in creating the DHCP network definition, and DNS configuration.',
  ntpservers => 'The ntp servers for this network.  Used in creating the DHCP network definition.  Assumed to be the DHCP server if not set.',
  logservers => 'The log servers for this network.  Used in creating the DHCP network definition.  Assumed to be the DHCP server if not set.',
  dynamicrange => 'The IP address range used by DHCP to assign dynamic IP addresses for requests on this network.  This should not overlap with entities expected to be configured with static host declarations, i.e. anything ever expected to be a node with an address registered in the mac table.',
  staticrange => 'The IP address range used to dynamically assign static IPs to newly discovered nodes.  This should not overlap with the dynamicrange nor overlap with entities that were manually assigned static IPs.  The format for the attribute value is:    <startip>-<endip>.',
  statusrangeincrement=> 'The increment value used when getting the next available IP in the staticrange.',
  nodehostname => 'A regular expression used to specify node name to network-specific hostname.  i.e. "/\z/-secondary/" would mean that the hostname of "n1" would be n1-secondary on this network.  By default, the nodename is assumed to equal the hostname, followed by nodename-interfacename.',
  ddnsdomain => 'A domain to be combined with nodename to construct FQDN for DDNS updates induced by DHCP.  This is not passed down to the client as "domain"',
  vlanid => 'The vlan ID if this network is within a vlan.',
  domain => 'The DNS domain name (ex. cluster.com).',
     comments => 'Any user-written notes.',
     disable => "Set to 'yes' or '1' to comment out this row.",
 },
  },
nodegroup => {
 cols => [qw(groupname grouptype members membergroups  wherevals comments disable)],
 keys => [qw(groupname)],
    table_desc => 'Contains group definitions, whose membership is dynamic depending on characteristics of the node.',
 descriptions => {
  groupname => 'Name of the group.',
  grouptype => 'The only current valid value is dynamic.  We will be looking at having the object def commands working with static group definitions in the nodelist table.',
  members => 'The value of the attribute is not used, but the attribute is necessary as a place holder for the object def commands.  (The membership for static groups is stored in the nodelist table.)',
  membergroups => 'This attribute stores a comma-separated list of nodegroups that this nodegroup refers to. This attribute is only used by PCM.',
  wherevals => 'A list of "attr*val" pairs that can be used to determine the members of a dynamic group, the delimiter is "::" and the operator * can be ==, =~, != or !~.',
     comments => 'Any user-written notes.',
     disable => "Set to 'yes' or '1' to comment out this row.",
 },
  },
nodehm => {
    cols => [qw(node power mgt cons termserver termport conserver serialport serialspeed serialflow getmac cmdmapping consoleondemand comments disable)],
    keys => [qw(node)],
    tablespace =>'XCATTBS16K',
    table_desc => "Settings that control how each node's hardware is managed.  Typically, an additional table that is specific to the hardware type of the node contains additional info.  E.g. the ipmi, mp, and ppc tables.",
 descriptions => {
  node => 'The node name or group name.',
  power => 'The method to use to control the power of the node. If not set, the mgt attribute will be used.  Valid values: ipmi, blade, hmc, ivm, fsp, kvm, esx, rhevm.  If "ipmi", xCAT will search for this node in the ipmi table for more info.  If "blade", xCAT will search for this node in the mp table.  If "hmc", "ivm", or "fsp", xCAT will search for this node in the ppc table.',
  mgt => 'The method to use to do general hardware management of the node.  This attribute is used as the default if power or getmac is not set.  Valid values: ipmi, blade, hmc, ivm, fsp, bpa, kvm, esx, rhevm.  See the power attribute for more details.',
  cons => 'The console method. If nodehm.serialport is set, this will default to the nodehm.mgt setting, otherwise it defaults to unused.  Valid values: cyclades, mrv, or the values valid for the mgt attribute.',
  termserver => 'The hostname of the terminal server.',
  termport => 'The port number on the terminal server that this node is connected to.',
  conserver => 'The hostname of the machine where the conserver daemon is running.  If not set, the default is the xCAT management node.',
  serialport => 'The serial port for this node, in the linux numbering style (0=COM1/ttyS0, 1=COM2/ttyS1).  For SOL on IBM blades, this is typically 1.  For rackmount IBM servers, this is typically 0.',
  serialspeed => 'The speed of the serial port for this node.  For SOL this is typically 19200.',
  serialflow => "The flow control value of the serial port for this node.  For SOL this is typically 'hard'.",
  getmac => 'The method to use to get MAC address of the node with the getmac command. If not set, the mgt attribute will be used.  Valid values: same as values for mgmt attribute.',
  cmdmapping => 'The fully qualified name of the file that stores the mapping between PCM hardware management commands and xCAT/third-party hardware management commands for a particular type of hardware device.  Only used by PCM.',
  consoleondemand => 'This overrides the value from site.consoleondemand; (0=no, 1=yes). Default is the result from site.consoleondemand.',
     comments => 'Any user-written notes.',
     disable => "Set to 'yes' or '1' to comment out this row.",
 },
  },
nodelist => {
    cols => [qw(node groups status statustime appstatus appstatustime primarysn hidden updatestatus updatestatustime zonename comments disable)],
    keys => [qw(node)],
    tablespace =>'XCATTBS32K',
    table_desc => "The list of all the nodes in the cluster, including each node's current status and what groups it is in.",
    descriptions => {
     node => 'The hostname of a node in the cluster.',
     groups => "A comma-delimited list of groups this node is a member of.  Group names are arbitrary, except all nodes should be part of the 'all' group. Internal group names are designated by using __<groupname>.  For example, __Unmanaged, could be the internal name for a group of nodes that is not managed by xCAT. Admins should avoid using the __ characters when defining their groups.",
     status => 'The current status of this node.  This attribute will be set by xCAT software.  Valid values: defined, booting, netbooting, booted, discovering, configuring, installing, alive, standingby, powering-off, unreachable. If blank, defined is assumed. The possible status change sequenses are: For installaton: defined->[discovering]->[configuring]->[standingby]->installing->booting->booted->[alive],  For diskless deployment: defined->[discovering]->[configuring]->[standingby]->netbooting->booted->[alive],  For booting: [alive/unreachable]->booting->[alive],  For powering off: [alive]->powering-off->[unreachable], For monitoring: alive->unreachable. Discovering and configuring are for x Series dicovery process. Alive and unreachable are set only when there is a monitoring plug-in start monitor the node status for xCAT. Please note that the status values will not reflect the real node status if you change the state of the node from outside of xCAT (i.e. power off the node using HMC GUI).',
     statustime => "The data and time when the status was updated.",
     appstatus => "A comma-delimited list of application status. For example: 'sshd=up,ftp=down,ll=down'",
     appstatustime =>'The date and time when appstatus was updated.',
     primarysn => 'Not used currently. The primary servicenode, used by this node.',
     hidden => "Used to hide fsp and bpa definitions, 1 means not show them when running lsdef and nodels",
     updatestatus => "The current node update status. Valid states are synced, out-of-sync,syncing,failed.",
     updatestatustime => "The date and time when the updatestatus was updated.",
     zonename => "The name of the zone to which the node is currently assigned. If undefined, then it is not assigned to any zone. ",
     comments => 'Any user-written notes.',
     disable => "Set to 'yes' or '1' to comment out this row.",
    },
  },
nodepos => {
    cols => [qw(node rack u chassis slot room height comments disable)],
    keys => [qw(node)],
    tablespace =>'XCATTBS16K',
    table_desc => 'Contains info about the physical location of each node.  Currently, this info is not used by xCAT, and therefore can be in whatevery format you want.  It will likely be used in xCAT in the future.',
 descriptions => {
  node => 'The node name or group name.',
  rack => 'The frame the node is in.',
  u => 'The vertical position of the node in the frame',
  chassis => 'The BladeCenter chassis the blade is in.',
  slot => 'The slot number of the blade in the chassis. For PCM, a comma-separated list of slot numbers is stored',
  room => 'The room where the node is located.',
  height => 'The server height in U(s).',
     comments => 'Any user-written notes.',
     disable => "Set to 'yes' or '1' to comment out this row.",
 },
  },
noderes => {
    cols => [qw(node servicenode netboot tftpserver tftpdir nfsserver monserver nfsdir installnic primarynic discoverynics cmdinterface xcatmaster current_osimage next_osimage nimserver routenames nameservers proxydhcp comments disable)],
    keys => [qw(node)],
    tablespace =>'XCATTBS16K',
    table_desc => 'Resources and settings to use when installing nodes.',
 descriptions => {
  node => 'The node name or group name.',
  servicenode => 'A comma separated list of node names (as known by the management node) that provides most services for this node. The first service node on the list that is accessible will be used.  The 2nd node on the list is generally considered to be the backup service node for this node when running commands like snmove.',
  netboot => 'The type of network booting to use for this node.  Valid values:  pxe or xnba for x86* architecture, yaboot for POWER architecture, grub2-tftp and grub2-http for RHEL7 on Power and all the os deployment on Power LE. Notice: yaboot is not supported from rhels7 on Power,use grub2-tftp or grub2-http instead, the difference between the 2 is the file transfer protocol(i.e, http or tftp)',
  tftpserver => 'The TFTP server for this node (as known by this node). If not set, it defaults to networks.tftpserver.',
  tftpdir => 'The directory that roots this nodes contents from a tftp and related perspective.  Used for NAS offload by using different mountpoints.',
  nfsserver => 'The NFS or HTTP server for this node (as known by this node).',
  monserver => 'The monitoring aggregation point for this node. The format is "x,y" where x is the ip address as known by the management node and y is the ip address as known by the node.',
  nfsdir => 'The path that should be mounted from the NFS server.',
  installnic => 'The network adapter on the node that will be used for OS deployment, the installnic can be set to the network adapter name or the mac address or the keyword "mac" which means that the network interface specified by the mac address in the mac table will be used.  If not set, primarynic will be used. If primarynic is not set too, the keyword "mac" will be used as default.',
  primarynic => 'This attribute will be deprecated. All the used network interface will be determined by installnic. The network adapter on the node that will be used for xCAT management, the primarynic can be set to the network adapter name or the mac address or the keyword "mac" which means that the network interface specified by the mac address in the mac table  will be used.  Default is eth0.',
  discoverynics => 'If specified, force discovery to occur on specific network adapters only, regardless of detected connectivity.  Syntax can be simply "eth2,eth3" to restrict discovery to whatever happens to come up as eth2 and eth3, or by driver name such as "bnx2:0,bnx2:1" to specify the first two adapters managed by the bnx2 driver',
  cmdinterface => 'Not currently used.',
  xcatmaster => 'The hostname of the xCAT service node (as known by this node).  This acts as the default value for nfsserver and tftpserver, if they are not set.  If xcatmaster is not set, the node will use whoever responds to its boot request as its master.  For the directed bootp case for POWER, it will use the management node if xcatmaster is not set.',
  current_osimage => 'Not currently used.  The name of the osimage data object that represents the OS image currently deployed on this node.',
  next_osimage => 'Not currently used.  The name of the osimage data object that represents the OS image that will be installed on the node the next time it is deployed.',
  nimserver => 'Not used for now. The NIM server for this node (as known by this node).',
  routenames => 'A comma separated list of route names that refer to rows in the routes table. These are the routes that should be defined on this node when it is deployed.',
  nameservers => 'An optional node/group specific override for name server list.  Most people want to stick to site or network defined nameserver configuration.',
  proxydhcp => 'To specify whether the node supports proxydhcp protocol. Valid values: yes or 1, no or 0. Default value is yes.',
  comments => 'Any user-written notes.',
  disable => "Set to 'yes' or '1' to comment out this row.",
 },
  },
    switches => {
        cols => [qw(switch snmpversion username password privacy auth linkports sshusername sshpassword protocol switchtype comments disable)],
        keys => [qw(switch)],
        nodecol => "switch",
        table_desc => 'Parameters to use when interrogating switches',
        descriptions => {
         switch => 'The hostname/address of the switch to which the settings apply',
         snmpversion => 'The version to use to communicate with switch.  SNMPv1 is assumed by default.',
         username => 'The username to use for SNMPv3 communication, ignored for SNMPv1',
         password => 'The password or community string to use for SNMPv3 or SNMPv1 respectively.  Falls back to passwd table, and site snmpc value if using SNMPv1',
         privacy => 'The privacy protocol to use for v3.  DES is assumed if v3 enabled, as it is the most readily available.',
         auth => 'The authentication protocol to use for SNMPv3.  SHA is assumed if v3 enabled and this is unspecified',
         linkports => 'The ports that connect to other switches. Currently, this column is only used by vlan configuration. The format is: "port_number:switch,port_number:switch...". Please refer to the switch table for details on how to specify the port numbers.',
        sshusername => 'The remote login user name. It can be for ssh or telnet. If it is for telnet, please set protocol to "telnet".',
        sshpassword => 'The remote login password. It can be for ssh or telnet. If it is for telnet, please set protocol to "telnet".',
        protocol => 'Prorocol for running remote commands for the switch. The valid values are: ssh, telnet. ssh is the default. Leave it blank or set to "ssh" for Mellanox IB switch.',
        switchtype => 'The type of switch. It is used to identify the file name that implements the functions for this swithc. The valid values are: MellanoxIB etc.',
	},
    },
nodetype => {
    cols => [qw(node os arch profile provmethod supportedarchs nodetype comments disable)],
    keys => [qw(node)],
    tablespace =>'XCATTBS16K',
    table_desc => 'A few hardware and software characteristics of the nodes.',
 descriptions => {
  node => 'The node name or group name.',
  os => 'The operating system deployed on this node.  Valid values: AIX, rhels*,rhelc*, rhas*,centos*,SL*, fedora*, sles* (where * is the version #). As a special case, if this is set to "boottarget", then it will use the initrd/kernel/parameters specified in the row in the boottarget table in which boottarget.bprofile equals nodetype.profile.',
  arch => 'The hardware architecture of this node.  Valid values: x86_64, ppc64, x86, ia64.',
  profile => 'The string to use to locate a kickstart or autoyast template to use for OS deployment of this node.  If the provmethod attribute is set to an osimage name, that takes precedence, and profile need not be defined.  Otherwise, the os, profile, and arch are used to search for the files in /install/custom first, and then in /opt/xcat/share/xcat.',
  provmethod => 'The provisioning method for node deployment. The valid values are install, netboot, statelite or an os image name from the osimage table. If an image name is specified, the osimage definition stored in the osimage table and the linuximage table (for Linux) or nimimage table (for AIX) are used to locate the files for templates, pkglists, syncfiles, etc. On Linux, if install, netboot or statelite is specified, the os, profile, and arch are used to search for the files in /install/custom first, and then in /opt/xcat/share/xcat.',
  supportedarchs => 'Comma delimited list of architectures this node can execute.',
  nodetype => 'A comma-delimited list of characteristics of this node.  Valid values: ppc, blade, vm (virtual machine), osi (OS image), mm, mn, rsa, switch.',
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
osimage => {
 cols => [qw(imagename groups profile imagetype description provmethod rootfstype osdistroname osupdatename cfmdir osname osvers osarch synclists postscripts postbootscripts serverrole isdeletable kitcomponents  comments disable)],
 keys => [qw(imagename)],
 tablespace =>'XCATTBS32K',
 table_desc => 'Basic information about an operating system image that can be used to deploy cluster nodes.',
 types => {
	osupdatename => 'VARCHAR(1024)',   
 },
 descriptions => {
  imagename => 'The name of this xCAT OS image definition.',
  groups => 'A comma-delimited list of image groups of which this image is a member.  Image groups can be used in the litefile and litetree table instead of a single image name. Group names are arbitrary.',
  imagetype => 'The type of operating system image this definition represents (linux,AIX).',
  description => 'OS Image Description',
  provmethod => 'The provisioning method for node deployment. The valid values are install, netboot,statelite,boottarget,dualboot,sysclone. If boottarget is set, you must set linuximage.boottarget to the name of the boottarget definition. It is not used by AIX.',
  rootfstype => 'The filesystem type for the rootfs is used when the provmethod is statelite. The valid values are nfs or ramdisk. The default value is nfs',
  osdistroname => 'The name of the OS distro definition.  This attribute can be used to specify which OS distro to use, instead of using the osname,osvers,and osarch attributes. For *kit commands,  the attribute will be used to read the osdistro table for the osname, osvers, and osarch attributes. If defined, the osname, osvers, and osarch attributes defined in the osimage table will be ignored.',
  osupdatename => 'A comma-separated list of OS distro updates to apply to this osimage.',
  cfmdir => 'CFM directory name for PCM. Set to /install/osimages/<osimage name>/cfmdir by PCM. ',
  profile => 'The node usage category. For example compute, service.',
  osname => 'Operating system name- AIX or Linux.',
  osvers => 'The Linux operating system deployed on this node.  Valid values:  rhels*,rhelc*, rhas*,centos*,SL*, fedora*, sles* (where * is the version #).',
  osarch => 'The hardware architecture of this node.  Valid values: x86_64, ppc64, x86, ia64.',
  synclists => 'The fully qualified name of a file containing a list of files to synchronize on the nodes. Can be a comma separated list of multiple synclist files. The synclist generated by PCM named /install/osimages/<imagename>/synclist.cfm is reserved for use only by PCM and should not be edited by the admin.',
  postscripts => 'Comma separated list of scripts that should be run on this image after diskfull installation or diskless boot. For installation of RedHat, CentOS, Fedora, the scripts will be run before the reboot. For installation of SLES, the scripts will be run after the reboot but before the init.d process. For diskless deployment, the scripts will be run at the init.d time, and xCAT will automatically add the list of scripts from the postbootscripts attribute to run after postscripts list. For installation of AIX, the scripts will run after the reboot and acts the same as the postbootscripts attribute.  For AIX, use the postbootscripts attribute. See the site table runbootscripts attribute. Support will be added in the future for  the postscripts attribute to run the scripts before the reboot in AIX. ',
  postbootscripts => 'Comma separated list of scripts that should be run on this after diskfull installation or diskless boot. On AIX these scripts are run during the processing of /etc/inittab.  On Linux they are run at the init.d time. xCAT automatically adds the scripts in the xcatdefaults.postbootscripts attribute to run first in the list. See the site table runbootscripts attribute.',
  serverrole => 'The role of the server created by this osimage.  Default roles: mgtnode, servicenode, compute, login, storage, utility.',
  isdeletable => 'A flag to indicate whether this image profile can be deleted.  This attribute is only used by PCM.',
  kitcomponents => 'List of Kit Component IDs assigned to this OS Image definition.',
  comments => 'Any user-written notes.',
  disable => "Set to 'yes' or '1' to comment out this row.",
 },
  },
linuximage  => {
 cols => [qw(imagename template boottarget addkcmdline pkglist pkgdir otherpkglist otherpkgdir exlist postinstall rootimgdir kerneldir nodebootif otherifce netdrivers kernelver krpmver permission dump crashkernelsize partitionfile driverupdatesrc comments disable)],
 keys => [qw(imagename)],
 tablespace =>'XCATTBS32K',
 table_desc => 'Information about a Linux operating system image that can be used to deploy cluster nodes.',
 descriptions => {
  imagename => 'The name of this xCAT OS image definition.',
  template => 'The fully qualified name of the template file that will be used to create the OS installer configuration file for stateful installations (e.g.  kickstart for RedHat, autoyast for SLES).',
  boottarget => 'The name of the boottarget definition.  When this attribute is set, xCAT will use the kernel, initrd and kernel params defined in the boottarget definition instead of the default.',
   addkcmdline=> 'User specified arguments to be passed to the kernel.  The user arguments are appended to xCAT.s default kernel arguments.   This attribute is ignored if linuximage.boottarget is set.',
  pkglist => 'The fully qualified name of the file that stores the distro  packages list that will be included in the image. Make sure that if the pkgs in the pkglist have dependency pkgs, the dependency pkgs should be found in one of the pkgdir',
  pkgdir => 'The name of the directory where the distro packages are stored. It could be set multiple paths.The multiple paths must be seperated by ",". The first path in the value of osimage.pkgdir must be the OS base pkg dir path, such as pkgdir=/install/rhels6.2/x86_64,/install/updates . In the os base pkg path, there are default repository data. And in the other pkg path(s), the users should make sure there are repository data. If not, use "createrepo" command to create them. For ubuntu, multiple mirrors can be specified in the pkgdir attribute, the mirrors must be prefixed by the protocol(http/ssh) and delimited with "," between each other.',
  otherpkglist => 'The fully qualified name of the file that stores non-distro package lists that will be included in the image. It could be set multiple paths.The multiple paths must be seperated by ",".',
  otherpkgdir => 'The base directory where the non-distro packages are stored. Only 1 local directory supported at present.', 
  exlist => 'The fully qualified name of the file that stores the file names and directory names that will be excluded from the image during packimage command.  It is used for diskless image only.',
  postinstall => 'The fully qualified name of the script file that will be run at the end of the genimage command. It could be set multiple paths.The multiple paths must be seperated by ",". It is used for diskless image only.',
  rootimgdir => 'The directory name where the image is stored.  It is generally used for diskless image. it also can be used in sysclone environment to specify where the image captured from golden client is stored. in sysclone environment, rootimgdir is generally assigned to some default value by xcat, but you can specify your own store directory. just one thing need to be noticed, wherever you save the image, the name of last level directory must be the name of image. for example, if your image name is testimage and you want to save this image under home directoy, rootimgdir should be assigned to value /home/testimage/',
  kerneldir => 'The directory name where the 3rd-party kernel is stored. It is used for diskless image only.',
  nodebootif => 'The network interface the stateless/statelite node will boot over (e.g. eth0)',
  otherifce => 'Other network interfaces (e.g. eth1) in the image that should be configured via DHCP',
  netdrivers => 'The ethernet device drivers of the nodes which will use this linux image, at least the device driver for the nodes\' installnic should be included',
  kernelver => 'The version of linux kernel used in the linux image. If the kernel version is not set, the default kernel in rootimgdir will be used',
  krpmver => 'The rpm version of kernel packages (for SLES only). If it is not set, the default rpm version of kernel packages will be used.',
  permission => 'The mount permission of /.statelite directory is used, its default value is 755',
  dump => qq{The NFS directory to hold the Linux kernel dump file (vmcore) when the node with this image crashes, its format is "nfs://<nfs_server_ip>/<kdump_path>". If you want to use the node's "xcatmaster" (its SN or MN), <nfs_server_ip> can be left blank. For example, "nfs:///<kdump_path>" means the NFS directory to hold the kernel dump file is on the node's SN, or MN if there's no SN.},
  crashkernelsize => 'the size that assigned to the kdump kernel. If the kernel size is not set, 256M will be the default value.',
  partitionfile => 'The path of the configuration file which will be used to partition the disk for the node. For stateful osimages,two types of files are supported: "<partition file absolute path>" which contains a partitioning definition that will be inserted directly into the generated autoinst configuration file and must be formatted for the corresponding OS installer (e.g. kickstart for RedHat, autoyast for SLES).  "s:<partitioning script absolute path>" which specifies a shell script that will be run from the OS installer configuration file %pre section;  the script must write the correct partitioning definition into the file /tmp/partitionfile on the node which will be included into the configuration file during the install process. For statelite osimages, partitionfile should specify "<partition file absolute path>";  see the xCAT Statelite documentation for the xCAT defined format of this configuration file.',
  driverupdatesrc => 'The source of the drivers which need to be loaded during the boot. Two types of driver update source are supported: Driver update disk and Driver rpm package. The value for this attribute should be comma separated sources. Each source should be the format tab:full_path_of_srouce_file. The tab keyword can be: dud (for Driver update disk) and rpm (for driver rpm). If missing the tab, the rpm format is the default. e.g. dud:/install/dud/dd.img,rpm:/install/rpm/d.rpm',
  comments => 'Any user-written notes.',
  disable => "Set to 'yes' or '1' to comment out this row.",
 },
  },
winimage => {
 cols => [qw(imagename template installto partitionfile winpepath comments disable)],
 keys => [qw(imagename)],
 tablespace =>'XCATTBS32K',
 table_desc => 'Information about a Windows operating system image that can be used to deploy cluster nodes.',
 descriptions => {
  imagename => 'The name of this xCAT OS image definition.',
  template => 'The fully qualified name of the template file that is used to create the windows unattend.xml file for diskful installation.',
  installto => 'The disk and partition that the Windows will be deployed to. The valid format is <disk>:<partition>. If not set, default value is 0:1 for bios boot mode(legacy) and 0:3 for uefi boot mode; If setting to 1, it means 1:1 for bios boot and 1:3 for uefi boot',
  partitionfile => 'The path of partition configuration file. Since the partition configuration for bios boot mode and uefi boot mode are different, this configuration file can include both configurations if you need to support both bios and uefi mode. Either way, you must specify the boot mode in the configuration. Example of partition configuration file: [BIOS]xxxxxxx[UEFI]yyyyyyy. To simplify the setting, you also can set installto in partitionfile with section like [INSTALLTO]0:1',
  winpepath => 'The path of winpe which will be used to boot this image. If the real path is /tftpboot/winboot/winpe1/, the value for winpepath should be set to winboot/winpe1',
  comments => 'Any user-written notes.',
  disable => "Set to 'yes' or '1' to comment out this row.",
 }
},
passwd => {
    cols => [qw(key username password cryptmethod authdomain comments disable)],
    keys => [qw(key username)],
    table_desc => 'Contains default userids and passwords for xCAT to access cluster components.  In most cases, xCAT will also actually set the userid/password in the relevant component when it is being configured or installed.  Userids/passwords for specific cluster components can be overidden in other tables, e.g. mpa, ipmi, ppchcp, etc.',
 descriptions => {
  key => 'The type of component this user/pw is for.  Valid values: blade (management module), ipmi (BMC), system (nodes), omapi (DHCP), hmc, ivm, cec, frame, switch.',
  username => 'The default userid for this type of component',
  password => 'The default password for this type of component',
  cryptmethod => 'Indicates the method that was used to encrypt the password attribute.  On AIX systems, if a value is provided for this attribute it indicates that the password attribute is encrypted.  If the cryptmethod value is not set it indicates the password is a simple string value. On Linux systems, the cryptmethod is not supported however the code attempts to auto-discover MD5 encrypted passwords.',
   authdomain => 'The domain in which this entry has meaning, e.g. specifying different domain administrators per active directory domain',
     comments => 'Any user-written notes.',
     disable => "Set to 'yes' or '1' to comment out this row.",
 },
  },
policy => {
    cols => [qw(priority name host commands noderange parameters time rule comments disable)],
    keys => [qw(priority)],
    table_desc => 'The policy table in the xCAT database controls who has authority to run specific xCAT operations. It is basically the Access Control List (ACL) for xCAT. It is sorted on the priority field before evaluating.',
 descriptions => {
  priority => 'The priority value for this rule.  This value is used to identify this policy data object (i.e. this rule) The table is sorted on this field with the lower the number the higher the priority. For example 1.0 is higher priority than 4.1 is higher than 4.9.',
  name => 'The username that is allowed to perform the commands specified by this rule.  Default is "*" (all users).',
  host => 'The host from which users may issue the commands specified by this rule.  Default is "*" (all hosts). Only all or one host is supported',
  commands => 'The list of commands that this rule applies to.  Default is "*" (all commands).',
  noderange => 'The Noderange that this rule applies to.  Default is "*" (all nodes). Not supported with the *def commands.',
  parameters => 'A regular expression that matches the command parameters (everything except the noderange) that this rule applies to.  Default is "*" (all parameters). Not supported with the *def commands.',
  time => 'Time ranges that this command may be executed in.  This is not supported.',
  rule => 'Specifies how this rule should be applied.  Valid values are: allow, accept, trusted. Allow or accept  will allow the user to run the commands. Any other value will deny the user access to the commands. Trusted means that once this client has been authenticated via the certificate, all other information that is sent (e.g. the username) is believed without question.  This authorization should only be given to the xcatd on the management node at this time.',
     comments => 'Any user-written notes.',
     disable => "Set to 'yes' or '1' to comment out this row.",
 },
  },
postscripts => {
    cols => [qw(node postscripts postbootscripts comments disable)],
    keys => [qw(node)],
    tablespace =>'XCATTBS16K',
    table_desc => 'The scripts that should be run on each node after installation or diskless boot.',
 descriptions => {
  node => 'The node name or group name.',
  postscripts => 'Comma separated list of scripts that should be run on this node after diskfull installation or diskless boot. Each script can take zero or more parameters. For example: "script1 p1 p2,script2,...". xCAT automatically adds the postscripts from  the xcatdefaults.postscripts attribute of the table to run first on the nodes after install or diskless boot. For installation of RedHat, CentOS, Fedora, the scripts will be run before the reboot. For installation of SLES, the scripts will be run after the reboot but before the init.d process. For diskless deployment, the scripts will be run at the init.d time, and xCAT will automatically add the list of scripts from the postbootscripts attribute to run after postscripts list. For installation of AIX, the scripts will run after the reboot and acts the same as the postbootscripts attribute.  For AIX, use the postbootscripts attribute. Support will be added in the future for  the postscripts attribute to run the scripts before the reboot in AIX. ',
  postbootscripts => 'Comma separated list of scripts that should be run on this node after diskfull installation or diskless boot. Each script can take zero or more parameters. For example: "script1 p1 p2,script2,...". On AIX these scripts are run during the processing of /etc/inittab.  On Linux they are run at the init.d time. xCAT automatically adds the scripts in the xcatdefaults.postbootscripts attribute to run first in the list.',
    comments => 'Any user-written notes.',
     disable => "Set to 'yes' or '1' to comment out this row.",
 },
  },
ppc => {
    cols => [qw(node hcp id pprofile parent nodetype supernode sfp comments disable)],
    keys => [qw(node)],
    tablespace =>'XCATTBS16K',
    table_desc => 'List of system p hardware: HMCs, IVMs, FSPs, BPCs, CECs, Frames.',
 descriptions => {
  node => 'The node name or group name.',
  hcp => 'The hardware control point for this node (HMC, IVM, Frame or CEC).  Do not need to set for BPAs and FSPs.',
  id => 'For LPARs: the LPAR numeric id; for CECs: the cage number; for Frames: the frame number.',
  pprofile => 'The LPAR profile that will be used the next time the LPAR is powered on with rpower. For DFM, the pprofile attribute should be set to blank ',
  parent => 'For LPARs: the CEC; for FSPs: the CEC; for CEC: the frame (if one exists); for BPA: the frame; for frame: the building block number (which consists 1 or more service nodes and compute/storage nodes that are serviced by them - optional).',
  nodetype => 'The hardware type of the node. Only can be one of fsp, bpa, cec, frame, ivm, hmc and lpar',
  supernode => 'Indicates the connectivity of this CEC in the HFI network. A comma separated list of 2 ids. The first one is the supernode number the CEC is part of. The second one is the logical location number (0-3) of this CEC within the supernode.',
  sfp => 'The Service Focal Point of this Frame. This is the name of the HMC that is responsible for collecting hardware service events for this frame and all of the CECs within this frame.',
     comments => 'Any user-written notes.',
     disable => "Set to 'yes' or '1' to comment out this row.",
 },
  },
ppcdirect => {
    cols => [qw(hcp username password comments disable)],
    keys => [qw(hcp username)],
    nodecol => "hcp",
    table_desc => 'Info necessary to use FSPs/BPAs to control system p CECs/Frames.',
 descriptions => {
  hcp => 'Hostname of the FSPs/BPAs(for ASMI) and CECs/Frames(for DFM).',
  username => 'Userid of the FSP/BPA(for ASMI) and CEC/Frame(for DFM).  If not filled in, xCAT will look in the passwd table for key=fsp.  If not in the passwd table, the default used is admin.',
  password => 'Password of the FSP/BPA(for ASMI) and CEC/Frame(for DFM).  If not filled in, xCAT will look in the passwd table for key=fsp.  If not in the passwd table, the default used is admin.',
     comments => 'Any user-written notes.',
     disable => "Set to 'yes' or '1' to comment out this row.",
 },
  },
ppchcp => {
    cols => [qw(hcp username password comments disable)],
    keys => [qw(hcp)],
    nodecol => "hcp",
    table_desc => 'Info necessary to use HMCs and IVMs as hardware control points for LPARs.',
 descriptions => {
  hcp => 'Hostname of the HMC or IVM.',
  username => 'Userid of the HMC or IVM.  If not filled in, xCAT will look in the passwd table for key=hmc or key=ivm.  If not in the passwd table, the default used is hscroot for HMCs and padmin for IVMs.',
  password => 'Password of the HMC or IVM.  If not filled in, xCAT will look in the passwd table for key=hmc or key=ivm.  If not in the passwd table, the default used is abc123 for HMCs and padmin for IVMs.',
     comments => 'Any user-written notes.',
     disable => "Set to 'yes' or '1' to comment out this row.",
 },
  },
servicenode => {
    cols => [qw(node nameserver dhcpserver tftpserver nfsserver conserver monserver ldapserver ntpserver ftpserver nimserver ipforward dhcpinterfaces proxydhcp comments disable)],
    keys => [qw(node)],
    tablespace =>'XCATTBS16K',
    table_desc => 'List of all Service Nodes and services that will be set up on the Service Node.',
 descriptions => {
  node => 'The hostname of the service node as known by the Management Node.',
  nameserver => 'Do we set up DNS on this service node? Valid values: 2, 1, no or 0. If 2, creates named.conf as dns slave, using the management node as dns master, and starts named. If 1, creates named.conf file with forwarding to the management node and starts named. If no or 0, it does not change the current state of the service. ',
  dhcpserver => 'Do we set up DHCP on this service node? Not supported on AIX. Valid values:yes or 1, no or 0. If yes, runs makedhcp -n. If no or 0, it does not change the current state of the service. ',
  tftpserver => 'Do we set up TFTP on this service node? Not supported on AIX. Valid values:yes or 1, no or 0. If yes, configures and starts atftp. If no or 0, it does not change the current state of the service. ',
  nfsserver => 'Do we set up file services (HTTP,FTP,or NFS) on this service node? For AIX will only setup NFS, not HTTP or FTP. Valid values:yes or 1, no or 0.If no or 0, it does not change the current state of the service. ',
  conserver => 'Do we set up Conserver on this service node?  Valid values:yes or 1, no or 0. If yes, configures and starts conserver daemon. If no or 0, it does not change the current state of the service.',
  monserver => 'Is this a monitoring event collection point? Valid values:yes or 1, no or 0. If no or 0, it does not change the current state of the service.',
  ldapserver => 'Do we set up ldap caching proxy on this service node? Not supported on AIX.  Valid values:yes or 1, no or 0. If no or 0, it does not change the current state of the service.',
  ntpserver => 'Not used. Use setupntp postscript to setup a ntp server on this service node? Valid values:yes or 1, no or 0. If no or 0, it does not change the current state of the service.',
  ftpserver => 'Do we set up a ftp server on this service node? Not supported on AIX Valid values:yes or 1, no or 0. If yes, configure and start vsftpd.  (You must manually install vsftpd on the service nodes before this.) If no or 0, it does not change the current state of the service. xCAT is not using ftp for compute nodes provisioning or any other xCAT features, so this attribute can be set to 0 if the ftp service will not be used for other purposes',
  nimserver => 'Not used. Do we set up a NIM server on this service node? Valid values:yes or 1, no or 0. If no or 0, it does not change the current state of the service.',
  ipforward => 'Do we set up ip forwarding on this service node? Valid values:yes or 1, no or 0. If no or 0, it does not change the current state of the service.',
  dhcpinterfaces => 'The network interfaces DHCP server should listen on for the target node. This attribute can be used for management node and service nodes.  If defined, it will override the values defined in site.dhcpinterfaces. This is a comma separated list of device names. !remote! indicates a non-local network for relay DHCP. For example: !remote!,eth0,eth1',
  proxydhcp => 'Do we set up proxydhcp service on this node? valid values: yes or 1, no or 0. If yes, the proxydhcp daemon will be enabled on this node.',

     comments => 'Any user-written notes.',
     disable => "Set to 'yes' or '1' to comment out this row.",
 },
  },
site => {
    cols => [qw(key value comments disable)],
    keys => [qw(key)],
    table_desc => "Global settings for the whole cluster.  This table is different from the \nother tables in that each attribute is just named in the key column, rather \nthan having a separate column for each attribute. The following is a list of \nattributes currently used by xCAT organized into categories.\n",
 descriptions => {
  # Do not put description text past column 88, so it displays well in a 100 char wide window.
  # ----------------------------------------------------------------------------------|----------
  key => "Attribute Name:  Description\n\n".
   " ------------\n".
   "AIX ATTRIBUTES\n".
   " ------------\n".
   " nimprime :   The name of NIM server, if not set default is the AIX MN.
              If Linux MN, then must be set for support of mixed cluster (TBD).\n\n".
   " useSSHonAIX:  (yes/1 or no/0). Default is yes.  The support for rsh/rcp is deprecated.\n".
   " useNFSv4onAIX:  (yes/1 or no/0). If yes, NFSv4 will be used with NIM. If no,\n".
   "               NFSv3 will be used with NIM. Default is no.\n\n".
   " -----------------\n".
   "DATABASE ATTRIBUTES\n".
   " -----------------\n".
   " auditnosyslog: If set to 1, then commands will only be written to the auditlog table.\n".
   "                This attribute set to 1 and auditskipcmds=ALL means no logging of commands.\n".
   "                Default is to write to both the auditlog table and syslog.\n".
   " auditskipcmds: List of commands and/or client types that will not be\n".
   "                written to the auditlog table and syslog. See auditnosyslog.\n".
   "                'ALL' means all cmds will be skipped. If attribute is null, all\n".
   "                commands will be written.\n". 
   "                clienttype:web would skip all commands from the web client\n". 
   "                For example: tabdump,nodels,clienttype:web \n".
   "                will not log tabdump,nodels and any web client commands.\n\n".
   " databaseloc:    Directory where we create the db instance directory.\n".
   "                 Default is /var/lib. Only DB2 is currently supported.\n".
   "                 Do not use the directory in the site.installloc or\n".
   "                 installdir attribute. This attribute must not be changed\n".
   "                 once db2sqlsetup script has been run and DB2 has been setup.\n\n".
   " excludenodes:  A set of comma separated nodes and/or groups that would automatically\n".
   "                be subtracted from any noderange, it can be used for excluding some\n".
   "                failed nodes for any xCAT commands. See the 'noderange' manpage for\n".
   "                details on supported formats.\n\n".
   " nodestatus:  If set to 'n', the nodelist.status column will not be updated during\n".
   "              the node deployment, node discovery and power operations. The default is to update.\n\n".
   " skiptables:  Comma separated list of tables to be skipped by dumpxCATdb\n\n".
   " skipvalidatelog:  If set to 1, then getcredentials and getpostscripts calls will not be logged in syslog.\n\n".
   " -------------\n".
   "DHCP ATTRIBUTES\n".
   " -------------\n".
   " dhcpinterfaces:  The network interfaces DHCP should listen on.  If it is the same\n".
   "                  for all nodes, use a simple comma-separated list of NICs.  To\n".
   "                  specify different NICs for different nodes:\n".
   "                       xcatmn|eth1,eth2;service|bond0.\n".
   "                  In this example xcatmn is the name of the xCAT MN, and DHCP there\n".
   "                  should listen on eth1 and eth2.  On all of the nodes in group\n".
   "                  'service' DHCP should listen on the bond0 nic.\n\n".
   " dhcpsetup:  If set to 'n', it will skip the dhcp setup process in the nodeset cmd.\n\n".
   " dhcplease:  The lease time for the dhcp client. The default value is 43200.\n\n".
   " disjointdhcps:  If set to '1', the .leases file on a service node only contains\n".
   "                 the nodes it manages. The default value is '0'.\n".
   "                 '0' value means include all the nodes in the subnet.\n\n".
   " pruneservices:  Whether to enable service pruning when noderm is run (i.e.\n".
   "                 removing DHCP entries when noderm is executed)\n\n".
   " managedaddressmode: The mode of networking configuration during node provision.\n".
   "                     If set to 'static', the network configuration will be configured \n".
   "                     in static mode based on the node and network definition on MN.\n".
   "                     If set to 'dhcp', the network will be configured with dhcp protocol.\n".
   "                     The default is 'dhcp'.\n\n".
   " ------------\n".
   "DNS ATTRIBUTES\n".
   " ------------\n".
   " dnshandler:  Name of plugin that handles DNS setup for makedns.\n".
   " domain:  The DNS domain name used for the cluster.\n\n".
   " forwarders:  The DNS servers at your site that can provide names outside of the\n".
   "              cluster. The makedns command will configure the DNS on the management\n".
   "              node to forward requests it does not know to these servers.\n".
   "              Note that the DNS servers on the service nodes will ignore this value\n".
   "              and always be configured to forward requests to the management node.\n\n".
   " master:  The hostname of the xCAT management node, as known by the nodes.\n\n".
   " nameservers:  A comma delimited list of DNS servers that each node in the cluster\n".
   "               should use. This value will end up in the nameserver settings of the\n".
   "               /etc/resolv.conf on each node. It is common (but not required) to set\n".
   "               this attribute value to the IP addr of the xCAT management node, if\n".
   "               you have set up the DNS on the management node by running makedns.\n".
   "               In a hierarchical cluster, you can also set this attribute to\n".
   "               \"<xcatmaster>\" to mean the DNS server for each node should be the\n".
   "               node that is managing it (either its service node or the management\n".
   "               node).\n\n".
   " externaldns:  To specify that external dns is used. If externaldns is set to any value\n".
   "               then, makedns command will not start the local nameserver on xCAT MN. \n".
   "               Default is to start the local nameserver.\n\n".
   " dnsupdaters:  The value are \',\' separated string which will be added to the zone config\n".
   "               section. This is an interface for user to add configuration entries to\n". 
   "               the zone sections in named.conf.\n\n".
   " dnsinterfaces:  The network interfaces DNS server should listen on.  If it is the same\n".
   "                  for all nodes, use a simple comma-separated list of NICs.  To\n".
   "                  specify different NICs for different nodes:\n".
   "                       xcatmn|eth1,eth2;service|bond0.\n".
   "                  In this example xcatmn is the name of the xCAT MN, and DNS there\n".
   "                  should listen on eth1 and eth2.  On all of the nodes in group\n".
   "                  'service' DNS should listen on the bond0 nic.\n".
   "                  NOTE: if using this attribute to block certain interfaces, make sure\n".
   "                  the ip maps to your hostname of xCAT MN is not blocked since xCAT needs to\n".
   "                  use this ip to communicate with the local NDS server on MN.\n\n".
   " -------------------------\n".
   "HARDWARE CONTROL ATTRIBUTES\n".
   " -------------------------\n".
   " blademaxp:  The maximum number of concurrent processes for blade hardware control.\n\n".
   " ea_primary_hmc:  The hostname of the HMC that the Integrated Switch Network\n".
   "                  Management Event Analysis should send hardware serviceable\n".
   "                  events to for processing and potentially sending to IBM.\n\n".
   " ea_backup_hmc:  The hostname of the HMC that the Integrated Switch Network\n".
   "                  Management Event Analysis should send hardware serviceable\n".
   "                  events to if the primary HMC is down.\n\n".
   " enableASMI:  (yes/1 or no/0). If yes, ASMI method will be used after fsp-api. If no,\n".
   "               when fsp-api is used, ASMI method will not be used. Default is no.\n\n".
   " fsptimeout:  The timeout, in milliseconds, to use when communicating with FSPs.\n\n".
   " hwctrldispatch:  Whether or not to send hw control operations to the service\n".
   "                  node of the target nodes. Default is 'y'.(At present, this attribute\n".
   "                  is only used for IBM Flex System)\n\n".
   " ipmidispatch:  Whether or not to send ipmi hw control operations to the service\n".
   "                node of the target compute nodes. Default is 'y'.\n\n".
   " ipmimaxp:  The max # of processes for ipmi hw ctrl. The default is 64. Currently,\n".
   "            this is only used for HP hw control.\n\n".
   " ipmiretries:  The # of retries to use when communicating with BMCs. Default is 3.\n\n".
   " ipmisdrcache:  If set to 'no', then the xCAT IPMI support will not cache locally\n".
   "                the target node's SDR cache to improve performance.\n\n".
   " ipmitimeout:  The timeout to use when communicating with BMCs. Default is 2.\n".
   "               This attribute is currently not used.\n\n".
   " maxssh:  The max # of SSH connections at any one time to the hw ctrl point for PPC\n".
   "          This parameter doesn't take effect on the rpower command.\n".
   "          It takes effects on other PPC hardware control command\n".
   "          getmacs/rnetboot/rbootseq and so on. Default is 8.\n\n".
   " syspowerinterval:  For system p CECs, this is the number of seconds the rpower\n".
   "                 command will wait between performing the action for each CEC.\n".
   "                 For system x IPMI servers, this is the number of seconds the\n".
   "                 rpower command will wait between powering on <syspowermaxnodes>\n".
   "                 nodes at a time.  This value is used to control the power on speed\n".
   "                 in large clusters. Default is 0.\n\n".
   " syspowermaxnodes:  The number of servers to power on at one time before waiting\n".
   "                    'syspowerinterval' seconds to continue on to the next set of\n".
   "                    nodes.  If the noderange given to rpower includes nodes served\n".
   "                    by different service nodes, it will try to spread each set of\n".
   "                    nodes across the service nodes evenly. Currently only used for\n".
   "                    IPMI servers and must be set if 'syspowerinterval' is set.\n\n".
   " powerinterval:  The number of seconds the rpower command to LPARs will wait between\n".
   "                 performing the action for each LPAR. LPARs of different HCPs\n".
   "                 (HMCs or FSPs) are done in parallel. This is used to limit the\n".
   "                 cluster boot up speed in large clusters. Default is 0.  This is\n".
   "                 currently only used for system p hardware.\n\n".
   " ppcmaxp:  The max # of processes for PPC hw ctrl. If there are more than ppcmaxp\n".
   "           hcps, this parameter will take effect. It will control the max number of\n".
   "           processes for PPC hardware control commands. Default is 64.\n\n".
   " ppcretry:  The max # of PPC hw connection attempts to HMC before failing.\n".
   "           It only takes effect on the hardware control commands through HMC. \n".
   "           Default is 3.\n\n".
   " ppctimeout:  The timeout, in milliseconds, to use when communicating with PPC hw\n".
   "              through HMC. It only takes effect on the hardware control commands\n".
   "              through HMC. Default is 0.\n\n".
   " snmpc:  The snmp community string that xcat should use when communicating with the\n".
   "         switches.\n\n".
   " ---------------------------\n".
   "INSTALL/DEPLOYMENT ATTRIBUTES\n".
   " ---------------------------\n".
   " cleanupxcatpost:  (yes/1 or no/0). Set to 'yes' or '1' to clean up the /xcatpost\n".
   "                   directory on the stateless and statelite nodes after the\n".
   "                   postscripts are run. Default is no.\n\n".
   " db2installloc:  The location which the service nodes should mount for\n".
   "                 the db2 code to install. Format is hostname:/path.  If hostname is\n".
   "                 omitted, it defaults to the management node. Default is /mntdb2.\n\n".
   " defserialflow:  The default serial flow - currently only used by the mknb command.\n\n".
   " defserialport:  The default serial port - currently only used by mknb.\n\n".
   " defserialspeed:  The default serial speed - currently only used by mknb.\n\n".
   " genmacprefix:  When generating mac addresses automatically, use this manufacturing\n".
   "                prefix (e.g. 00:11:aa)\n\n".
   " genpasswords:  Automatically generate random passwords for BMCs when configuring\n".
   "                them.\n\n".
   " installdir:  The local directory name used to hold the node deployment packages.\n\n".
   " installloc:  The location from which the service nodes should mount the \n".
   "              deployment packages in the format hostname:/path.  If hostname is\n".
   "              omitted, it defaults to the management node. The path must\n".
   "              match the path in the installdir attribute.\n\n".
   " iscsidir:  The path to put the iscsi disks in on the mgmt node.\n\n".
   " mnroutenames:  The name of the routes to be setup on the management node.\n".
   "                It is a comma separated list of route names that are defined in the\n".
   "                routes table.\n\n".
   " runbootscripts:  If set to 'yes' the scripts listed in the postbootscripts\n".
   "                  attribute in the osimage and postscripts tables will be run during\n".
   "                  each reboot of stateful (diskful) nodes. This attribute has no\n".
   "                  effect on stateless and statelite nodes. Please run the following\n" .
   "                  command after you change the value of this attribute: \n".
   "                  'updatenode <nodes> -P setuppostbootscripts'\n\n".
   " precreatemypostscripts: (yes/1 or no/0). Default is no. If yes, it will  \n".
   "              instruct xCAT at nodeset and updatenode time to query the db once for\n".
   "              all of the nodes passed into the cmd and create the mypostscript file\n".
   "              for each node, and put them in a directory of tftpdir(such as: /tftpboot)\n".
   "              If no, it will not generate the mypostscript file in the tftpdir.\n\n".
   " setinstallnic:  Set the network configuration for installnic to be static.\n\n".
   " sharedtftp:  Set to 0 or no, xCAT should not assume the directory\n".
   "              in tftpdir is mounted on all on Service Nodes. Default is 1/yes.\n". 
   "              If value is set to a hostname, the directory in tftpdir\n".
   "              will be mounted from that hostname on the SN\n\n". 
   " sharedinstall: Indicates if a shared file system will be used for installation\n". 
   "               resources. Possible values are: 'no', 'sns', or 'all'.  'no' \n".
   "               means a shared file system is not being used.  'sns' means a\n".
   "               shared filesystem is being used across all service nodes.\n".
   "               'all' means that the management as well as the service nodes\n".
   "               are all using a common shared filesystem. The default is 'no'.\n".
   " xcatconfdir:  Where xCAT config data is (default /etc/xcat).\n\n".
   " --------------------\n".
   "REMOTESHELL ATTRIBUTES\n".
   " --------------------\n".
   " nodesyncfiledir:  The directory on the node, where xdcp will rsync the files\n".
   " SNsyncfiledir:  The directory on the Service Node, where xdcp will rsync the files\n".
   "                 from the MN that will eventually be rsync'd to the compute nodes.\n\n".
   " sshbetweennodes:  Comma separated list of groups of compute nodes to enable passwordless root \n".
   "                   ssh during install, or xdsh -K. Default is ALLGROUPS.\n".
   "                   Set to NOGROUPS,if you do not wish to enabled any group of compute nodes.\n".
   "                   Service Nodes are not affected by this attribute\n".
   "                   they are always setup with\n".
   "                   passwordless root access to nodes and other SN.\n".
   "                   If using the zone table, this attribute in not used.\n\n".
   " -----------------\n".
   "SERVICES ATTRIBUTES\n".
   " -----------------\n".
   " consoleondemand:  When set to 'yes', conserver connects and creates the console\n".
   "                   output only when the user opens the console. Default is no on\n".
   "                   Linux, yes on AIX.\n\n".
   " consoleservice:   The console service to be used by xCAT. Default is conserver\n\n".
   " httpport:    The port number that the booting/installing nodes should contact the\n".
   "              http server on the MN/SN on. It is your responsibility to configure\n".
   "              the http server to listen on that port - xCAT will not do that.\n\n".
   " nmapoptions: Additional options for the nmap command. nmap is used in pping, \n".
   "              nodestat, xdsh -v and updatenode commands. Sometimes additional \n".
   "              performance tuning may be needed for nmap due to network traffic.\n".
   "              For example, if the network response time is too slow, nmap may not\n".
   "              give stable output. You can increase the timeout value by specifying \n".
   "              '--min-rtt-timeout 1s'. xCAT will append the options defined here to \n".
   "              the nmap command.\n\n".
   " ntpservers:  A comma delimited list of NTP servers for the cluster - often the\n".
   "              xCAT management node.\n\n".
   " svloglocal:  if set to 1, syslog on the service node will not get forwarded to the\n".
   "              mgmt node.\n\n".
   " timezone:  (e.g. America/New_York)\n\n".
   " tftpdir:  tftp directory path. Default is /tftpboot\n\n".
   " tftpflags:  The flags that used to start tftpd. Default is \'-v -l -s /tftpboot \n".
   "               -m /etc/tftpmapfile4xcat.conf\' if tftplfags is not set\n\n".
   " useNmapfromMN:  When set to yes, nodestat command should obtain the node status\n".
   "                 using nmap (if available) from the management node instead of the\n".
   "                 service node. This will improve the performance in a flat network.\n\n".
   " vsftp:       Default is 'n'. If set to 'y', the xcatd on the mn will automatically\n".
   "              bring up vsftpd.  (You must manually install vsftpd before this.\n".
   "              This setting does not apply to the service node. For sn\n".
   "              you need to set servicenode.ftpserver=1 if you want xcatd to\n".
   "              bring up vsftpd.\n\n".
   " -----------------------\n".
   "VIRTUALIZATION ATTRIBUTES\n".
   " -----------------------\n".
   " usexhrm:  Have xCAT run its xHRM script when booting up KVM guests to set the\n".
   "           virtual network bridge up correctly. See\n".
   "           https://sourceforge.net/apps/mediawiki/xcat/index.php?title=XCAT_Virtualization_with_KVM#Setting_up_a_network_bridge\n\n".
   " vcenterautojoin:  When set to no, the VMWare plugin will not attempt to auto remove\n".
   "                   and add hypervisors while trying to perform operations.  If users\n".
   "                   or tasks outside of xCAT perform the joining this assures xCAT\n".
   "                   will not interfere.\n\n".
   " vmwarereconfigonpower:  When set to no, the VMWare plugin will make no effort to\n".
   "                         push vm.cpus/vm.memory updates from xCAT to VMWare.\n\n".
   " persistkvmguests:  Keep the kvm definition on the kvm hypervisor when you power off\n".
   "                    the kvm guest node. This is useful for you to manually change the \n".
   "                    kvm xml definition file in virsh for debugging. Set anything means\n".
   "                    enable.\n\n".
   " --------------------\n".
   "XCAT DAEMON ATTRIBUTES\n".
   " --------------------\n".
   " useflowcontrol:  (yes/1 or no/0). If yes, the postscript processing on each node\n".
   "               contacts xcatd on the MN/SN using a lightweight UDP packet to wait\n".
   "               until xcatd is ready to handle the requests associated with\n".
   "               postscripts.  This prevents deploying nodes from flooding xcatd and\n".
   "               locking out admin interactive use. This value works with the\n".
   "               xcatmaxconnections and xcatmaxbatch attributes. Is not supported on AIX.\n".
   "               If the value is no, nodes sleep for a random time before contacting\n".
   "               xcatd, and retry. The default is no.\n".
   "               See the following document for details:\n".
   "               Hints_and_Tips_for_Large_Scale_Clusters\n\n".
   " xcatmaxconnections:  Number of concurrent xCAT protocol requests before requests\n".
   "                      begin queueing. This applies to both client command requests\n".
   "                      and node requests, e.g. to get postscripts. Default is 64.\n\n".
   " xcatmaxbatchconnections:  Number of concurrent xCAT connections allowed from the nodes.\n".
   "                      Value must be less than xcatmaxconnections. Default is 50.\n\n".
   " xcatdport:  The port used by the xcatd daemon for client/server communication.\n\n".
   " xcatiport:  The port used by xcatd to receive install status updates from nodes.\n\n".
   " xcatsslversion:  The ssl version by xcatd. Default is SSLv3.\n\n".
   " xcatsslciphers:  The ssl cipher by xcatd. Default is 3DES.\n\n",
  value => 'The value of the attribute specified in the "key" column.',
     comments => 'Any user-written notes.',
     disable => "Set to 'yes' or '1' to comment out this row.",
 },
  },
switch =>  {
    cols => [qw(node switch port vlan interface comments disable)],
    keys => [qw(node switch port)],
    table_desc => 'Contains what switch port numbers each node is connected to.',
 descriptions => {
  node => 'The node name or group name.',
  switch => 'The switch hostname.',
  port => 'The port number in the switch that this node is connected to. On a simple 1U switch, an administrator can generally enter the number as printed next to the ports, and xCAT will understand switch representation differences.  On stacked switches or switches with line cards, administrators should usually use the CLI representation (i.e. 2/0/1 or 5/8).  One notable exception is stacked SMC 8848M switches, in which you must add 56 for the proceeding switch, then the port number.  For example, port 3 on the second switch in an SMC8848M stack would be 59',
  vlan => 'The ID for the tagged vlan that is created on this port using mkvlan and chvlan commands.',
  interface => 'The interface name from the node perspective. For example, eth0. For the primary nic, it can be empty, the word "primary" or "primary:ethx" where ethx is the interface name.',
     comments => 'Any user-written notes.',
     disable => "Set to 'yes' or '1' to comment out this row.",
 },
  },
vpd => {
    cols => [qw(node serial mtm side asset uuid comments disable)],
    keys => [qw(node)],
    table_desc => 'The Machine type, Model, and Serial numbers of each node.',
 descriptions => {
  node => 'The node name or group name.',
  serial => 'The serial number of the node.',
  mtm => 'The machine type and model number of the node.  E.g. 7984-6BU',
  side => '<BPA>-<port> or <FSP>-<port>. The side information for the BPA/FSP. The side attribute refers to which BPA/FSP, A or B, which is determined by the slot value returned from lsslp command. It also lists the physical port within each BPA/FSP which is determined by the IP address order from the lsslp response. This information is used internally when communicating with the BPAs/FSPs',
  asset => 'A field for administators to use to correlate inventory numbers they may have to accomodate',
  uuid => 'The UUID applicable to the node',
     comments => 'Any user-written notes.',
     disable => "Set to 'yes' or '1' to comment out this row.",
 },
  },
nimimage  => {
 cols => [qw(imagename nimtype lpp_source spot root dump paging resolv_conf tmp home shared_home res_group nimmethod script bosinst_data installp_bundle mksysb fb_script shared_root otherpkgs image_data configdump comments disable)],
 keys => [qw(imagename)],
    table_desc => 'All the info that specifies a particular AIX operating system image that can be used to deploy AIX nodes.',
 descriptions => {
  imagename => 'User provided name of this xCAT OS image definition.',
  nimtype => 'The NIM client type- standalone, diskless, or dataless.',
  lpp_source => 'The name of the NIM lpp_source resource.',
  spot => 'The name of the NIM SPOT resource.',
  root => 'The name of the NIM root resource.',
  dump => 'The name of the NIM dump resource.',
  paging => 'The name of the NIM paging resource.',
  resolv_conf  => 'The name of the NIM resolv_conf resource.',
  tmp => 'The name of the NIM tmp resource.',
  home => 'The name of the NIM home resource.',
  shared_home => 'The name of the NIM shared_home resource.',
  res_group => 'The name of a NIM resource group.',
  nimmethod => 'The NIM install method to use, (ex. rte, mksysb).',
  script => 'The name of a NIM script resource.',
  fb_script => 'The name of a NIM fb_script resource.',
  bosinst_data => 'The name of a NIM bosinst_data resource.',
  otherpkgs => "One or more comma separated installp or rpm packages.  The rpm packages must have a prefix of 'R:', (ex. R:foo.rpm)",
  installp_bundle => 'One or more comma separated NIM installp_bundle resources.',
  mksysb => 'The name of a NIM mksysb resource.',
  shared_root => 'A shared_root resource represents a directory that can be used as a / (root) directory by one or more diskless clients.',
  image_data  => 'The name of a NIM image_data resource.',
  configdump  => 'Specifies the type of system dump to be collected. The values are selective, full, and none.  The default is selective.',
  comments => 'Any user-provided notes.',
  disable => "Set to 'yes' or '1' to comment out this row.",
 },
  },
performance => {
    cols => [qw(timestamp node attrname attrvalue comments disable)],
    keys => [qw(timestamp node attrname)],
    table_desc => 'Describes the system performance every interval unit of time.',
 descriptions => {
   timestamp => 'The time at which the metric was captured.',
   node => 'The node name.',
   attrname => 'The metric name.',
   attrvalue => 'The metric value.',
   comments => 'Any user-provided notes.',
   disable => "Set to 'yes' or '1' to comment out this row.",
 },
  },
zone => {
    cols => [qw(zonename sshkeydir sshbetweennodes defaultzone comments disable)],
    keys => [qw(zonename)],
    table_desc => 'Defines a cluster zone for nodes that share root ssh key access to each other.',
 descriptions => {
   zonename => 'The name of the zone.',
   sshkeydir => 'Directory containing the shared root ssh RSA keys.',
   sshbetweennodes => 'Indicates whether passwordless ssh will be setup between the nodes of this zone. Values are yes/1 or no/0. Default is yes. ',
   defaultzone => 'If nodes are not assigned to any other zone, they will default to this zone. If value is set to yes or 1.',
   comments => 'Any user-provided notes.',
   disable => "Set to 'yes' or '1' to comment out this row.",
 },
  },

eventlog => {
    cols => [qw(recid  eventtime eventtype monitor monnode node application component id severity  message rawdata comments disable)], 
    keys => [qw(recid)],
    types => {
	recid => 'INTEGER AUTO_INCREMENT',  
    },
    tablespace =>'XCATTBS32K',
    table_desc => 'Stores the events occurred.',  
    descriptions => {
        recid => 'The record id.',
	eventtime => 'The timestamp for the event.',     
	eventtype => 'The type of the event.',     # for RMC it's either "Event" or "Rearm event".
	monitor => 'The name of the monitor that monitors this event.',    #for RMC, it's the condition name
        monnode => 'The node that monitors this event.',
	node => 'The node where the event occurred.',    
	application => 'The application that reports the event.',        #RMC, Ganglia 
	component  => 'The component where the event occurred.',   #in RMC, it's the resource class name
	id => 'The location or the resource name where the event occurred.', #In RMC it's the resource name and attribute name
	severity => 'The severity of the event. Valid values are: informational, warning, critical.',
	message => 'The full description of the event.',
	rawdata => ' The data that associated with the event. ',    # in RMC, it's the attribute value, it takes the format of attname=attvalue[,atrrname=attvalue....]
	comments => 'Any user-provided notes.',
	disable => "Do not use.  tabprune will not work if set to yes or 1",
    },
},

auditlog => {
    cols => [qw(recid  audittime userid clientname clienttype command noderange args status comments disable)], 
    keys => [qw(recid)],
    types => {
	recid => 'INTEGER AUTO_INCREMENT',  
    },
    compress =>'YES',
    tablespace =>'XCATTBS32K',
    table_desc => ' Audit Data log.',  
    descriptions => {
        recid => 'The record id.',
	audittime => 'The timestamp for the audit entry.',     
	userid => 'The user running the command.',  
	clientname => 'The client machine, where the command originated.',  
        clienttype => 'Type of command: cli,java,webui,other.',
	command => 'Command executed.',    
	noderange => 'The noderange on which the command was run.',   
	args  => 'The command argument list.',  
	status => 'Allowed or Denied.',
	comments => 'Any user-provided notes.',
	disable => "Do not use.  tabprune will not work if set to yes or 1",
    },
},

prescripts => {
    cols => [qw(node begin end comments disable)],
    keys => [qw(node)],
    tablespace =>'XCATTBS16K',
    table_desc => 'The scripts that will be run at the beginning and the end of the nodeset(Linux), nimnodeset(AIX) or mkdsklsnode(AIX) command.',
    descriptions => {
	node => 'The node name or group name.',
  # Do not put description text past column 88, so it displays well in a 100 char wide window.
  # ----------------------------------------------------------------------------------|
	begin => 
   "The scripts to be run at the beginning of the nodeset(Linux),\n" .
   " nimnodeset(AIX) or mkdsklsnode(AIX) command.\n". 
   " The format is:\n".
   "   [action1:]s1,s2...[|action2:s3,s4,s5...]\n".
   " where:\n".
   "  - action1 and action2 for Linux are the nodeset actions specified in the command. \n" .
   "    For AIX, action1 and action1 can be 'diskless' for mkdsklsnode command'\n" . 
   "    and 'standalone for nimnodeset command. \n" .
   "  - s1 and s2 are the scripts to run for action1 in order.\n".
   "  - s3, s4, and s5 are the scripts to run for actions2.\n".
   " If actions are omitted, the scripts apply to all actions.\n".
   " Examples:\n".
   "   myscript1,myscript2  (all actions)\n".
   "   diskless:myscript1,myscript2   (AIX)\n".
   "   install:myscript1,myscript2|netboot:myscript3   (Linux)\n\n".
   " All the scripts should be copied to /install/prescripts directory.\n".
   " The following two environment variables will be passed to each script: \n".
   "   NODES a coma separated list of node names that need to run the script for\n".
   "   ACTION current nodeset action.\n\n".
   " If '#xCAT setting:MAX_INSTANCE=number' is specified in the script, the script\n".
   " will get invoked for each node in parallel, but no more than number of instances\n".
   " will be invoked at at a time. If it is not specified, the script will be invoked\n".
   " once for all the nodes.\n",
    end => "The scripts to be run at the end of the nodeset(Linux),\n". 
   " nimnodeset(AIX),or mkdsklsnode(AIX) command. \n".
   " The format is the same as the 'begin' column.",
	comments => 'Any user-written notes.',
	disable => "Set to 'yes' or '1' to comment out this row.",
    },
},

routes => {
    cols => [qw(routename net mask gateway ifname comments disable)],
    keys => [qw(routename)],
    table_desc => 'Describes the additional routes needed to be setup in the os routing table. These routes usually are used to connect the management node to the compute node using the servie node as gateway.',
    descriptions => {
	routename => 'Name used to identify this route.',
	net => 'The network address.',
	mask => 'The network mask.',
	ifname => 'The interface name that facing the gateway. It is optional for IPv4 routes, but it is required for IPv6 routes.',
	gateway => 'The gateway that routes the ip traffic from the mn to the nodes. It is usually a service node.',
	comments => 'Any user-written notes.',
	disable => "Set to 'yes' or '1' to comment out this row.",
    },
},

zvm => {
	cols => [qw(node hcp userid nodetype parent comments disable)],
	keys => [qw(node)],
	table_desc => 'List of z/VM virtual servers.',
	descriptions => {
		node => 'The node name.',
		hcp => 'The hardware control point for this node.',
		userid => 'The z/VM userID of this node.',
		nodetype => 'The node type. Valid values: cec (Central Electronic Complex), lpar (logical partition), zvm (z/VM host operating system), and vm (virtual machine).',
		parent => 'The parent node. For LPAR, this specifies the CEC. For z/VM, this specifies the LPAR. For VM, this specifies the z/VM host operating system.',
		comments => 'Any user provided notes.',
		disable => "Set to 'yes' or '1' to comment out this row.",
	},
},

firmware => {
        cols => [qw(node cfgfile comments disable)], 
        keys => [qw(node)],
        required => [qw(node)],
        table_desc => 'Maps node to firmware values to be used for setup at node discovery or later',
        descriptions => {
            node => 'The node id.',
            cfgfile => 'The file to use.',
            comments => 'Any user-written notes.',
            disable => "Set to 'yes' or '1' to comment out this row.",
        },
},

nics => {
        cols => [qw(node nicips  nichostnamesuffixes nichostnameprefixes nictypes niccustomscripts nicnetworks nicaliases nicextraparams comments disable)], 
        keys => [qw(node)],
        tablespace =>'XCATTBS16K',
        table_desc => 'Stores NIC details.',
        descriptions => {
            node => 'The node or group name.',
            nicips => 'Comma-separated list of IP addresses per NIC. To specify one ip address per NIC:
                    <nic1>!<ip1>,<nic2>!<ip2>,..., for example, eth0!10.0.0.100,ib0!11.0.0.100
                To specify multiple ip addresses per NIC:
                    <nic1>!<ip1>|<ip2>,<nic2>!<ip1>|<ip2>,..., for example, eth0!10.0.0.100|fd55::214:5eff:fe15:849b,ib0!11.0.0.100|2001::214:5eff:fe15:849a. The xCAT object definition commands support to use nicips.<nicname> as the sub attributes.
                Note: The primary IP address must also be stored in the hosts.ip attribute. The nichostnamesuffixes should specify one hostname suffix for each ip address.',
            nichostnamesuffixes  => 'Comma-separated list of hostname suffixes per NIC. 
                        If only one ip address is associated with each NIC:
                            <nic1>!<ext1>,<nic2>!<ext2>,..., for example, eth0!-eth0,ib0!-ib0
                        If multiple ip addresses are associcated with each NIC:
                            <nic1>!<ext1>|<ext2>,<nic2>!<ext1>|<ext2>,..., for example,  eth0!-eth0|-eth0-ipv6,ib0!-ib0|-ib0-ipv6. 
                        The xCAT object definition commands support to use nichostnamesuffixes.<nicname> as the sub attributes. 
                        Note:  According to DNS rules a hostname must be a text string up to 24 characters drawn from the alphabet (A-Z), digits (0-9), minus sign (-),and period (.). When you are specifying "nichostnamesuffixes" or "nicaliases" make sure the resulting hostnames will conform to this naming convention',
            nichostnameprefixes  => 'Comma-separated list of hostname prefixes per NIC. 
                        If only one ip address is associated with each NIC:
                            <nic1>!<ext1>,<nic2>!<ext2>,..., for example, eth0!eth0-,ib0!ib-
                        If multiple ip addresses are associcated with each NIC:
                            <nic1>!<ext1>|<ext2>,<nic2>!<ext1>|<ext2>,..., for example,  eth0!eth0-|eth0-ipv6i-,ib0!ib-|ib-ipv6-. 
                        The xCAT object definition commands support to use nichostnameprefixes.<nicname> as the sub attributes. 
                        Note:  According to DNS rules a hostname must be a text string up to 24 characters drawn from the alphabet (A-Z), digits (0-9), minus sign (-),and period (.). When you are specifying "nichostnameprefixes" or "nicaliases" make sure the resulting hostnames will conform to this naming convention',
            nictypes => 'Comma-separated list of NIC types per NIC. <nic1>!<type1>,<nic2>!<type2>, e.g. eth0!Ethernet,ib0!Infiniband. The xCAT object definition commands support to use nictypes.<nicname> as the sub attributes.', 
            niccustomscripts => 'Comma-separated list of custom scripts per NIC.  <nic1>!<script1>,<nic2>!<script2>, e.g. eth0!configeth eth0, ib0!configib ib0. The xCAT object definition commands support to use niccustomscripts.<nicname> as the sub attribute
.',
            nicnetworks => 'Comma-separated list of networks connected to each NIC.
                If only one ip address is associated with each NIC:
                    <nic1>!<network1>,<nic2>!<network2>, for example, eth0!10_0_0_0-255_255_0_0, ib0!11_0_0_0-255_255_0_0
                If multiple ip addresses are associated with each NIC:
                    <nic1>!<network1>|<network2>,<nic2>!<network1>|<network2>, for example, eth0!10_0_0_0-255_255_0_0|fd55:faaf:e1ab:336::/64,ib0!11_0_0_0-255_255_0_0|2001:db8:1:0::/64. The xCAT object definition commands support to use nicnetworks.<nicname> as the sub attributes.',
            nicaliases => 'Comma-separated list of hostname aliases for each NIC.
            Format: eth0!<alias list>,eth1!<alias1 list>|<alias2 list>
			For multiple aliases per nic use a space-separated list.
            For example: eth0!moe larry curly,eth1!tom|jerry',
            nicextraparams => 'Comma-separated list of extra parameters that will be used for each NIC configuration.
                If only one ip address is associated with each NIC:
                    <nic1>!<param1=value1 param2=value2>,<nic2>!<param3=value3>, for example, eth0!MTU=1500,ib0!MTU=65520 CONNECTED_MODE=yes.
                If multiple ip addresses are associated with each NIC:
                    <nic1>!<param1=value1 param2=value2>|<param3=value3>,<nic2>!<param4=value4 param5=value5>|<param6=value6>, for example, eth0!MTU=1500|MTU=1460,ib0!MTU=65520 CONNECTED_MODE=yes.
            The xCAT object definition commands support to use nicextraparams.<nicname> as the sub attributes.',
            comments => 'Any user-written notes.',
            disable => "Set to 'yes' or '1' to comment out this row.",
        },
},
rack => {
        cols => [qw(rackname displayname num height room comments disable)], 
        keys => [qw(rackname)],
        table_desc => 'Rack information.',
        descriptions => {
            rackname => 'The rack name.',
            displayname => 'Alternative name for rack. Only used by PCM.',
            num => 'The rack number.',
            height => 'Number of units which can be stored in the rack.',
            room => 'The room in which the rack is located.',
            comments => 'Any user-written notes.',
            disable => "Set to 'yes' or '1' to comment out this row.",
        },
},
osdistro => {
        cols => [qw(osdistroname basename majorversion minorversion arch type dirpaths comments disable)], 
        keys => [qw(osdistroname)],
        table_desc => 'Information about all the OS distros in the xCAT cluster',
        descriptions => {
            osdistroname => 'Unique name (e.g. rhels6.2-x86_64)',
            basename => 'The OS base name (e.g. rhels)',
            majorversion  => 'The OS distro major version.(e.g. 6)',
            minorversion  => 'The OS distro minor version. (e.g. 2)',
            arch => 'The OS distro arch (e.g. x86_64)',
            type => 'Linux or AIX',
            dirpaths => 'Directory paths where OS distro is store. There could be multiple paths if OS distro has more than one ISO image. (e.g. /install/rhels6.2/x86_64,...)',
            comments => 'Any user-written notes.',
            disable => "Set to 'yes' or '1' to comment out this row.",
        },
},
osdistroupdate => {
        cols => [qw(osupdatename osdistroname dirpath downloadtime comments disable)], 
        keys => [qw(osupdatename)],
        table_desc => 'Information about the OS distro updates in the xCAT cluster',
        descriptions => {
            osupdatename => 'Name of OS update. (e.g. rhn-update1)',
            osdistroname => 'The OS distro name to update. (e.g. rhels)',
            dirpath => 'Path to where OS distro update is stored. (e.g. /install/osdistroupdates/rhels6.2-x86_64-20120716-update) ',
            downloadtime => 'The timestamp when OS distro update was downloaded..',
            comments => 'Any user-written notes.',
            disable => "Set to 'yes' or '1' to comment out this row.",
        },
},
kit => {
        cols => [qw(kitname basename description version release ostype isinternal kitdeployparams kitdir comments disable)], 
        keys => [qw(kitname)],
        table_desc => 'This table stores all kits added to the xCAT cluster.',
        descriptions => {
            kitname => 'The unique generated kit name, when kit is added to the cluster.',
            basename => 'The kit base name',
            description => 'The Kit description.',
            version => 'The kit version',
            release => 'The kit release',
            ostype => 'The kit OS type.  Linux or AIX.',
            isinternal => 'A flag to indicated if the Kit is internally used. When set to 1, the Kit is internal. If 0 or undefined, the kit is not internal.',
            kitdeployparams => 'The file containing the default deployment parameters for this Kit.  These parameters are added to the OS Image definition.s list of deployment parameters when one or more Kit Components from this Kit are added to the OS Image.',
            kitdir => 'The path to Kit Installation directory on the Mgt Node.',
            comments => 'Any user-written notes.',
            disable => "Set to 'yes' or '1' to comment out this row.",
        },
},
kitrepo => {
        cols => [qw(kitreponame kitname osbasename osmajorversion osminorversion osarch compat_osbasenames kitrepodir comments disable)], 
        keys => [qw(kitreponame)],
        table_desc => 'This table stores all kits added to the xCAT cluster.',
        descriptions => {
            kitreponame => 'The unique generated kit repo package name, when kit is added to the cluster.',
            kitname => 'The Kit name which this Kit Package Repository belongs to.',
            osbasename => 'The OS distro name which this repository is based on.',
            osmajorversion => 'The OS distro major version which this repository is based on.',
            osminorversion => 'The OS distro minor version which this repository is based on. If this attribute is not set, it means that this repo applies to all minor versions.',
            osarch => 'The OS distro arch which this repository is based on.',
            compat_osbasenames => 'List of compatible OS base names.',
            kitrepodir => 'The path to Kit Repository directory on the Mgt Node.',
            comments => 'Any user-written notes.',
            disable => "Set to 'yes' or '1' to comment out this row.",
        },
},
kitcomponent => {
        cols => [qw(kitcompname description kitname kitreponame basename version release serverroles kitpkgdeps prerequisite driverpacks kitcompdeps postbootscripts genimage_postinstall exlist comments disable)], 
        keys => [qw(kitcompname)],
        tablespace =>'XCATTBS16K',
        table_desc => 'This table stores all kit components added to the xCAT cluster.',
        descriptions => {
            kitcompname => 'The unique Kit Component name. It is auto-generated when the parent Kit is added to the cluster.',
            description => 'The Kit component description.',
            kitname => 'The Kit name which this Kit Component belongs to.',
            kitreponame => 'The Kit Package Repository name which this Kit Component belongs to.',
            basename => 'Kit Component basename.',
            version => 'Kit Component version.',
            release => 'Kit Component release.',
            serverroles => 'The types of servers that this Kit Component can install on.  Valid types are: mgtnode, servicenode, compute',
            kitpkgdeps => 'Comma-separated list of packages that this kit component depends on.',
            prerequisite => 'Prerequisite for this kit component, the prerequisite includes ospkgdeps,preinstall,preupgrade,preuninstall scripts',
            driverpacks => 'Comma-separated List of driver package names. These must be full names like: pkg1-1.0-1.x86_64.rpm.',
            kitcompdeps  => 'Comma-separated list of kit components that this kit component depends on.',
            postbootscripts  => 'Comma-separated list of postbootscripts that will run during the node boot.',
            genimage_postinstall => 'Comma-separated list of postinstall scripts that will run during the genimage.',
            exlist  => 'Exclude list file containing the files/directories to exclude when building a diskless image.',
            comments => 'Any user-written notes.',
            disable => "Set to 'yes' or '1' to comment out this row.",
        },
},
discoverydata => {
   cols => [qw(uuid node method discoverytime arch cpucount cputype memory mtm serial nicdriver nicipv4 nichwaddr nicpci nicloc niconboard nicfirm switchname switchaddr switchdesc switchport otherdata comments disable)],
   keys => [qw(uuid)],
   tablespace =>'XCATTBS32K',
   table_desc => 'Discovery data which sent from genesis.',
   types => {
       otherdata => 'VARCHAR(2048)',   
   },
   descriptions => {
       uuid => 'The uuid of the node which send out the discovery request.',
       node => 'The node name which assigned to the discovered node.',
       method => 'The method which handled the discovery request. The method could be one of: switch, blade, profile, sequential.',
       discoverytime => 'The last time that xCAT received the discovery message.',
       arch => 'The architecture of the discovered node. e.g. x86_64.',
       cpucount => 'The number of cores multiply by threads core supported for the discovered node. e.g. 192.',
       cputype => 'The cpu type of the discovered node. e.g. Intel(R) Xeon(R) CPU E5-2690 0 @ 2.90GHz',
       memory => 'The memory size of the discovered node. e.g. 198460852',
       mtm => 'The machine type model of the discovered node. e.g. 786310X',
       serial => 'The serial number of the discovered node. e.g. 1052EFB',
       nicdriver =>  'The driver of the nic. The value should be comma separated <nic name!driver name>. e.g. eth0!be2net,eth1!be2net',
       nicipv4 => 'The ipv4 address of the nic. The value should be comma separated <nic name!ipv4 address>. e.g. eth0!10.0.0.212/8',
       nichwaddr => 'The hardware address of the nic. The should will be comma separated <nic name!hardware address>. e.g. eth0!34:40:B5:BE:DB:B0,eth1!34:40:B5:BE:DB:B4',
       nicpci => 'The pic device of the nic. The value should be comma separated <nic name!pci device>. e.g. eth0!0000:0c:00.0,eth1!0000:0c:00.1',
       nicloc => 'The location of the nic. The value should be comma separated <nic name!nic location>. e.g. eth0!Onboard Ethernet 1,eth1!Onboard Ethernet 2',
       niconboard => 'The onboard info of the nic. The value should be comma separated <nic name!onboard info>. e.g. eth0!1,eth1!2',
       nicfirm => 'The firmware description of the nic. The value should be comma separated <nic name!fimware description>. e.g. eth0!ServerEngines BE3 Controller,eth1!ServerEngines BE3 Controller',
       switchname => 'The switch name which the nic connected to. The value should be comma separated <nic name!switch name>. e.g. eth0!c909f06sw01',
       switchaddr => 'The address of the switch which the nic connected to. The value should be comma separated <nic name!switch address>. e.g. eth0!192.168.70.120', 
       switchdesc => 'The description of the switch which the nic connected to. The value should be comma separated <nic name!switch description>. e.g. eth0!IBM Flex System Fabric EN4093 10Gb Scalable Switch, flash image: version 7.2.6, boot image: version 7.2.6',
       switchport => 'The port of the switch that the nic connected to. The value should be comma separated <nic name!switch port>. e.g. eth0!INTA2',
       otherdata => 'The left data which is not parsed to specific attributes (The complete message comes from genesis)',
       comments => 'Any user-written notes.',
       disable => "Set to 'yes' or '1' to comment out this row.",
   },
},
cfgmgt => {
   cols => [qw(node cfgmgr cfgserver roles comments disable)],
   keys => [qw(node)],
   table_desc => 'Configuration management data for nodes used by non-xCAT osimage management services to install and configure software on a node.  ',
   descriptions => {
       node => 'The node being managed by the cfgmgr service',
       cfgmgr => 'The name of the configuration manager service.  Currently \'chef\' and \'puppet\' are supported services.',
       cfgserver => 'The xCAT node name of the chef server or puppet master',
       roles => 'The roles associated with this node as recognized by the cfgmgr for the software that is to be installed and configured.  These role names map to chef recipes or puppet manifest classes that should be used for this node.  For example, chef OpenStack cookbooks have roles such as mysql-master,keystone, glance, nova-controller, nova-conductor, cinder-all.  ',
       comments => 'Any user-written notes.',
       disable => "Set to 'yes' or '1' to comment out this row.",
   },
},
mic => {
    cols => [qw(node host id nodetype bridge onboot vlog powermgt comments disable)],
    keys => [qw(node)],
    table_desc => 'The host, slot id and configuraton of the mic (Many Integrated Core).',
    descriptions => {
        node => 'The node name or group name.',
        host => 'The host node which the mic card installed on.',
        id => 'The device id of the mic node.',
        nodetype => 'The hardware type of the mic node. Generally, it is mic.',
        bridge => 'The virtual bridge on the host node which the mic connected to.',
        onboot => 'Set mic to autoboot when mpss start. Valid values: yes|no. Default is yes.',
        vlog => 'Set the Verbose Log to console. Valid values: yes|no. Default is no.',
        powermgt => 'Set the Power Management for mic node. This attribute is used to set the power management state that mic may get into when it is idle. Four states can be set: cpufreq, corec6, pc3 and pc6. The valid value for powermgt attribute should be [cpufreq=<on|off>]![corec6=<on|off>]![pc3=<on|off>]![pc6=<on|off>]. e.g. cpufreq=on!corec6=off!pc3=on!pc6=off. Refer to the doc of mic to get more information for power management.',
        comments => 'Any user-provided notes.',
        disable => "Do not use.  tabprune will not work if set to yes or 1",
    },
},
hwinv => {
    cols => [qw(node cputype cpucount memory disksize comments disable)],
    keys => [qw(node)],
    table_desc => 'The hareware inventory for the node.',
    descriptions => {
        node => 'The node name or group name.',
        cputype => 'The cpu model name for the node.',
        cpucount => 'The number of cpus for the node.',
        memory => 'The size of the memory for the node in MB.',
        disksize => 'The size of the disks for the node in GB.',
        comments => 'Any user-provided notes.',
        disable =>  "Set to 'yes' or '1' to comment out this row.",
    },
},
token => {
    cols => [qw(tokenid username expire comments disable)],
    keys => [qw(tokenid)],
    table_desc => 'The token of users for authentication.',
    descriptions => {
        tokenid => 'It is a UUID as an unified identify for the user.',
        username => 'The user name.',
        expire => 'The expire time for this token.',
        comments => 'Any user-provided notes.',
        disable =>  "Set to 'yes' or '1' to comment out this row.",
    },
},
); # end of tabspec definition




###################################################
# adding user defined external tables
##################################################
foreach my $tabname (keys(%xCAT::ExtTab::ext_tabspec)) {
    if (exists($tabspec{$tabname})) {
	xCAT::MsgUtils->message('ES', "\n  Warning: Conflict when adding user defined tablespec. Duplicate table name: $tabname. \n");
    } else {
      $tabspec{$tabname}=$xCAT::ExtTab::ext_tabspec{$tabname};
    }
}
 




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
#                access_tabentry => '<table.attr>=<value>::<table.attr>=<value>',
#      # how to look up tabentry. Now support multiple lookup entries, useful for 'multiple keys" in the table 
#                         For <value>,
#                         # if "attr:<attrname>", use a previously resolved
#                         #    attribute value from the data object
#                         # for now, only supports the objectname in attr:<attrname>
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
  route => { attrs => [], attrhash => {}, objkey => 'routename' },
  group => { attrs => [], attrhash => {}, objkey => 'groupname' },
  site =>    { attrs => [], attrhash => {}, objkey => 'master' },
  policy => { attrs => [], attrhash => {}, objkey => 'priority' },
  monitoring => { attrs => [], attrhash => {}, objkey => 'name' },
  notification => { attrs => [], attrhash => {}, objkey => 'filename' },
  eventlog => { attrs => [], attrhash => {}, objkey => 'recid' }, 
  auditlog => { attrs => [], attrhash => {}, objkey => 'recid' }, 
  boottarget => { attrs => [], attrhash => {}, objkey => 'bprofile' },
  kit => { attrs => [], attrhash => {}, objkey => 'kitname' },
  kitrepo => { attrs => [], attrhash => {}, objkey => 'kitreponame' },
  kitcomponent => { attrs => [], attrhash => {}, objkey => 'kitcompname' },
  rack => { attrs => [], attrhash => {}, objkey => 'rackname' },
  osdistro=> { attrs => [], attrhash => {}, objkey => 'osdistroname' },
  osdistroupdate=> { attrs => [], attrhash => {}, objkey => 'osupdatename' },
  zone=> { attrs => [], attrhash => {}, objkey => 'zonename' },
  
);


###############
#   @nodeattrs ia a list of node attrs that can be used for
#  BOTH node and group definitions
##############
my @nodeattrs = (
       {attr_name => 'nodetype',
                 tabentry => 'nodetype.nodetype',
                 access_tabentry => 'nodetype.node=attr:node',
       },
####################
# postscripts table#
####################
        {attr_name => 'postscripts',
                 tabentry => 'postscripts.postscripts',
                 access_tabentry => 'postscripts.node=attr:node',
  },
        {attr_name => 'postbootscripts',
                 tabentry => 'postscripts.postbootscripts',
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
                 tabentry => 'noderes.tftpserver',
                 access_tabentry => 'noderes.node=attr:node',
  },
        {attr_name => 'tftpdir',
                 tabentry => 'noderes.tftpdir',
                 access_tabentry => 'noderes.node=attr:node',
  },
        {attr_name => 'nfsserver',
                 tabentry => 'noderes.nfsserver',
                 access_tabentry => 'noderes.node=attr:node',
  },
        {attr_name => 'nimserver',
                 tabentry => 'noderes.nimserver',
                 access_tabentry => 'noderes.node=attr:node',
  },

###
# TODO:  Is noderes.nfsdir used anywhere?  Could not find any code references
#        to this attribute.
###
        {attr_name => 'nfsdir',
                 tabentry => 'noderes.nfsdir',
                 access_tabentry => 'noderes.node=attr:node',
  },
        {attr_name => 'monserver',
                 tabentry => 'noderes.monserver',
                 access_tabentry => 'noderes.node=attr:node',
  },
        {attr_name => 'supportproxydhcp',
                 tabentry => 'noderes.proxydhcp',
                 access_tabentry => 'noderes.node=attr:node',
  },

 {attr_name => 'kernel',
                 tabentry => 'bootparams.kernel',
                 access_tabentry => 'bootparams.node=attr:node',
                },
 {attr_name => 'initrd',
                 tabentry => 'bootparams.initrd',
                 access_tabentry => 'bootparams.node=attr:node',
                },
 {attr_name => 'kcmdline',
                 tabentry => 'bootparams.kcmdline',
                 access_tabentry => 'bootparams.node=attr:node',
                },
 {attr_name => 'addkcmdline',
                 tabentry => 'bootparams.addkcmdline',
                 access_tabentry => 'bootparams.node=attr:node',
                },
        # Note that the serialport attr is actually defined down below
        # with the other serial*  attrs from the nodehm table
        #{attr_name => 'serialport',
        #         tabentry => 'noderes.serialport',
        #         access_tabentry => 'noderes.node=attr:node',
        # },
        {attr_name => 'primarynic',
                 tabentry => 'noderes.primarynic',
                 access_tabentry => 'noderes.node=attr:node',
  },
        {attr_name => 'installnic',
                 tabentry => 'noderes.installnic',
                 access_tabentry => 'noderes.node=attr:node',
  },
        {attr_name => 'netboot',
                 tabentry => 'noderes.netboot',
                 access_tabentry => 'noderes.node=attr:node',
  },
                {attr_name => 'nameservers',
                 tabentry => 'noderes.nameservers',
                 access_tabentry => 'noderes.node=attr:node',
  },
       {attr_name => 'routenames',
                 tabentry => 'noderes.routenames',
                 access_tabentry => 'noderes.node=attr:node',
  },
######################
#  servicenode table #
######################
	{attr_name => 'setupnameserver',
                 tabentry => 'servicenode.nameserver',
                 access_tabentry => 'servicenode.node=attr:node',
  },
	{attr_name => 'setupdhcp',
                 tabentry => 'servicenode.dhcpserver',
                 access_tabentry => 'servicenode.node=attr:node',
  },
	{attr_name => 'setuptftp',
                 tabentry => 'servicenode.tftpserver',
                 access_tabentry => 'servicenode.node=attr:node',
  },
	{attr_name => 'setupnfs',
                 tabentry => 'servicenode.nfsserver',
                 access_tabentry => 'servicenode.node=attr:node',
  },
	{attr_name => 'setupconserver',
                 tabentry => 'servicenode.conserver',
                 access_tabentry => 'servicenode.node=attr:node',
  },
	{attr_name => 'setupipforward',
                 tabentry => 'servicenode.ipforward',
                 access_tabentry => 'servicenode.node=attr:node',
  },
	{attr_name => 'setupproxydhcp',
                 tabentry => 'servicenode.proxydhcp',
                 access_tabentry => 'servicenode.node=attr:node',
  },
# - moserver not used yet
#	{attr_name => 'setupmonserver',
#                 tabentry => 'servicenode.monserver',
#                 access_tabentry => 'servicenode.node=attr:node',
#  },
	{attr_name => 'setupldap',
                 tabentry => 'servicenode.ldapserver',
                 access_tabentry => 'servicenode.node=attr:node',
  },
	{attr_name => 'setupntp',
                 tabentry => 'servicenode.ntpserver',
                 access_tabentry => 'servicenode.node=attr:node',
  },
	{attr_name => 'setupftp',
                 tabentry => 'servicenode.ftpserver',
                 access_tabentry => 'servicenode.node=attr:node',
  },
	{attr_name => 'setupnim',
                 tabentry => 'servicenode.nimserver',
                 access_tabentry => 'servicenode.node=attr:node',
  },
	{attr_name => 'dhcpinterfaces',
                 tabentry => 'servicenode.dhcpinterfaces',
                 access_tabentry => 'servicenode.node=attr:node',
  },
######################
#  nodetype table    #
######################
        {attr_name => 'arch',
                 tabentry => 'nodetype.arch',
                 access_tabentry => 'nodetype.node=attr:node',
  },
        {attr_name => 'supportedarchs',
                 tabentry => 'nodetype.supportedarchs',
                 access_tabentry => 'nodetype.node=attr:node',
  },
        {attr_name => 'os',
                 tabentry => 'nodetype.os',
                 access_tabentry => 'nodetype.node=attr:node',
  },
# TODO:  need to decide what to do with the profile attr once the osimage
#        stuff is implemented.  May want to move this to the osimage table.
        {attr_name => 'profile',
                 tabentry => 'nodetype.profile',
                 access_tabentry => 'nodetype.node=attr:node',
  },
  {attr_name => 'provmethod',
                 tabentry => 'nodetype.provmethod',
                 access_tabentry => 'nodetype.node=attr:node',
  },
####################
#  iscsi table     #
####################
 {attr_name => 'iscsiserver',
                 tabentry => 'iscsi.server',
                 access_tabentry => 'iscsi.node=attr:node',
                },
 {attr_name => 'iscsitarget',
                 tabentry => 'iscsi.target',
                 access_tabentry => 'iscsi.node=attr:node',
                },
 {attr_name => 'iscsiuserid',
                 tabentry => 'iscsi.userid',
                 access_tabentry => 'iscsi.node=attr:node',
                },
 {attr_name => 'iscsipassword',
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
        {attr_name => 'cmdmapping',
                 tabentry => 'nodehm.cmdmapping',
                 access_tabentry => 'nodehm.node=attr:node',
  },  
        {attr_name => 'serialport',
                 tabentry => 'nodehm.serialport',
                 access_tabentry => 'nodehm.node=attr:node',
  },
        {attr_name => 'serialspeed',
                 tabentry => 'nodehm.serialspeed',
                 access_tabentry => 'nodehm.node=attr:node',
  },
        {attr_name => 'serialflow',
                 tabentry => 'nodehm.serialflow',
                 access_tabentry => 'nodehm.node=attr:node',
  },
        {attr_name => 'consoleondemand',
                 tabentry => 'nodehm.consoleondemand',
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
        {attr_name => 'side',
                tabentry => 'vpd.side',
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
 {attr_name => 'username',
                 only_if => 'nodetype=ivm',
                 tabentry => 'ppchcp.username',
                 access_tabentry => 'ppchcp.hcp=attr:node',
                },
 {attr_name => 'password',
                 only_if => 'nodetype=ivm',
                 tabentry => 'ppchcp.password',
                 access_tabentry => 'ppchcp.hcp=attr:node',
                },
 {attr_name => 'username',
                 only_if => 'nodetype=hmc',
                 tabentry => 'ppchcp.username',
                 access_tabentry => 'ppchcp.hcp=attr:node',
                },
 {attr_name => 'password',
                 only_if => 'nodetype=hmc',
                 tabentry => 'ppchcp.password',
                 access_tabentry => 'ppchcp.hcp=attr:node',
                },
 {attr_name => 'username',
                 only_if => 'nodetype=ppc',
                 tabentry => 'ppchcp.username',
                 access_tabentry => 'ppchcp.hcp=attr:node',
                },
 {attr_name => 'password',
                 only_if => 'nodetype=ppc',
                 tabentry => 'ppchcp.password',
                 access_tabentry => 'ppchcp.hcp=attr:node',
                },

####################
#  ppc table       #
####################
        {attr_name => 'hcp',
                 tabentry => 'ppc.hcp',
                 access_tabentry => 'ppc.node=attr:node',
  },
 {attr_name => 'id',
                 tabentry => 'ppc.id',
                 access_tabentry => 'ppc.node=attr:node',
                },
 {attr_name => 'pprofile',
                only_if => 'mgt=hmc',
                 tabentry => 'ppc.pprofile',
                 access_tabentry => 'ppc.node=attr:node',
                },
 {attr_name => 'pprofile',
                only_if => 'mgt=ivm',
                 tabentry => 'ppc.pprofile',
                 access_tabentry => 'ppc.node=attr:node',
                },
 {attr_name => 'pprofile',
                only_if => 'mgt=fsp',
                 tabentry => 'ppc.pprofile',
                 access_tabentry => 'ppc.node=attr:node',
                },
 {attr_name => 'parent',
                 only_if => 'mgt=hmc',
                 tabentry => 'ppc.parent',
                 access_tabentry => 'ppc.node=attr:node',
                },
 {attr_name => 'parent',
                 only_if => 'mgt=ivm',
                 tabentry => 'ppc.parent',
                 access_tabentry => 'ppc.node=attr:node',
                },
 {attr_name => 'parent',
                 only_if => 'mgt=bpa',
                 tabentry => 'ppc.parent',
                 access_tabentry => 'ppc.node=attr:node',
                },

 {attr_name => 'parent',
                 only_if => 'mgt=fsp',
                 tabentry => 'ppc.parent',
                 access_tabentry => 'ppc.node=attr:node',
                },
 {attr_name => 'hwtype',
                 only_if => 'mgt=fsp',
                 tabentry => 'ppc.nodetype',
                 access_tabentry => 'ppc.node=attr:node',
                },    
 {attr_name => 'hwtype',
                 only_if => 'mgt=bpa',
                 tabentry => 'ppc.nodetype',
                 access_tabentry => 'ppc.node=attr:node',
                },    
 {attr_name => 'hwtype',
                 only_if => 'mgt=ivm',
                 tabentry => 'ppc.nodetype',
                 access_tabentry => 'ppc.node=attr:node',
                },  
 {attr_name => 'hwtype',
                 only_if => 'mgt=hmc',
                 tabentry => 'ppc.nodetype',
                 access_tabentry => 'ppc.node=attr:node',
                },                  
 {attr_name => 'hwtype',
                 only_if => 'mgt=zvm',
                 tabentry => 'zvm.nodetype',
                 access_tabentry => 'ppc.node=attr:node',
                },                   
 {attr_name => 'hwtype',
                 only_if => 'mgt=blade',
                 tabentry => 'mp.nodetype',
                 access_tabentry => 'mp.node=attr:node',
                }, 
 {attr_name => 'hwtype',
                 only_if => 'mgt=ipmi',
                 tabentry => 'mp.nodetype',
                 access_tabentry => 'mp.node=attr:node',
                }, 
 {attr_name => 'supernode',
                 tabentry => 'ppc.supernode',
                 access_tabentry => 'ppc.node=attr:node',
                },
 {attr_name => 'sfp',
                 tabentry => 'ppc.sfp',
                 access_tabentry => 'ppc.node=attr:node',
                },
#######################
#  ppcdirect table    #
#######################
        {attr_name => 'passwd.HMC',
                 only_if => 'mgt=fsp',
                 tabentry => 'ppcdirect.password',
                 access_tabentry => 'ppcdirect.hcp=attr:node::ppcdirect.username=str:HMC',
  },
        {attr_name => 'passwd.hscroot',
                 only_if => 'mgt=fsp',
                 tabentry => 'ppcdirect.password',
                 access_tabentry => 'ppcdirect.hcp=attr:node::ppcdirect.username=str:hscroot',
  },
        {attr_name => 'passwd.admin',
                 only_if => 'mgt=fsp',
                 tabentry => 'ppcdirect.password',
                 access_tabentry => 'ppcdirect.hcp=attr:node::ppcdirect.username=str:admin',
  },
        {attr_name => 'passwd.general',
                 only_if => 'mgt=fsp',
                 tabentry => 'ppcdirect.password',
                 access_tabentry => 'ppcdirect.hcp=attr:node::ppcdirect.username=str:general',
  },
        {attr_name => 'passwd.celogin',
                 only_if => 'mgt=fsp',
                 tabentry => 'ppcdirect.password',
                 access_tabentry => 'ppcdirect.hcp=attr:node::ppcdirect.username=str:celogin',
  },        {attr_name => 'passwd.celogin',
                 only_if => 'mgt=bpa',
                 tabentry => 'ppcdirect.password',
                 access_tabentry => 'ppcdirect.hcp=attr:node::ppcdirect.username=str:celogin',
  },
        {attr_name => 'passwd.HMC',
                 only_if => 'mgt=bpa',
                 tabentry => 'ppcdirect.password',
                 access_tabentry => 'ppcdirect.hcp=attr:node::ppcdirect.username=str:HMC',
  },
        {attr_name => 'passwd.hscroot',
                 only_if => 'mgt=bpa',
                 tabentry => 'ppcdirect.password',
                 access_tabentry => 'ppcdirect.hcp=attr:node::ppcdirect.username=str:hscroot',
  },
        {attr_name => 'passwd.admin',
                 only_if => 'mgt=bpa',
                 tabentry => 'ppcdirect.password',
                 access_tabentry => 'ppcdirect.hcp=attr:node::ppcdirect.username=str:admin',
  },
        {attr_name => 'passwd.general',
                 only_if => 'mgt=bpa',
                 tabentry => 'ppcdirect.password',
                 access_tabentry => 'ppcdirect.hcp=attr:node::ppcdirect.username=str:general',
  },

####################
#  zvm table       #
####################
	{attr_name => 'hcp',
		only_if => 'mgt=zvm',
		tabentry => 'zvm.hcp',
		access_tabentry => 'zvm.node=attr:node',
	},
	{attr_name => 'userid',
		only_if => 'mgt=zvm',
		tabentry => 'zvm.userid',
		access_tabentry => 'zvm.node=attr:node',
	},
	
##################
#  ipmi table    #
##################
        {attr_name => 'bmc',
                 only_if => 'mgt=ipmi',
                 tabentry => 'ipmi.bmc',
                 access_tabentry => 'ipmi.node=attr:node',
  },
        {attr_name => 'bmcport',
                 only_if => 'mgt=ipmi',
                 tabentry => 'ipmi.bmcport',
                 access_tabentry => 'ipmi.node=attr:node',
  },
        {attr_name => 'bmcusername',
                 only_if => 'mgt=ipmi',
                 tabentry => 'ipmi.username',
                 access_tabentry => 'ipmi.node=attr:node',
  },
        {attr_name => 'bmcpassword',
                 only_if => 'mgt=ipmi',
                 tabentry => 'ipmi.password',
                 access_tabentry => 'ipmi.node=attr:node',
  },
################
#  mp table    #
################
        {attr_name => 'mpa',
                 # Remove the restriction so that fsp also can 
                 # write to mpa attribute
                 #only_if => 'mgt=blade',
                 tabentry => 'mp.mpa',
                 access_tabentry => 'mp.node=attr:node',
  },
        {attr_name => 'slotid',
                 only_if => 'mgt=fsp',
                 tabentry => 'mp.id',
                 access_tabentry => 'mp.node=attr:node',
  },
        {attr_name => 'id',
                 only_if => 'mgt=blade',
                 tabentry => 'mp.id',
                 access_tabentry => 'mp.node=attr:node',
  },
        {attr_name => 'slotid',
                 only_if => 'mgt=ipmi',
                 tabentry => 'mp.id',
                 access_tabentry => 'mp.node=attr:node',
  },

#################
#  mpa table    #
#################
        {attr_name => 'username',
                 only_if => 'nodetype=mm',
                 tabentry => 'mpa.username',
                 access_tabentry => 'mpa.mpa=attr:node',
  },
        {attr_name => 'password',
                 only_if => 'nodetype=mm',
                 tabentry => 'mpa.password',
                 access_tabentry => 'mpa.mpa=attr:node',
  },
        {attr_name => 'displayname',
                 only_if => 'nodetype=mm',
                 tabentry => 'mpa.displayname',
                 access_tabentry => 'mpa.mpa=attr:node',
  },
        {attr_name => 'slots',
                 only_if => 'nodetype=mm',
                 tabentry => 'mpa.slots',
                 access_tabentry => 'mpa.mpa=attr:node',
  },
        {attr_name => 'urlpath',
                 only_if => 'nodetype=mm',
                 tabentry => 'mpa.urlpath',
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
  },
        {attr_name => 'height',
                 tabentry => 'nodepos.height',
                 access_tabentry => 'nodepos.node=attr:node',
  },
####################
#  nics table  #
####################
        {attr_name => 'nicips',
                tabentry => 'nics.nicips',
                access_tabentry => 'nics.node=attr:node',
        },
        {attr_name => 'nichostnamesuffixes',
                tabentry => 'nics.nichostnamesuffixes',
                access_tabentry => 'nics.node=attr:node',
        },
        {attr_name => 'nichostnameprefixes',
                tabentry => 'nics.nichostnameprefixes',
                access_tabentry => 'nics.node=attr:node',
        },
        {attr_name => 'nictypes',
                tabentry => 'nics.nictypes',
                access_tabentry => 'nics.node=attr:node',
        },
        {attr_name => 'niccustomscripts',
                tabentry => 'nics.niccustomscripts',
                access_tabentry => 'nics.node=attr:node',
        },
        {attr_name => 'nicnetworks',
                tabentry => 'nics.nicnetworks',
                access_tabentry => 'nics.node=attr:node',
        },
		{attr_name => 'nicaliases',
				tabentry => 'nics.nicaliases',
				access_tabentry => 'nics.node=attr:node',
		},
		{attr_name => 'nicextraparams',
				tabentry => 'nics.nicextraparams',
				access_tabentry => 'nics.node=attr:node',
		},
#######################
#  prodkey table     #
######################
                {attr_name => 'productkey',
                 tabentry => 'prodkey.key',
                 access_tabentry => 'prodkey.node=attr:node',
                },
######################
#  domain table     #
######################
                {attr_name => 'ou',
                 tabentry => 'domain.ou',
                 access_tabentry => 'domain.node=attr:node',
                },
                {attr_name => 'domainadminuser',
                 tabentry => 'domain.adminuser',
                 access_tabentry => 'domain.node=attr:node',
                },
                {attr_name => 'domainadminpassword',
                 tabentry => 'domain.adminpassword',
                 access_tabentry => 'domain.node=attr:node',
                },
                {attr_name => 'authdomain',
                 tabentry => 'domain.authdomain',
                 access_tabentry => 'domain.node=attr:node',
                },
                {attr_name => 'domaintype',
                 tabentry => 'domain.type',
                 access_tabentry => 'domain.node=attr:node',
                },
######################
#  storage table     #
######################
                {attr_name => 'osvolume',
                 tabentry => 'storage.osvolume',
                 access_tabentry => 'storage.node=attr:node',
                },
                {attr_name => 'storagcontroller',
                 tabentry => 'storage.controller',
                 access_tabentry => 'storage.node=attr:node',
                },
                {attr_name => 'storagetype',
                 tabentry => 'storage.type',
                 access_tabentry => 'storage.node=attr:node',
                },
######################
#  vm table          #
######################
             {attr_name => 'vmmanager',
                 tabentry => 'vm.mgr',
                 access_tabentry => 'vm.node=attr:node',
                },
                {attr_name => 'vmhost',
                 tabentry => 'vm.host',
                 access_tabentry => 'vm.node=attr:node',
                },
                {attr_name => 'migrationdest',
                 tabentry => 'vm.migrationdest',
                 access_tabentry => 'vm.node=attr:node',
                },
                {attr_name => 'vmstorage',
                 tabentry => 'vm.storage',
                 access_tabentry => 'vm.node=attr:node',
                },
                {attr_name => 'vmphyslots',
                 tabentry => 'vm.physlots',
                 access_tabentry => 'vm.node=attr:node',
                },
                {attr_name => 'vmothersetting',
                 tabentry => 'vm.othersettings',
                 access_tabentry => 'vm.node=attr:node',
                },
                {attr_name => 'vmstoragemodel',
                 tabentry => 'vm.storagemodel',
                 access_tabentry => 'vm.node=attr:node',
                },
                {attr_name => 'vmstoragecache',
                 tabentry => 'vm.storagecache',
                 access_tabentry => 'vm.node=attr:node',
                },
                {attr_name => 'vmstorageformat',
                 tabentry => 'vm.storageformat',
                 access_tabentry => 'vm.node=attr:node',
                },
                {attr_name => 'vmcfgstore',
                 tabentry => 'vm.cfgstore',
                 access_tabentry => 'vm.node=attr:node',
                },
                {attr_name => 'vmmemory',
                 tabentry => 'vm.memory',
                 access_tabentry => 'vm.node=attr:node',
                },
                {attr_name => 'vmcpus',
                 tabentry => 'vm.cpus',
                 access_tabentry => 'vm.node=attr:node',
                },
                {attr_name => 'vmnics',
                 tabentry => 'vm.nics',
                 access_tabentry => 'vm.node=attr:node',
                },
                {attr_name => 'vmnicnicmodel',
                 tabentry => 'vm.nicmodel',
                 access_tabentry => 'vm.node=attr:node',
                },
                {attr_name => 'vmbootorder',
                 tabentry => 'vm.bootorder',
                 access_tabentry => 'vm.node=attr:node',
                },
                {attr_name => 'vmvirtflags',
                 tabentry => 'vm.virtflags',
                 access_tabentry => 'vm.node=attr:node',
                },
                {attr_name => 'vmmaster',
                 tabentry => 'vm.master',
                 access_tabentry => 'vm.node=attr:node',
                },
                {attr_name => 'vmvncport',
                 tabentry => 'vm.vncport',
                 access_tabentry => 'vm.node=attr:node',
                },
                {attr_name => 'vmtextconsole',
                 tabentry => 'vm.textconsole',
                 access_tabentry => 'vm.node=attr:node',
                },
                {attr_name => 'vmbeacon',
                 tabentry => 'vm.beacon',
                 access_tabentry => 'vm.node=attr:node',
                },
                {attr_name => 'vmcluster',
                 tabentry => 'vm.cluster',
                 access_tabentry => 'vm.node=attr:node',
                },
######################
#  hypervisor table      #
######################
                {attr_name => 'hosttype',
                 tabentry => 'hypervisor.type',
                 access_tabentry => 'hypervisor.node=attr:node',
                },
                {attr_name => 'hostinterface',
                 tabentry => 'hypervisor.interface',
                 access_tabentry => 'hypervisor.node=attr:node',
                },
                {attr_name => 'hostmanager',
                 tabentry => 'hypervisor.mgr',
                 access_tabentry => 'hypervisor.node=attr:node',
                },
                {attr_name => 'hostcluster',
                 tabentry => 'hypervisor.cluster',
                 access_tabentry => 'hypervisor.node=attr:node',
                },
######################
#  websrv table      #
######################
		{attr_name => 'webport',
                 only_if => 'nodetype=websrv',
                 tabentry => 'websrv.port',
                 access_tabentry => 'websrv.node=attr:node',
                },
		{attr_name => 'username',
                 only_if => 'nodetype=websrv',
                 tabentry => 'websrv.username',
                 access_tabentry => 'websrv.node=attr:node',
                },
		{attr_name => 'password',
                 only_if => 'nodetype=websrv',
                 tabentry => 'websrv.password',
                 access_tabentry => 'websrv.node=attr:node',
                },
######################
#  switch table      #
######################
                {attr_name => 'switch',
                 tabentry => 'switch.switch',
                 access_tabentry => 'switch.node=attr:node',
                },
                {attr_name => 'switchport',
                 tabentry => 'switch.port',
                 access_tabentry => 'switch.node=attr:node',
                },
                {attr_name => 'switchvlan',
                 tabentry => 'switch.vlan',
                 access_tabentry => 'switch.node=attr:node',
                },
                {attr_name => 'switchinterface',
                 tabentry => 'switch.interface',
                 access_tabentry => 'switch.node=attr:node',
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
        {attr_name => 'otherinterfaces',
                 tabentry => 'hosts.otherinterfaces',
                 access_tabentry => 'hosts.node=attr:node',
             },
####################
# prescripts table#
####################
        {attr_name => 'prescripts-begin',
                 tabentry => 'prescripts.begin',
                 access_tabentry => 'prescripts.node=attr:node',
			},
        {attr_name => 'prescripts-end',
                 tabentry => 'prescripts.end',
                 access_tabentry => 'prescripts.node=attr:node',
			},
#################
# cfgmgt table  #
#################
        {attr_name => 'cfgmgr',
                 tabentry => 'cfgmgt.cfgmgr',
                 access_tabentry => 'cfgmgt.node=attr:node',
        },
        {attr_name => 'cfgserver',
                 tabentry => 'cfgmgt.cfgserver',
                 access_tabentry => 'cfgmgt.node=attr:node',
        },
        {attr_name => 'cfgmgtroles',
                 tabentry => 'cfgmgt.roles',
                 access_tabentry => 'cfgmgt.node=attr:node',
        },
#####################
##   mic   table    #
#####################
	{attr_name => 'michost',
		only_if => 'mgt=mic',
		tabentry => 'mic.host',
		access_tabentry => 'mic.node=attr:node',
	},
	{attr_name => 'micid',
		only_if => 'mgt=mic',
		tabentry => 'mic.id',
		access_tabentry => 'mic.node=attr:node',
	},
	{attr_name => 'hwtype',
		only_if => 'mgt=mic',
		tabentry => 'mic.nodetype',
		access_tabentry => 'mic.node=attr:node',
	},
	{attr_name => 'micbridge',
		only_if => 'mgt=mic',
		tabentry => 'mic.bridge',
		access_tabentry => 'mic.node=attr:node',
	},
	{attr_name => 'miconboot',
		only_if => 'mgt=mic',
		tabentry => 'mic.onboot',
		access_tabentry => 'mic.node=attr:node',
	},
	{attr_name => 'micvlog',
		only_if => 'mgt=mic',
		tabentry => 'mic.vlog',
		access_tabentry => 'mic.node=attr:node',
	},
	{attr_name => 'micpowermgt',
		only_if => 'mgt=mic',
		tabentry => 'mic.powermgt',
		access_tabentry => 'mic.node=attr:node',
	},
#####################
##   hwinv   table    #
#####################
	{attr_name => 'cputype',
		tabentry => 'hwinv.cputype',
		access_tabentry => 'hwinv.node=attr:node',
	},
	{attr_name => 'cpucount',
		tabentry => 'hwinv.cpucount',
		access_tabentry => 'hwinv.node=attr:node',
	},
	{attr_name => 'memory',
		tabentry => 'hwinv.memory',
		access_tabentry => 'hwinv.node=attr:node',
	},
	{attr_name => 'disksize',
		tabentry => 'hwinv.disksize',
		access_tabentry => 'hwinv.node=attr:node',
	},
		
  );	# end of @nodeattrs that applies to both nodes and groups


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
        {attr_name => 'groups',
                 tabentry => 'nodelist.groups',
                 access_tabentry => 'nodelist.node=attr:node',
             },
        {attr_name => 'status',
                 tabentry => 'nodelist.status',
                 access_tabentry => 'nodelist.node=attr:node',
             },
        {attr_name => 'statustime',
                 tabentry => 'nodelist.statustime',
                 access_tabentry => 'nodelist.node=attr:node',
             },
        {attr_name => 'appstatus',
                 tabentry => 'nodelist.appstatus',
                 access_tabentry => 'nodelist.node=attr:node',
             },
        {attr_name => 'appstatustime',
                 tabentry => 'nodelist.appstatustime',
                 access_tabentry => 'nodelist.node=attr:node',
             },
        {attr_name => 'primarysn',
                 tabentry => 'nodelist.primarysn',
                 access_tabentry => 'nodelist.node=attr:node',
             },
		{attr_name => 'hidden',
                 tabentry => 'nodelist.hidden',
                 access_tabentry => 'nodelist.node=attr:node',
             },             
		{attr_name => 'updatestatus',
                 tabentry => 'nodelist.updatestatus',
                 access_tabentry => 'nodelist.node=attr:node',
             },             
		{attr_name => 'updatestatustime',
                 tabentry => 'nodelist.updatestatustime',
                 access_tabentry => 'nodelist.node=attr:node',
             },       
                {attr_name => 'zonename',
                 tabentry => 'nodelist.zonename',
                 access_tabentry => 'nodelist.node=attr:node',
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
@{$defspec{osimage}->{'attrs'}} = (
 {attr_name => 'imagename',
                 tabentry => 'osimage.imagename',
                 access_tabentry => 'osimage.imagename=attr:imagename',
                 },
 {attr_name => 'groups',
                 tabentry => 'osimage.groups',
                 access_tabentry => 'osimage.imagename=attr:imagename',
                 },
 {attr_name => 'imagetype',
                 tabentry => 'osimage.imagetype',
                 access_tabentry => 'osimage.imagename=attr:imagename',
                 },
 {attr_name => 'description',
                 tabentry => 'osimage.description',
                 access_tabentry => 'osimage.imagename=attr:imagename',
                 },
 {attr_name => 'provmethod',
                 tabentry => 'osimage.provmethod',
                 access_tabentry => 'osimage.imagename=attr:imagename',
                 },
 {attr_name => 'osdistroname',
                 tabentry => 'osimage.osdistroname',
                 access_tabentry => 'osimage.imagename=attr:imagename',
                 },
 {attr_name => 'osupdatename',
                 tabentry => 'osimage.osupdatename',
                 access_tabentry => 'osimage.imagename=attr:imagename',
                 },
 {attr_name => 'cfmdir',
                 tabentry => 'osimage.cfmdir',
                 access_tabentry => 'osimage.imagename=attr:imagename',
                 },
 {attr_name => 'rootfstype',
                 only_if => 'imagetype=linux',
                 tabentry => 'osimage.rootfstype',
                 access_tabentry => 'osimage.imagename=attr:imagename',
                 },
 {attr_name => 'profile',
                 tabentry => 'osimage.profile',
                 access_tabentry => 'osimage.imagename=attr:imagename',
                 },
 {attr_name => 'osname',
                 tabentry => 'osimage.osname',
                 access_tabentry => 'osimage.imagename=attr:imagename',
                 },
 {attr_name => 'osvers',
                 tabentry => 'osimage.osvers',
                 access_tabentry => 'osimage.imagename=attr:imagename',
                 },
 {attr_name => 'osarch',
                 tabentry => 'osimage.osarch',
                 access_tabentry => 'osimage.imagename=attr:imagename',
                 },
 {attr_name => 'synclists',
                 tabentry => 'osimage.synclists',
                 access_tabentry => 'osimage.imagename=attr:imagename',
                 },
 {attr_name => 'postscripts',
                 tabentry => 'osimage.postscripts',
                 access_tabentry => 'osimage.imagename=attr:imagename',
                 },
 {attr_name => 'postbootscripts',
                 tabentry => 'osimage.postbootscripts',
                 access_tabentry => 'osimage.imagename=attr:imagename',
                 },
 {attr_name => 'serverrole',
                 tabentry => 'osimage.serverrole',
                 access_tabentry => 'osimage.imagename=attr:imagename',
                 },
 {attr_name => 'isdeletable',
                 tabentry => 'osimage.isdeletable',
                 access_tabentry => 'osimage.imagename=attr:imagename',
                 },
 {attr_name => 'kitcomponents',
                 tabentry => 'osimage.kitcomponents',
                 access_tabentry => 'osimage.imagename=attr:imagename',
                 },
####################
# linuximage table#
####################
 {attr_name => 'template',
                 only_if => 'imagetype=linux',
                 tabentry => 'linuximage.template',
                 access_tabentry => 'linuximage.imagename=attr:imagename',
                }, 
 {attr_name => 'boottarget',
                 only_if => 'imagetype=linux',
                 tabentry => 'linuximage.boottarget',
                 access_tabentry => 'linuximage.imagename=attr:imagename',
                }, 
 {attr_name => 'addkcmdline',
                 only_if => 'imagetype=linux',
                 tabentry => 'linuximage.addkcmdline',
                 access_tabentry => 'linuximage.imagename=attr:imagename',
                }, 
 {attr_name => 'pkglist',
                 only_if => 'imagetype=linux',
                 tabentry => 'linuximage.pkglist',
                 access_tabentry => 'linuximage.imagename=attr:imagename',
                }, 
 {attr_name => 'pkgdir',
                 only_if => 'imagetype=linux',
                 tabentry => 'linuximage.pkgdir',
                 access_tabentry => 'linuximage.imagename=attr:imagename',
                }, 
 {attr_name => 'otherpkglist',
                 only_if => 'imagetype=linux',
                 tabentry => 'linuximage.otherpkglist',
                 access_tabentry => 'linuximage.imagename=attr:imagename',
                }, 
 {attr_name => 'otherpkgdir',
                 only_if => 'imagetype=linux',
                 tabentry => 'linuximage.otherpkgdir',
                 access_tabentry => 'linuximage.imagename=attr:imagename',
                }, 
 {attr_name => 'exlist',
                 only_if => 'imagetype=linux',
                 tabentry => 'linuximage.exlist',
                 access_tabentry => 'linuximage.imagename=attr:imagename',
                }, 
 {attr_name => 'postinstall',
                 only_if => 'imagetype=linux',
                 tabentry => 'linuximage.postinstall',
                 access_tabentry => 'linuximage.imagename=attr:imagename',
                }, 
 {attr_name => 'rootimgdir',
                 only_if => 'imagetype=linux',
                 tabentry => 'linuximage.rootimgdir',
                 access_tabentry => 'linuximage.imagename=attr:imagename',
                }, 
 {attr_name => 'kerneldir',
                 only_if => 'imagetype=linux',
                 tabentry => 'linuximage.kerneldir',
                 access_tabentry => 'linuximage.imagename=attr:imagename',
                },
 {attr_name => 'nodebootif',
                 only_if => 'imagetype=linux',
                 tabentry => 'linuximage.nodebootif',
                 access_tabentry => 'linuximage.imagename=attr:imagename',
                },
 {attr_name => 'otherifce',
                 only_if => 'imagetype=linux',
                 tabentry => 'linuximage.otherifce',
                 access_tabentry => 'linuximage.imagename=attr:imagename',
                },
 {attr_name => 'netdrivers',
                 only_if => 'imagetype=linux',
                 tabentry => 'linuximage.netdrivers',
                 access_tabentry => 'linuximage.imagename=attr:imagename',
                },
 {attr_name => 'kernelver',
                 only_if => 'imagetype=linux',
                 tabentry => 'linuximage.kernelver',
                 access_tabentry => 'linuximage.imagename=attr:imagename',
                },
 {attr_name => 'krpmver',
                 only_if => 'imagetype=linux',
                 tabentry => 'linuximage.krpmver',
                 access_tabentry => 'linuximage.imagename=attr:imagename',
                },
 {attr_name => 'permission',
                 only_if => 'imagetype=linux',
                 tabentry => 'linuximage.permission',
                 access_tabentry => 'linuximage.imagename=attr:imagename',
                },
 {attr_name => 'dump',
                 only_if => 'imagetype=linux',
                 tabentry => 'linuximage.dump',
                 access_tabentry => 'linuximage.imagename=attr:imagename',
                },
 {attr_name => 'crashkernelsize',
                 only_if => 'imagetype=linux',
                 tabentry => 'linuximage.crashkernelsize',
                 access_tabentry => 'linuximage.imagename=attr:imagename',
                },
 {attr_name => 'partitionfile',
                 only_if => 'imagetype=linux',
                 tabentry => 'linuximage.partitionfile',
                 access_tabentry => 'linuximage.imagename=attr:imagename',
                },
 {attr_name => 'driverupdatesrc',
                 only_if => 'imagetype=linux',
                 tabentry => 'linuximage.driverupdatesrc',
                 access_tabentry => 'linuximage.imagename=attr:imagename',
                },
 {attr_name => 'usercomment',
                 only_if => 'imagetype=linux',
                 tabentry => 'linuximage.comments',
                 access_tabentry => 'linuximage.imagename=attr:imagename',
                 },
####################
# winimage table#
####################
 {attr_name => 'template',
                 only_if => 'imagetype=windows',
                 tabentry => 'winimage.template',
                 access_tabentry => 'winimage.imagename=attr:imagename',
                }, 
 {attr_name => 'installto',
                 only_if => 'imagetype=windows',
                 tabentry => 'winimage.installto',
                 access_tabentry => 'winimage.imagename=attr:imagename',
                },
{attr_name => 'partitionfile',
                 only_if => 'imagetype=windows',
                 tabentry => 'winimage.partitionfile',
                 access_tabentry => 'winimage.imagename=attr:imagename',
                },
{attr_name => 'winpepath',
                 only_if => 'imagetype=windows',
                 tabentry => 'winimage.winpepath',
                 access_tabentry => 'winimage.imagename=attr:imagename',
                },
####################
# nimimage table#
####################
 {attr_name => 'nimtype',
                 only_if => 'imagetype=NIM',
                 tabentry => 'nimimage.nimtype',
                 access_tabentry => 'nimimage.imagename=attr:imagename',
                 },
 {attr_name => 'nimmethod',
                 only_if => 'imagetype=NIM',
                 tabentry => 'nimimage.nimmethod',
                 access_tabentry => 'nimimage.imagename=attr:imagename',
                 },
 {attr_name => 'lpp_source',
                 only_if => 'imagetype=NIM',
                 tabentry => 'nimimage.lpp_source',
                 access_tabentry => 'nimimage.imagename=attr:imagename',
                 },
 {attr_name => 'spot',
                 only_if => 'imagetype=NIM',
                 tabentry => 'nimimage.spot',
                 access_tabentry => 'nimimage.imagename=attr:imagename',
                 },
 {attr_name => 'root',
                 only_if => 'imagetype=NIM',
                 tabentry => 'nimimage.root',
                 access_tabentry => 'nimimage.imagename=attr:imagename',
                 },
 {attr_name => 'dump',
                 only_if => 'imagetype=NIM',
                 tabentry => 'nimimage.dump',
                 access_tabentry => 'nimimage.imagename=attr:imagename',
                 },
 {attr_name => 'configdump',
				only_if => 'imagetype=NIM',
				tabentry => 'nimimage.configdump',
				access_tabentry => 'nimimage.imagename=attr:imagename',
				},
 {attr_name => 'paging',
                 only_if => 'imagetype=NIM',
                 tabentry => 'nimimage.paging',
                 access_tabentry => 'nimimage.imagename=attr:imagename',
                 },
 {attr_name => 'resolv_conf',
                 only_if => 'imagetype=NIM',
                 tabentry => 'nimimage.resolv_conf',
                 access_tabentry => 'nimimage.imagename=attr:imagename',
                 },
 {attr_name => 'image_data',
				only_if => 'imagetype=NIM',
				tabentry => 'nimimage.image_data',
				access_tabentry => 'nimimage.imagename=attr:imagename',
				},
 {attr_name => 'tmp',
                 only_if => 'imagetype=NIM',
                 tabentry => 'nimimage.tmp',
                 access_tabentry => 'nimimage.imagename=attr:imagename',
                 },
 {attr_name => 'home',
                 only_if => 'imagetype=NIM',
                 tabentry => 'nimimage.home',
                 access_tabentry => 'nimimage.imagename=attr:imagename',
                 },
 {attr_name => 'shared_home',
                 only_if => 'imagetype=NIM',
                 tabentry => 'nimimage.shared_home',
                 access_tabentry => 'nimimage.imagename=attr:imagename',
                 },
 {attr_name => 'shared_root',
                 only_if => 'imagetype=NIM',
                 tabentry => 'nimimage.shared_root',
                 access_tabentry => 'nimimage.imagename=attr:imagename',
                 },
 {attr_name => 'script',
                only_if => 'imagetype=NIM',
                 tabentry => 'nimimage.script',
                 access_tabentry => 'nimimage.imagename=attr:imagename',
                 },
 {attr_name => 'fb_script',
                 only_if => 'imagetype=NIM',
                 tabentry => 'nimimage.fb_script',
                 access_tabentry => 'nimimage.imagename=attr:imagename',
                 },
 {attr_name => 'bosinst_data',
                 only_if => 'imagetype=NIM',
                 tabentry => 'nimimage.bosinst_data',
                 access_tabentry => 'nimimage.imagename=attr:imagename',
                 },
 {attr_name => 'installp_bundle',
                 only_if => 'imagetype=NIM',                 
                 tabentry => 'nimimage.installp_bundle',
                 access_tabentry => 'nimimage.imagename=attr:imagename',
                 },
 {attr_name => 'otherpkgs',
                 only_if => 'imagetype=NIM',
				tabentry => 'nimimage.otherpkgs',
				access_tabentry => 'nimimage.imagename=attr:imagename',
				},
 {attr_name => 'mksysb',
                 only_if => 'imagetype=NIM',
                 tabentry => 'nimimage.mksysb',
                 access_tabentry => 'nimimage.imagename=attr:imagename',
                 },
# {attr_name => 'res_group',
#                 tabentry => 'nimimage.res_group',
#                 access_tabentry => 'nimimage.imagename=attr:imagename',
#                 },
 {attr_name => 'usercomment',
                 only_if => 'imagetype=NIM',
                 tabentry => 'nimimage.comments',
                 access_tabentry => 'nimimage.imagename=attr:imagename',
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
        {attr_name => 'mgtifname',
                 tabentry => 'networks.mgtifname',
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
        {attr_name => 'ntpservers',
                 tabentry => 'networks.ntpservers',
                 access_tabentry => 'networks.netname=attr:netname',
  },
        {attr_name => 'logservers',
                 tabentry => 'networks.logservers',
                 access_tabentry => 'networks.netname=attr:netname',
  },

        {attr_name => 'dynamicrange',
                 tabentry => 'networks.dynamicrange',
                 access_tabentry => 'networks.netname=attr:netname',
  },
        {attr_name => 'nodehostname',
                 tabentry => 'networks.nodehostname',
                 access_tabentry => 'networks.netname=attr:netname',
  },
        {attr_name => 'ddnsdomain',
                 tabentry => 'networks.ddnsdomain',
                 access_tabentry => 'networks.netname=attr:netname',
  },
        {attr_name => 'vlanid',
                 tabentry => 'networks.vlanid',
                 access_tabentry => 'networks.netname=attr:netname',
  },
  		{attr_name => 'domain',
                 tabentry => 'networks.domain',
                 access_tabentry => 'networks.netname=attr:netname',
  },
  		{attr_name => 'staticrange',
                 tabentry => 'networks.staticrange',
                 access_tabentry => 'networks.netname=attr:netname',
  },
  		{attr_name => 'staticrangeincrement',
                 tabentry => 'networks.staticrangeincrement',
                 access_tabentry => 'networks.netname=attr:netname',
  },
 {attr_name => 'usercomment',
                 tabentry => 'networks.comments',
                 access_tabentry => 'networks.netname=attr:netname',
                },
             );
####################
#  rack table      #
####################
@{$defspec{rack}->{'attrs'}} = (
        {attr_name => 'rackname',
                tabentry => 'rack.rackname',
                access_tabentry => 'rack.rackname=attr:rackname',
        },
        {attr_name => 'displayname',
                tabentry => 'rack.displayname',
                access_tabentry => 'rack.rackname=attr:rackname',
        },
        {attr_name => 'num',
                tabentry => 'rack.num',
                access_tabentry => 'rack.rackname=attr:rackname',
        },
        {attr_name => 'height',
                tabentry => 'rack.height',
                access_tabentry => 'rack.rackname=attr:rackname',
        },
        {attr_name => 'room',
                tabentry => 'rack.room',
                access_tabentry => 'rack.rackname=attr:rackname',
        },
        {attr_name => 'usercomment',
                 tabentry => 'rack.comments',
                 access_tabentry => 'rack.rackname=attr:rackname',
        },
   );
####################
#  zone table      #
####################
@{$defspec{zone}->{'attrs'}} = (
        {attr_name => 'zonename',
                tabentry => 'zone.zonename',
                access_tabentry => 'zone.zonename=attr:zonename',
        },
        {attr_name => 'sshkeydir',
                tabentry => 'zone.sshkeydir',
                access_tabentry => 'zone.zonename=attr:zonename',
        },
        {attr_name => 'sshbetweennodes',
                tabentry => 'zone.sshbetweennodes',
                access_tabentry => 'zone.zonename=attr:zonename',
        },
        {attr_name => 'defaultzone',
                tabentry => 'zone.defaultzone',
                access_tabentry => 'zone.zonename=attr:zonename',
        },
        {attr_name => 'usercomment',
                 tabentry => 'zone.comments',
                 access_tabentry => 'zone.zonename=attr:zonename',
        },
   );
#########################
#  route data object  #
#########################
#     routes table    #
#########################
@{$defspec{route}->{'attrs'}} = (
        {attr_name => 'routename',
                 tabentry => 'routes.routename',
                 access_tabentry => 'routes.routename=attr:routename',
                 },
        {attr_name => 'net',
                 tabentry => 'routes.net',
                 access_tabentry => 'routes.routename=attr:routename',
  },
        {attr_name => 'mask',
                 tabentry => 'routes.mask',
                 access_tabentry => 'routes.routename=attr:routename',
  },
        {attr_name => 'gateway',
                 tabentry => 'routes.gateway',
                 access_tabentry => 'routes.routename=attr:routename',
  },
        {attr_name => 'ifname',
                 tabentry => 'routes.ifname',
                 access_tabentry => 'routes.routename=attr:routename',
  },
 {attr_name => 'usercomment',
                 tabentry => 'routes.comments',
                 access_tabentry => 'routes.routename=attr:routename',
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
 {attr_name => 'membergroups',
                 tabentry => 'nodegroup.membergroups',
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
	{attr_name => 'disable',
                 tabentry => 'monitoring.disable',
                 access_tabentry => 'monitoring.name=attr:name',
                 },
);

@{$defspec{eventlog}->{'attrs'}} = (
        {attr_name => 'recid',
                 tabentry => 'eventlog.recid',
                 access_tabentry => 'eventlog.recid=attr:recid',
                 },
        {attr_name => 'eventtime',
                 tabentry => 'eventlog.eventtime',
                 access_tabentry => 'eventlog.recid=attr:recid',
                 },
        {attr_name => 'eventtype',
                 tabentry => 'eventlog.eventtype',
                 access_tabentry => 'eventlog.recid=attr:recid',
                 },
        {attr_name => 'monitor',
                 tabentry => 'eventlog.monitor',
                 access_tabentry => 'eventlog.recid=attr:recid',
                 },
        {attr_name => 'monnode',
                 tabentry => 'eventlog.monnode',
                 access_tabentry => 'eventlog.recid=attr:recid',
                 },
        {attr_name => 'node',
                 tabentry => 'eventlog.node',
                 access_tabentry => 'eventlog.recid=attr:recid',
                 },
        {attr_name => 'application',
                 tabentry => 'eventlog.application',
                 access_tabentry => 'eventlog.recid=attr:recid',
                 },
        {attr_name => 'component',
                 tabentry => 'eventlog.component',
                 access_tabentry => 'eventlog.recid=attr:recid',
                 },
        {attr_name => 'id',
                 tabentry => 'eventlog.id',
                 access_tabentry => 'eventlog.recid=attr:recid',
                 },
        {attr_name => 'severity',
                 tabentry => 'eventlog.severity',
                 access_tabentry => 'eventlog.recid=attr:recid',
                 },
        {attr_name => 'message',
                 tabentry => 'eventlog.message',
                 access_tabentry => 'eventlog.recid=attr:recid',
                 },
        {attr_name => 'rawdata',
                 tabentry => 'eventlog.rawdata',
                 access_tabentry => 'eventlog.recid=attr:recid',
                 },
        {attr_name => 'comments',
                 tabentry => 'eventlog.comments',
                 access_tabentry => 'eventlog.recid=attr:recid',
                 },
	{attr_name => 'disable',
                 tabentry => 'eventlog.disable',
                 access_tabentry => 'eventlog.recid=attr:recid',
                 },
);


#############################
#  auditlog object #
#############################
#   auditlog table    #
#############################

@{$defspec{auditlog}->{'attrs'}} = (
        {attr_name => 'recid',
                 tabentry => 'auditlog.recid',
                 access_tabentry => 'auditlog.recid=attr:recid',
                 },
        {attr_name => 'audittime',
                 tabentry => 'auditlog.audittime',
                 access_tabentry => 'auditlog.recid=attr:recid',
                 },
        {attr_name => 'userid',
                 tabentry => 'auditlog.userid',
                 access_tabentry => 'auditlog.recid=attr:recid',
                 },
        {attr_name => 'clientname',
                 tabentry => 'auditlog.clientname',
                 access_tabentry => 'auditlog.recid=attr:recid',
                 },
        {attr_name => 'clienttype',
                 tabentry => 'auditlog.clienttype',
                 access_tabentry => 'auditlog.recid=attr:recid',
                 },
        {attr_name => 'command',
                 tabentry => 'auditlog.command',
                 access_tabentry => 'auditlog.recid=attr:recid',
                 },
        {attr_name => 'noderange',
                 tabentry => 'auditlog.noderange',
                 access_tabentry => 'auditlog.recid=attr:recid',
                 },
        {attr_name => 'args',
                 tabentry => 'auditlog.args',
                 access_tabentry => 'auditlog.recid=attr:recid',
                 },
        {attr_name => 'status',
                 tabentry => 'auditlog.status',
                 access_tabentry => 'auditlog.recid=attr:recid',
                 },
        {attr_name => 'comments',
                 tabentry => 'auditlog.comments',
                 access_tabentry => 'auditlog.recid=attr:recid',
                 },
	{attr_name => 'disable',
                 tabentry => 'auditlog.disable',
                 access_tabentry => 'auditlog.recid=attr:recid',
                 },
);

#############################
#  firmware object #
#############################
#    firmware table    #
#############################

@{$defspec{firmware}->{'attrs'}} =
(
    {   attr_name => 'cfgfile',
        tabentry => 'firmware.cfgfile',
        access_tabentry => 'firmware.file=attr:cfgfile',
    },
    {attr_name => 'comments',
        tabentry => 'firmware.comments',
        access_tabentry => 'firmware.file=attr:cfgfile',
     },
     {attr_name => 'disable',
        tabentry => 'firmware.disable',
        access_tabentry => 'firmware.file=attr:cfgfile',
     },
);
#############################
#  osdistro object #
#############################
@{$defspec{osdistro}->{'attrs'}} = (
        {attr_name => 'osdistroname',
                tabentry => 'osdistro.osdistroname',
                access_tabentry => 'osdistro.osdistroname=attr:osdistroname',
        },
        {attr_name => 'basename',
                tabentry => 'osdistro.basename',
                access_tabentry => 'osdistro.osdistroname=attr:osdistroname',
        },
        {attr_name => 'majorversion',
                tabentry => 'osdistro.majorversion',
               access_tabentry => 'osdistro.osdistroname=attr:osdistroname',
        },
        {attr_name => 'minorversion',
                tabentry => 'osdistro.minorversion',
                access_tabentry => 'osdistro.osdistroname=attr:osdistroname',
        },
        {attr_name => 'arch',
                tabentry => 'osdistro.arch',
                access_tabentry => 'osdistro.osdistroname=attr:osdistroname',
        },

        {attr_name => 'type',
                tabentry => 'osdistro.type',
                access_tabentry => 'osdistro.osdistroname=attr:osdistroname',
        },
        {attr_name => 'dirpaths',
                tabentry => 'osdistro.dirpaths',
                access_tabentry => 'osdistro.osdistroname=attr:osdistroname',
        },
);

#############################
#  osdistroupdate object #
#############################
@{$defspec{osdistroupdate}->{'attrs'}} = (
        {attr_name => 'osupdatename',
                tabentry => 'osdistroupdate.osupdatename',
                access_tabentry => 'osdistroupdate.osupdatename=attr:osupdatename',
        },
        {attr_name => 'osdistroname',
                tabentry => 'osdistroupdate.osdistroname',
                access_tabentry => 'osdistroupdate.osupdatename=attr:osupdatename',
        },
        {attr_name => 'dirpath',
                tabentry => 'osdistroupdate.dirpath',
                access_tabentry => 'osdistroupdate.osupdatename=attr:osupdatename',
        },
        {attr_name => 'downloadtime',
                tabentry => 'osdistroupdate.downloadtime',
                access_tabentry => 'osdistroupdate.osupdatename=attr:osupdatename',
        },
	{attr_name => 'usercomment',
               tabentry => 'osdistroupdate.comments',
                access_tabentry => 'osdistroupdate.osupdatename=attr:osupdatename',
        },
);

#############################
#  kit object #
#############################
#############################
#  kit object #
#############################
#     kit table    #
#############################
@{$defspec{kit}->{'attrs'}} = (
        {attr_name => 'kitname',
                 tabentry => 'kit.kitname',
                 access_tabentry => 'kit.kitname=attr:kitname',
        },
        {attr_name => 'basename',
                 tabentry => 'kit.basename',
                 access_tabentry => 'kit.kitname=attr:kitname',
        },
        {attr_name => 'description',
                 tabentry => 'kit.description',
                 access_tabentry => 'kit.kitname=attr:kitname',
        },
        {attr_name => 'version',
                 tabentry => 'kit.version',
                 access_tabentry => 'kit.kitname=attr:kitname',
        },
        {attr_name => 'release',
                 tabentry => 'kit.release',
                 access_tabentry => 'kit.kitname=attr:kitname',
        },
        {attr_name => 'ostype',
                 tabentry => 'kit.ostype',
                 access_tabentry => 'kit.kitname=attr:kitname',
        },
        {attr_name => 'isinternal',
                 tabentry => 'kit.isinternal',
                 access_tabentry => 'kit.kitname=attr:kitname',
        },
        {attr_name => 'kitdeployparams',
                 tabentry => 'kit.kitdeployparams',
                 access_tabentry => 'kit.kitname=attr:kitname',
        },
        {attr_name => 'kitdir',
                 tabentry => 'kit.kitdir',
                 access_tabentry => 'kit.kitname=attr:kitname',
        },

);
#############################
#  kitrepo object #
#############################
#     kitrepo table    #
#############################
@{$defspec{kitrepo}->{'attrs'}} = (
        {attr_name => 'kitreponame',
                 tabentry => 'kitrepo.kitreponame',
                 access_tabentry => 'kitrepo.kitreponame=attr:kitreponame',
        },
        {attr_name => 'kitname',
                 tabentry => 'kitrepo.kitname',
                 access_tabentry => 'kitrepo.kitreponame=attr:kitreponame',
        },
        {attr_name => 'osbasename',
                 tabentry => 'kitrepo.osbasename',
                 access_tabentry => 'kitrepo.kitreponame=attr:kitreponame',
        },
        {attr_name => 'osmajorversion',
                 tabentry => 'kitrepo.osmajorversion',
                 access_tabentry => 'kitrepo.kitreponame=attr:kitreponame',
        },
        {attr_name => 'osminorversion',
                 tabentry => 'kitrepo.osminorversion',
                 access_tabentry => 'kitrepo.kitreponame=attr:kitreponame',
        },
        {attr_name => 'osarch',
                 tabentry => 'kitrepo.osarch',
                 access_tabentry => 'kitrepo.kitreponame=attr:kitreponame',
        },
        {attr_name => 'compat_osbasenames',
                tabentry => 'kitrepo.compat_osbasenames',
                 access_tabentry => 'kitrepo.kitreponame=attr:kitreponame',
        },
        {attr_name => 'kitrepodir',
                tabentry => 'kitrepo.kitrepodir',
                 access_tabentry => 'kitrepo.kitreponame=attr:kitreponame',
        },

);
#############################
#############################
#  kitcomponent object #
#############################
#     kitcomponent table    #
#############################
@{$defspec{kitcomponent}->{'attrs'}} = (
        {attr_name => 'kitcompname',
                 tabentry => 'kitcomponent.kitcompname',
                 access_tabentry => 'kitcomponent.kitcompname=attr:kitcompname',
        },
        {attr_name => 'description',
                 tabentry => 'kitcomponent.description',
                 access_tabentry => 'kitcomponent.kitcompname=attr:kitcompname',
        },
        {attr_name => 'kitname',
                 tabentry => 'kitcomponent.kitname',
                 access_tabentry => 'kitcomponent.kitcompname=attr:kitcompname',
        },
        {attr_name => 'kitreponame',
                 tabentry => 'kitcomponent.kitreponame',
                 access_tabentry => 'kitcomponent.kitcompname=attr:kitcompname',
        },
        {attr_name => 'basename',
                 tabentry => 'kitcomponent.basename',
                 access_tabentry => 'kitcomponent.kitcompname=attr:kitcompname',
        },
        {attr_name => 'version',
                 tabentry => 'kitcomponent.version',
                 access_tabentry => 'kitcomponent.kitcompname=attr:kitcompname',
        },
        {attr_name => 'release',
                 tabentry => 'kitcomponent.release',
                 access_tabentry => 'kitcomponent.kitcompname=attr:kitcompname',
        },
        {attr_name => 'serverroles',
                 tabentry => 'kitcomponent.serverroles',
                 access_tabentry => 'kitcomponent.kitcompname=attr:kitcompname',
        },
        {attr_name => 'kitpkgdeps',
                 tabentry => 'kitcomponent.kitpkgdeps',
                 access_tabentry => 'kitcomponent.kitcompname=attr:kitcompname',
        },
        {attr_name => 'prerequisite',
                 tabentry => 'kitcomponent.prerequisite',
                 access_tabentry => 'kitcomponent.kitcompname=attr:kitcompname',
        },
        {attr_name => 'driverpacks',
                 tabentry => 'kitcomponent.driverpacks',
                 access_tabentry => 'kitcomponent.kitcompname=attr:kitcompname',
        },
        {attr_name => 'kitcompdeps',
                 tabentry => 'kitcomponent.kitcompdeps',
                 access_tabentry => 'kitcomponent.kitcompname=attr:kitcompname',
        },
        {attr_name => 'postbootscripts',
                 tabentry => 'kitcomponent.postbootscripts',
                 access_tabentry => 'kitcomponent.kitcompname=attr:kitcompname',
        },
        {attr_name => 'genimage_postinstall',
                 tabentry => 'kitcomponent.genimage_postinstall',
                 access_tabentry => 'kitcomponent.kitcompname=attr:kitcompname',
        },
        {attr_name => 'exlist',
                 tabentry => 'kitcomponent.exlist',
                 access_tabentry => 'kitcomponent.kitcompname=attr:kitcompname',
        },

);

###################################################

###################################################
# adding user defined external defspec
##################################################
foreach my $objname (keys(%xCAT::ExtTab::ext_defspec)) {
    if (exists($xCAT::ExtTab::ext_defspec{$objname}->{'attrs'})) {
	if (exists($defspec{$objname})) {
	    my @extattr=@{$xCAT::ExtTab::ext_defspec{$objname}->{'attrs'}};
	    my @attr=@{$defspec{$objname}->{'attrs'}};
	    my %tmp_hash=();
	    foreach my $orig (@attr) {
		my $attrname=$orig->{attr_name};
		$tmp_hash{$attrname}=1;
	    }
	    foreach(@extattr) {
		my $attrname=$_->{attr_name};
		if (exists($tmp_hash{$attrname})) {
		    xCAT::MsgUtils->message('ES', "\n  Warning: Conflict when adding user defined defspec. Attribute name $attrname is already defined in object $objname. \n");
		} else {
		    push(@{$defspec{$objname}->{'attrs'}}, $_); 
		}
	    }
	} else {
	    $defspec{$objname}=$xCAT::ExtTab::ext_defspec{$objname};
	}
    }
}


#print "\ndefspec:\n";
#foreach(%xCAT::Schema::defspec) {
#    print "  $_:\n";
#    my @attr=@{$xCAT::Schema::defspec{$_}->{'attrs'}};
#    foreach my $h (@attr) {
#	print "    " . $h->{attr_name} . "\n";
#    }
#}  


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


