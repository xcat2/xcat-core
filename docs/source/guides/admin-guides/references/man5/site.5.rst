
######
site.5
######

.. highlight:: perl


****
NAME
****


\ **site**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **site Attributes:**\   \ *key*\ , \ *value*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


Global settings for the whole cluster.  This table is different from the 
other tables in that each attribute is just named in the key column, rather 
than having a separate column for each attribute. The following is a list of 
attributes currently used by xCAT organized into categories.


****************
site Attributes:
****************



\ **key**\ 
 
 Attribute Name:  Description
 
 
 .. code-block:: perl
 
   ------------
  AIX ATTRIBUTES
   ------------
   nimprime :   The name of NIM server, if not set default is the AIX MN.
                If Linux MN, then must be set for support of mixed cluster (TBD).
  
   useSSHonAIX:  (yes/1 or no/0). Default is yes.  The support for rsh/rcp is deprecated.
   useNFSv4onAIX:  (yes/1 or no/0). If yes, NFSv4 will be used with NIM. If no,
                 NFSv3 will be used with NIM. Default is no.
  
   -----------------
  DATABASE ATTRIBUTES
   -----------------
   auditnosyslog: If set to 1, then commands will only be written to the auditlog table.
                  This attribute set to 1 and auditskipcmds=ALL means no logging of commands.
                  Default is to write to both the auditlog table and syslog.
   auditskipcmds: List of commands and/or client types that will not be
                  written to the auditlog table and syslog. See auditnosyslog.
                  'ALL' means all cmds will be skipped. If attribute is null, all
                  commands will be written.
                  clienttype:web would skip all commands from the web client
                  For example: tabdump,nodels,clienttype:web 
                  will not log tabdump,nodels and any web client commands.
  
   databaseloc:    Directory where we create the db instance directory.
                   Default is /var/lib. Only DB2 is currently supported.
                   Do not use the directory in the site.installloc or
                   installdir attribute. This attribute must not be changed
                   once db2sqlsetup script has been run and DB2 has been setup.
  
   excludenodes:  A set of comma separated nodes and/or groups that would automatically
                  be subtracted from any noderange, it can be used for excluding some
                  failed nodes for any xCAT commands. See the 'noderange' manpage for
                  details on supported formats.
  
   nodestatus:  If set to 'n', the nodelist.status column will not be updated during
                the node deployment, node discovery and power operations. The default
                is to update.
  
   skiptables:  Comma separated list of tables to be skipped by dumpxCATdb
  
   skipvalidatelog:  If set to 1, then getcredentials and getpostscripts calls will not 
                     be logged in syslog.
  
   -------------
  DHCP ATTRIBUTES
   -------------
   dhcpinterfaces:  The network interfaces DHCP should listen on.  If it is the same for all
                    nodes, use a comma-separated list of the NICs.  To specify different NICs
                    for different nodes, use the format: "xcatmn|eth1,eth2;service|bond0", 
                    where xcatmn is the name of the management node, DHCP should listen on 
                    the eth1 and eth2 interfaces.  All the nodes in group 'service' should 
                    listen on the 'bond0' interface.
  
                    To disable the genesis kernel from being sent to specific interfaces, a
                    ':noboot' option can be appended to the interface name.  For example,
                    if the management node has two interfaces, eth1 and eth2, disable
                    genesis from being sent to eth1 using: "eth1:noboot,eth2".
  
   dhcpsetup:  If set to 'n', it will skip the dhcp setup process in the nodeset cmd.
  
   dhcplease:  The lease time for the dhcp client. The default value is 43200.
  
   disjointdhcps:  If set to '1', the .leases file on a service node only contains
                   the nodes it manages. The default value is '0'.
                   '0' value means include all the nodes in the subnet.
  
   pruneservices:  Whether to enable service pruning when noderm is run (i.e.
                   removing DHCP entries when noderm is executed)
  
   managedaddressmode: The mode of networking configuration during node provision.
                       If set to 'static', the network configuration will be configured 
                       in static mode based on the node and network definition on MN.
                       If set to 'dhcp', the network will be configured with dhcp protocol.
                       The default is 'dhcp'.
  
   ------------
  DNS ATTRIBUTES
   ------------
   dnshandler:  Name of plugin that handles DNS setup for makedns.
  
   domain:  The DNS domain name used for the cluster.
  
   forwarders:  The DNS servers at your site that can provide names outside of the cluster.
                The makedns command will configure the DNS on the management node to forward
                requests it does not know to these servers. Note that the DNS servers on the
                service nodes will ignore this value and always be configured to forward 
                to the management node.
  
   master:  The hostname of the xCAT management node, as known by the nodes.
  
   nameservers:  A comma delimited list of DNS servers that each node in the cluster should
                 use. This value will end up in the nameserver settings of the
                 /etc/resolv.conf on each node. It is common (but not required) to set
                 this attribute value to the IP addr of the xCAT management node, if
                 you have set up the DNS on the management node by running makedns.
                 In a hierarchical cluster, you can also set this attribute to
                 "<xcatmaster>" to mean the DNS server for each node should be the
                 node that is managing it (either its service node or the management
                 node).
  
   externaldns:  To specify that external dns is used. If externaldns is set to any value
                 then, makedns command will not start the local nameserver on xCAT MN. 
                 Default is to start the local nameserver.
  
   dnsupdaters:  The value are ',' separated string which will be added to the zone config
                 section. This is an interface for user to add configuration entries to
                 the zone sections in named.conf.
  
   dnsinterfaces:  The network interfaces DNS should listen on.  If it is the same for all
                   nodes, use a simple comma-separated list of NICs.  To specify different 
                   NICs for different nodes, use the format: "xcatmn|eth1,eth2;service|bond0", 
                   where xcatmn is the name of the management node, and DNS should listen on
                   the eth1 and eth2 interfaces.  All the nods in group 'service' should 
                   listen on the 'bond0' interface.
  
                   NOTE: If using this attribute to block certain interfaces, make sure
                   the IP maps to your hostname of xCAT MN is not blocked since xCAT needs
                   to use this IP to communicate with the local NDS server on MN.
  
   -------------------------
  HARDWARE CONTROL ATTRIBUTES
   -------------------------
   blademaxp:  The maximum number of concurrent processes for blade hardware control.
  
   ea_primary_hmc:  The hostname of the HMC that the Integrated Switch Network
                    Management Event Analysis should send hardware serviceable
                    events to for processing and potentially sending to IBM.
  
   ea_backup_hmc:  The hostname of the HMC that the Integrated Switch Network
                    Management Event Analysis should send hardware serviceable
                    events to if the primary HMC is down.
  
   enableASMI:  (yes/1 or no/0). If yes, ASMI method will be used after fsp-api. If no,
                 when fsp-api is used, ASMI method will not be used. Default is no.
  
   fsptimeout:  The timeout, in milliseconds, to use when communicating with FSPs.
  
   hwctrldispatch:  Whether or not to send hw control operations to the service
                    node of the target nodes. Default is 'y'.(At present, this attribute
                    is only used for IBM Flex System)
  
   ipmidispatch:  Whether or not to send ipmi hw control operations to the service
                  node of the target compute nodes. Default is 'y'.
  
   ipmimaxp:  The max # of processes for ipmi hw ctrl. The default is 64. Currently,
              this is only used for HP hw control.
  
   ipmiretries:  The # of retries to use when communicating with BMCs. Default is 3.
  
   ipmisdrcache:  If set to 'no', then the xCAT IPMI support will not cache locally
                  the target node's SDR cache to improve performance.
  
   ipmitimeout:  The timeout to use when communicating with BMCs. Default is 2.
                 This attribute is currently not used.
  
   maxssh:  The max # of SSH connections at any one time to the hw ctrl point for PPC
            This parameter doesn't take effect on the rpower command.
            It takes effects on other PPC hardware control command
            getmacs/rnetboot/rbootseq and so on. Default is 8.
  
   syspowerinterval:  For SystemP CECs, this is the number of seconds the rpower command
                      will wait between performing the action for each CEC.  For SystemX
                      IPMI servers, this is the number of seconds the rpower command will
                      wait between powering on <syspowermaxnodes> nodes at a time.  This
                      value is used to control the power on speed in large clusters. 
                      Default is 0.
  
   syspowermaxnodes:  The number of servers to power on at one time before waiting
                      'syspowerinterval' seconds to continue on to the next set of
                      nodes.  If the noderange given to rpower includes nodes served
                      by different service nodes, it will try to spread each set of
                      nodes across the service nodes evenly. Currently only used for
                      IPMI servers and must be set if 'syspowerinterval' is set.
  
   powerinterval:  The number of seconds the rpower command to LPARs will wait between
                   performing the action for each LPAR. LPARs of different HCPs
                   (HMCs or FSPs) are done in parallel. This is used to limit the
                   cluster boot up speed in large clusters. Default is 0.  This is
                   currently only used for system p hardware.
  
   ppcmaxp:  The max # of processes for PPC hw ctrl. If there are more than ppcmaxp
             hcps, this parameter will take effect. It will control the max number of
             processes for PPC hardware control commands. Default is 64.
  
   ppcretry:  The max # of PPC hw connection attempts to HMC before failing.
             It only takes effect on the hardware control commands through HMC. 
             Default is 3.
  
   ppctimeout:  The timeout, in milliseconds, to use when communicating with PPC hw
                through HMC. It only takes effect on the hardware control commands
                through HMC. Default is 0.
  
   snmpc:  The snmp community string that xcat should use when communicating with the
           switches.
  
   ---------------------------
  INSTALL/DEPLOYMENT ATTRIBUTES
   ---------------------------
   cleanupxcatpost:  (yes/1 or no/0). Set to 'yes' or '1' to clean up the /xcatpost
                     directory on the stateless and statelite nodes after the
                     postscripts are run. Default is no.
  
   db2installloc:  The location which the service nodes should mount for
                   the db2 code to install. Format is hostname:/path.  If hostname is
                   omitted, it defaults to the management node. Default is /mntdb2.
  
   defserialflow:  The default serial flow - currently only used by the mknb command.
  
   defserialport:  The default serial port - currently only used by mknb.
  
   defserialspeed:  The default serial speed - currently only used by mknb.
  
   genmacprefix:  When generating mac addresses automatically, use this manufacturing
                  prefix (e.g. 00:11:aa)
  
   genpasswords:  Automatically generate random passwords for BMCs when configuring
                  them.
  
   installdir:  The local directory name used to hold the node deployment packages.
  
   installloc:  The location from which the service nodes should mount the 
                deployment packages in the format hostname:/path.  If hostname is
                omitted, it defaults to the management node. The path must
                match the path in the installdir attribute.
  
   iscsidir:  The path to put the iscsi disks in on the mgmt node.
  
   mnroutenames:  The name of the routes to be setup on the management node.
                  It is a comma separated list of route names that are defined in the
                  routes table.
  
   runbootscripts:  If set to 'yes' the scripts listed in the postbootscripts
                    attribute in the osimage and postscripts tables will be run during
                    each reboot of stateful (diskful) nodes. This attribute has no
                    effect on stateless and statelite nodes. Run the following
                    command after you change the value of this attribute: 
                    'updatenode <nodes> -P setuppostbootscripts'
  
   precreatemypostscripts: (yes/1 or no/0). Default is no. If yes, it will  
                instruct xCAT at nodeset and updatenode time to query the db once for
                all of the nodes passed into the cmd and create the mypostscript file
                for each node, and put them in a directory of tftpdir(such as: /tftpboot)
                If no, it will not generate the mypostscript file in the tftpdir.
  
   setinstallnic:  Set the network configuration for installnic to be static.
  
   sharedtftp:  Set to 0 or no, xCAT should not assume the directory
                in tftpdir is mounted on all on Service Nodes. Default is 1/yes.
                If value is set to a hostname, the directory in tftpdir
                will be mounted from that hostname on the SN
  
   sharedinstall:  Indicates if a shared file system will be used for installation
                   resources. Possible values are: 'no', 'sns', or 'all'.  'no' 
                   means a shared file system is not being used.  'sns' means a
                   shared filesystem is being used across all service nodes.
                   'all' means that the management as well as the service nodes
                   are all using a common shared filesystem. The default is 'no'.
  
   xcatconfdir:  Where xCAT config data is (default /etc/xcat).
  
   xcatdebugmode:  the xCAT debug level. xCAT provides a batch of techniques
                   to help user debug problems while using xCAT, especially on OS provision,
                   such as collecting logs of the whole installation process and accessing
                   the installing system via ssh, etc. These techniques will be enabled
                   according to different xCAT debug levels specified by 'xcatdebugmode',
                   currently supported values:
                     '0':  disable debug mode
                     '1':  enable basic debug mode
                     '2':  enable expert debug mode
                   For the details on 'basic debug mode' and 'expert debug mode',
                   refer to xCAT documentation.
  
   --------------------
  REMOTESHELL ATTRIBUTES
   --------------------
   nodesyncfiledir:  The directory on the node, where xdcp will rsync the files
  
   SNsyncfiledir:  The directory on the Service Node, where xdcp will rsync the files
                   from the MN that will eventually be rsync'd to the compute nodes.
  
   sshbetweennodes:  Comma separated list of groups of compute nodes to enable passwordless
                     root ssh to the nodes during install or running 'xdsh -K'. The default
                     is ALLGROUPS.  Set to NOGROUPS to disable.
  
                     Service Nodes are not affected by this attribute as they are always
                     configured with passwordless root access.
                     If using the zone table, this attribute in not used.
  
   -----------------
  SERVICES ATTRIBUTES
   -----------------
   consoleondemand:  When set to 'yes', conserver connects and creates the console
                     output only when the user opens the console. Default is 'no' on
                     Linux, 'yes' on AIX.
  
   httpport:    The port number that the booting/installing nodes should contact the
                http server on the MN/SN on. It is your responsibility to configure
                the http server to listen on that port - xCAT will not do that.
  
   nmapoptions: Additional options for the nmap command. nmap is used in pping, 
                nodestat, xdsh -v and updatenode commands. Sometimes additional 
                performance tuning may be needed for nmap due to network traffic.
                For example, if the network response time is too slow, nmap may not
                give stable output. You can increase the timeout value by specifying 
                '--min-rtt-timeout 1s'. xCAT will append the options defined here to 
                the nmap command.
  
   ntpservers:  A comma delimited list of NTP servers for the service node and
                the compute node to sync with. The keyword <xcatmaster> means that
                the node's NTP server is the node that is managing it
                (either its service node or the management node).
  
   extntpservers:  A comma delimited list of external NTP servers for the xCAT
                   management node to sync with. If it is empty, the NTP server
                   will use the management node's own hardware clock to calculate
                   the system date and time
  
   svloglocal:  If set to 1, syslog on the service node will not get forwarded to the
                management node.
  
   timezone:  (e.g. America/New_York)
  
   tftpdir:  The tftp directory path. Default is /tftpboot
  
   tftpflags:  The flags that used to start tftpd. Default is '-v -l -s /tftpboot 
                 -m /etc/tftpmapfile4xcat.conf' if tftplfags is not set
  
   useNmapfromMN:  When set to yes, nodestat command should obtain the node status
                   using nmap (if available) from the management node instead of the
                   service node. This will improve the performance in a flat network.
  
   vsftp:  Default is 'n'. If set to 'y', xcatd on the management node will automatically
           start vsftpd.  (vsftpd must be installed by the admin).  This setting does not
           apply to service nodes.  For service nodes, set servicenode.ftpserver=1.
  
   FQDNfirst:  Fully Qualified Domain Name first. If set to 1/yes/enable, the /etc/hosts 
               entries generated by 'makehosts' will put the FQDN before the PQDN(Partially 
               Qualified Domain Name). Otherwise, the original behavior will be performed.
  
   hierarchicalattrs:  Table attributes(e.g. postscripts, postbootscripts) that will be
                       included hierarchically. Attribute values for all the node's groups
                       will be applied to the node in the groups' order except the repeat one.
  
   -----------------------
  VIRTUALIZATION ATTRIBUTES
   -----------------------
   usexhrm:  Have xCAT execute the xHRM script when booting up KVM guests to configure
             the virtual network bridge.
  
   vcenterautojoin:  When set to no, the VMWare plugin will not attempt to auto remove
                     and add hypervisors while trying to perform operations.  If users
                     or tasks outside of xCAT perform the joining this assures xCAT
                     will not interfere.
  
   vmwarereconfigonpower:  When set to no, the VMWare plugin will make no effort to
                           push vm.cpus/vm.memory updates from xCAT to VMWare.
  
   persistkvmguests:  Keep the kvm definition on the kvm hypervisor when you power off
                      the kvm guest node. This is useful for you to manually change the 
                      kvm xml definition file in virsh for debugging. Set anything means
                      enable.
  
   --------------------
  XCAT DAEMON ATTRIBUTES
   --------------------
   useflowcontrol:  (yes/1 or no/0). If yes, the postscript processing on each node
                 contacts xcatd on the MN/SN using a lightweight UDP packet to wait
                 until xcatd is ready to handle the requests associated with
                 postscripts.  This prevents deploying nodes from flooding xcatd and
                 locking out admin interactive use. This value works with the
                 xcatmaxconnections and xcatmaxbatch attributes. Is not supported on AIX.
                 If the value is no, nodes sleep for a random time before contacting
                 xcatd, and retry. The default is no.
                 See the following document for details:
                 Hints_and_Tips_for_Large_Scale_Clusters
  
   xcatmaxconnections:  Number of concurrent xCAT protocol requests before requests
                        begin queueing. This applies to both client command requests
                        and node requests, e.g. to get postscripts. Default is 64.
  
   xcatmaxbatchconnections:  Number of concurrent xCAT connections allowed from the nodes.
                        Value must be less than xcatmaxconnections. Default is 50.
  
   xcatdport:  The port used by the xcatd daemon for client/server communication.
  
   xcatiport:  The port used by xcatd to receive install status updates from nodes.
  
   xcatlport:  The port used by xcatd command log writer process to collect command output.
  
   xcatsslversion:  The ssl version by xcatd. Default is SSLv3.
  
   xcatsslciphers:  The ssl cipher by xcatd. Default is 3DES.
 
 


\ **value**\ 
 
 The value of the attribute specified in the "key" column.
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

