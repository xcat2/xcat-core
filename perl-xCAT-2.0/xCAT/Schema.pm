# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::Schema;

#  When making additions or deletions to this file please be sure to
#       modify BOTH the tabspec and defspec definitions.  This includes
#       adding descriptions for any new attributes.

#Note that the SQL is far from imaginative.  Fact of the matter is that
#certain SQL backends don't ascribe meaning to the data types anyway.
#New format, not sql statements, but info enough to describe xcat tables
%tabspec = (
  ppchcp => {
    cols => [qw(hcp username password comments disable)],
    keys => [qw(hcp)],
  },
  ppc => {
    cols => [qw(node hcp id profile parent comments disable)],
    keys => [qw(node)],
  },
  ppcdirect => {
    cols => [qw(hcp username password comments disable)],
    keys => [qw(hcp)],
  },
  nodetype => {
    cols => [qw(node os arch profile comments disable)],
    keys => [qw(node)],
  },
  nodepos => {
    cols => [qw(node rack u chassis slot room comments disable)],
    keys => [qw(node)],
  },
  iscsi => {
	cols => [qw(node server target userid passwd comments disable)],
  	keys => [qw(node)],
  },
  vpd => {
    cols => [qw(node serial mtm comments disable)],
    keys => [qw(node)],
  },
  nodehm => {
    cols => [qw(node power mgt cons termserver termport conserver serialspeed serialflow getmac comments disable)],
    keys => [qw(node)],
  },
  hosts => {
    cols => [qw(node ip hostnames comments disable)],
    keys => [qw(node)],
  },
  mp => {
    cols => [qw(node mpa id comments disable)],
    keys => [qw(node)],
  },
  mpa => {
    cols => [qw(mpa username password comments disable)],
    keys => [qw(mpa)],
  },
  mac => {
    cols => [qw(node interface mac comments disable)],
    keys => [qw(node interface)],
  },
  chain => {
    cols => [qw(node currstate currchain chain ondiscover comments disable)],
    keys => [qw(node)],
  },
  noderes => {
    cols => [qw(node servicenode netboot tftpserver nfsserver monserver kernel initrd kcmdline nfsdir serialport installnic primarynic xcatmaster current_osimage next_osimage comments disable)],
    keys => [qw(node)],
  },
  networks => {
    cols => [qw(netname net mask gateway dhcpserver tftpserver nameservers dynamicrange comments disable)],
    keys => [qw(net mask)]
  },
  osimage  => {
	cols => [qw(imagename osname osvers osdistro osarch comments disable)],
	keys => [qw(imagename)]
  },
  nodegroup => {
	cols => [qw(groupname grouptype members wherevals comments disable)],
	keys => [qw(groupname)]
  },
  switch =>  {
    cols => [qw(node switch vlan port comments disable)],
    keys => [qw(node switch port)]
  },
  nodelist => {
    cols => [qw(node nodetype groups status comments disable)],
    keys => [qw(node)],
  },
  site => {
    cols => [qw(key value comments disable)],
    keys => [qw(key)]
  },
#  site => {
#    cols => [qw(sitename domain master rsh rcp xcatdport installdir comments disable)],
#    keys => [qw(sitename)]
#  },
  passwd => {
    cols => [qw(key username password comments disable)],
    keys => [qw(key)]
  },
  ipmi => {
    cols => [qw(node bmc username password comments disable )],
    keys => [qw(node)]
  },
  policy => {
    cols => [qw(priority name host commands noderange parameters time rule comments disable)],
    keys => [qw(priority)]
  },
  notification => {
    cols => [qw(filename tables tableops comments disable)],
    keys => [qw(filename)],
    required => [qw(tables filename)]
  },
  monitoring => {
    cols => [qw(pname nodestatmon comments disable)],
    keys => [qw(pname)],
    required => [qw(pname)]
  }
  );



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
  monitoring => { attrs => [], attrhash => {}, objkey => 'pname' },
  notification => { attrs => [], attrhash => {}, objkey => 'filename' }
);
  
@{$defspec{node}->{'attrs'}} = (
		{attr_name => 'node',
                 tabentry => 'nodelist.node',
				access_tabentry => 'nodelist.node=attr:node',
				description => 'The name of this node definition.'},
        {attr_name => 'nodetype',
                 tabentry => 'nodelist.nodetype',
                 access_tabentry => 'nodelist.node=attr:node',
                 description => 'Specifies a comma-separated list of node type values. (Valid values: osi, hmc, fsp, blade, vm, lpar, ivm, bpa, mm, rsa, switch)'},
		{attr_name => 'groups',
                 tabentry => 'nodelist.groups',
                 access_tabentry => 'nodelist.node=attr:node',
                 description => 'Comma separated list of groups this node belongs to.'},
        {attr_name => 'xcatmaster',
                 tabentry => 'noderes.xcatmaster',
                 access_tabentry => 'noderes.node=attr:node',
				description => 'The hostname of the xCAT management node.'},
#       {attr_name => 'mgtnet',
#                 tabentry => 'noderes.mgtnet',
#                 access_tabentry => 'noderes.node=attr:node',
#                 description => 'The name of the xCAT network definition for this node.'},
        {attr_name => 'servicenode',
                 tabentry => 'noderes.servicenode',
                 access_tabentry => 'noderes.node=attr:node',
				description => '??????.'},
		{attr_name => 'kernel',
                 tabentry => 'noderes.kernel',
                 access_tabentry => 'noderes.node=attr:node',
                description => '??????.'},
		{attr_name => 'initrd',
                 tabentry => 'noderes.initrd',
                 access_tabentry => 'noderes.node=attr:node',
                description => '??????.'},
		{attr_name => 'kcmdline',
                 tabentry => 'noderes.kcmdline',
                 access_tabentry => 'noderes.node=attr:node',
                description => '??????.'},
        {attr_name => 'mgt',
                 tabentry => 'nodehm.mgt',
                 access_tabentry => 'nodehm.node=attr:node',
				description => 'Specifies the hardware management method.'},
        {attr_name => 'power',
                 tabentry => 'nodehm.power',
                 access_tabentry => 'nodehm.node=attr:node',
				description => 'Specifies the power method.'},
        {attr_name => 'cons',
                 tabentry => 'nodehm.cons',
                 access_tabentry => 'nodehm.node=attr:node',
				description => 'Specifies the console method.'},
        {attr_name => 'termserver',
                 tabentry => 'nodehm.termserver',
                 access_tabentry => 'nodehm.node=attr:node',
				description => 'The name of the terminal server.'},
        {attr_name => 'termport',
                 tabentry => 'nodehm.termport',
                 access_tabentry => 'nodehm.node=attr:node',
				description => '??????.'},
        {attr_name => 'conserver',
                 tabentry => 'nodehm.conserver',
                 access_tabentry => 'nodehm.node=attr:node',
				description => '??????.'},
        {attr_name => 'getmac',
                 tabentry => 'nodehm.getmac',
                 access_tabentry => 'nodehm.node=attr:node',
				description => '??????.'},
        {attr_name => 'serialport',
                 tabentry => 'noderes.serialport',
                 access_tabentry => 'noderes.node=attr:node',
				description => '??????.'},
        {attr_name => 'serialspeed',
                 tabentry => 'nodehm.serialspeed',
                 access_tabentry => 'nodehm.node=attr:node',
				description => '??????.'},
        {attr_name => 'serialflow',
                 tabentry => 'nodehm.serialflow',
                 access_tabentry => 'nodehm.node=attr:node',
				description => '??????.'},
        {attr_name => 'ip',
                 tabentry => 'hosts.ip',
                 access_tabentry => 'hosts.node=attr:node',
				description => '??????.'},
        {attr_name => 'hostnames',
                 tabentry => 'hosts.hostnames',
                 access_tabentry => 'hosts.node=attr:node',
				description => '??????.'},
        {attr_name => 'serialnumber',
                 tabentry => 'vpd.serial',
                 access_tabentry => 'vpd.node=attr:node',
				description => '??????.'},
        {attr_name => 'mtm',
                 tabentry => 'vpd.mtm',
                 access_tabentry => 'vpd.node=attr:node',
				description => '??????.'},
        {attr_name => 'rackloc',
                 tabentry => 'nodepos.rack',
                 access_tabentry => 'nodepos.node=attr:node',
				description => '??????.'},
        {attr_name => 'unitloc',
                 tabentry => 'nodepos.u',
                 access_tabentry => 'nodepos.node=attr:node',
				description => '??????.'},
        {attr_name => 'chassisloc',
                 tabentry => 'nodepos.chassis',
                 access_tabentry => 'nodepos.node=attr:node',
				description => '??????.'},
        {attr_name => 'slotloc',
                 tabentry => 'nodepos.slot',
                 access_tabentry => 'nodepos.node=attr:node',
				description => '??????.'},
        {attr_name => 'roomloc',
                 tabentry => 'nodepos.room',
                 access_tabentry => 'nodepos.node=attr:node',
				description => '??????.'},
		{attr_name => 'usercomment',
                 tabentry => 'nodelist.comments',
                 access_tabentry => 'nodelist.node=attr:node',
                description => 'User comment.'},
		{attr_name => 'interface',
                 tabentry => 'mac.interface',
                 access_tabentry => 'mac.node=attr:node',
                description => 'The Ethernet adapter interface name that will be used to install and manage the node. (For example, eth0 or en0.)'},
		{attr_name => 'mac',
                 tabentry => 'mac.mac',
                 access_tabentry => 'mac.node=attr:node',
                description => 'The machine address of the network adapter used for deployment.'},
		{attr_name => 'currstate',
                 tabentry => 'chain.currstate',
                 access_tabentry => 'chain.node=attr:node',
                description => '?????'},
		{attr_name => 'currchain',
                 tabentry => 'chain.currchain',
                 access_tabentry => 'chain.node=attr:node',
                description => '?????'},
		{attr_name => 'chain',
                 tabentry => 'chain.chain',
                 access_tabentry => 'chain.node=attr:node',
                description => '?????'},
		{attr_name => 'ondiscover',
                 tabentry => 'chain.ondiscover',
                 access_tabentry => 'chain.node=attr:node',
                description => '?????'},

     # Conditional attributes:
     #    OSI node attributes:

        {attr_name => 'tftpserver',
                 only_if => 'nodetype=osi',
                 tabentry => 'noderes.tftpserver',
                 access_tabentry => 'noderes.node=attr:node',
				description => '??????.'},
        {attr_name => 'nfsserver',
                 only_if => 'nodetype=osi',
                 tabentry => 'noderes.nfsserver',
                 access_tabentry => 'noderes.node=attr:node',
				description => '??????.'},
        {attr_name => 'nfsdir',
                 only_if => 'nodetype=osi',
                 tabentry => 'noderes.nfsdir',
                 access_tabentry => 'noderes.node=attr:node',
				description => '??????.'},
        {attr_name => 'primarynic',
                 only_if => 'nodetype=osi',
                 tabentry => 'noderes.primarynic',
                 access_tabentry => 'noderes.node=attr:node',
				description => '??????.'},
        {attr_name => 'installnic',
                 only_if => 'nodetype=osi',
                 tabentry => 'noderes.installnic',
                 access_tabentry => 'noderes.node=attr:node',
				description => '??????.'},
        {attr_name => 'netboot',
                 only_if => 'nodetype=osi',
                 tabentry => 'noderes.netboot',
                 access_tabentry => 'noderes.node=attr:node',
				description => '??????.'},
        {attr_name => 'current_osimage',
                 only_if => 'nodetype=osi',
                 tabentry => 'noderes.current_osimage',
                 access_tabentry => 'noderes.node=attr:node',
				description => '??????.'},
        {attr_name => 'next_osimage',
                 only_if => 'nodetype=osi',
                 tabentry => 'noderes.next_osimage',
                 access_tabentry => 'noderes.node=attr:node',
				description => '??????.'},

     #    Hardware Control node attributes:

# add hcp username password id profile mgt

        {attr_name => hcp,
                 only_if => 'mgt=hmc',
                 tabentry => 'ppc.hcp',
                 access_tabentry => 'ppc.node=attr:node',
				description => 'The host name or IP address of the network interface for the hardware control point.'},
		{attr_name => id,
                 only_if => 'mgt=hmc',
                 tabentry => 'ppc.id',
                 access_tabentry => 'ppc.node=attr:node',
                description => '?????'},
		{attr_name => profile,            
                 only_if => 'mgt=hmc',              
                 tabentry => 'ppc.profile',           
                 access_tabentry => 'ppc.node=attr:node',              
                description => '?????'},
		{attr_name => id,            
                 only_if => 'mgt=hmc',              
                 tabentry => 'ppc.id',           
                 access_tabentry => 'ppc.node=attr:node',              
                description => '?????'},

				
#       {attr_name => hdwctrlpoint,
#                 only_if => 'mgtmethod=hmc',
#                 tabentry => 'ppc.hcp',
#                 access_tabentry => 'ppc.node=attr:node'},
        {attr_name => hdwctrlpoint,
                 only_if => 'mgtmethod=ipmi',
                 tabentry => 'ipmi.bmc',
                 access_tabentry => 'ipmi.node=attr:node'},
        {attr_name => hdwctrlnodeid,
                 only_if => 'mgtmethod=mp',
                 tabentry => 'mp.id',
                 access_tabentry => 'mp.node=attr:node',
				description => '??????.'},
#       {attr_name => hdwctrlnodeid,
#                 only_if => 'mgtmethod=hmc',
#                 tabentry => 'ppc.id',
#                 access_tabentry => 'ppc.node=attr:node'}
             );
             
@{$defspec{osimage}->{'attrs'}} = (
        {attr_name => 'imagename',
                 tabentry => 'osimage.imagename',
                 access_tabentry => 'osimage.imagename=attr:imagename',
                 description => 'The name of this operating system image.'},
		{attr_name => 'osdistro',
                 tabentry => 'osimage.osdistro',
                 access_tabentry => 'osimage.imagename=attr:imagename',
                 description => 'The Linux distribution name to be deployed. The valid values are RedHat, and SLES.'},
        {attr_name => 'osname',
                 tabentry => 'osimage.osname',
                 access_tabentry => 'osimage.imagename=attr:imagename',
                 description => 'The name of the operating system to be deployed. The expected values are AIX or Linux.'},
		{attr_name => 'osvers',
                 tabentry => 'osimage.osvers',
                 access_tabentry => 'osimage.imagename=attr:imagename',
                 description => 'The operating system version to be deployed. The formats for the values are "version.release.mod" for AIX and "version" for Linux. (ex. AIX: "5.3.0", Linux: "5").'},
		{attr_name => 'osarch',
                 tabentry => 'osimage.osarch',
                 access_tabentry => 'osimage.imagename=attr:imagename',
                 description => 'The node machine architecture.'},
		{attr_name => 'usercomment',
                 tabentry => 'osimage.comments',
                 access_tabentry => 'osimage.imagename=attr:imagename',
                description => 'User comment.'},
             );
             
@{$defspec{network}->{'attrs'}} = (
        {attr_name => 'netname',
                 tabentry => 'networks.netname',
                 access_tabentry => 'networks.netname=attr:netname',
                 description => 'Name used to identify this network definition.'},
        {attr_name => 'net',
                 tabentry => 'networks.net',
                 access_tabentry => 'networks.netname=attr:netname',
				description => '??????.'},
        {attr_name => 'mask',
                 tabentry => 'networks.mask',
                 access_tabentry => 'networks.netname=attr:netname',
				description => 'The network mask.'},
        {attr_name => 'gateway',
                 tabentry => 'networks.gateway',
                 access_tabentry => 'networks.netname=attr:netname',
				description => 'Specifies the hostname or IP address of the network gateway.'},
        {attr_name => 'dhcpserver',
                 tabentry => 'networks.dhcpserver',
                 access_tabentry => 'networks.netname=attr:netname',
				description => '??????.'},
        {attr_name => 'tftpserver',
                 tabentry => 'networks.tftpserver',
                 access_tabentry => 'networks.netname=attr:netname',
				description => '??????.'},
        {attr_name => 'nameservers',
                 tabentry => 'networks.nameservers',
                 access_tabentry => 'networks.netname=attr:netname',
				description => '??????.'},
        {attr_name => 'dynamicrange',
                 tabentry => 'networks.dynamicrange',
                 access_tabentry => 'networks.netname=attr:netname',
				description => '??????.'},
		{attr_name => 'usercomment',
                 tabentry => 'networks.comments',
                 access_tabentry => 'networks.netname=attr:netname',
                description => 'User comment.'},
             );

@{$defspec{site}->{'attrs'}} = (
        {attr_name => 'key',
                 tabentry => 'site.key',
                 access_tabentry => 'site.key=attr:key',
                 description => 'The name of the attribute.'},
		{attr_name => 'value',
                 tabentry => 'site.value',
                 access_tabentry => 'site.key=attr:key',
                 description => 'The value of the attribute.'},
		{attr_name => 'comments',
                 tabentry => 'site.comments',
                 access_tabentry => 'site.key=attr:key',
                 description => 'User comments.'},
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
#				access_tabentry => 'site.sitename=attr:sitename',
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


@{$defspec{group}->{'attrs'}} = (
        {attr_name => 'groupname',
                 tabentry => 'nodegroup.groupname',
                 access_tabentry => 'nodegroup.groupname=attr:groupname',
                 description => 'The name of this xCAT group object definition.'},
        {attr_name => 'grouptype',
                 tabentry => 'nodegroup.grouptype',
                 access_tabentry => 'nodegroup.groupname=attr:groupname',
                 description => 'The type of xCAT group - either "static" or "dynamic".'},
        {attr_name => 'members',
                 tabentry => 'nodegroup.members',
                 access_tabentry => 'nodegroup.groupname=attr:groupname',
                 description => 'The list of members for this group.'},
		{attr_name => 'wherevals',
                 tabentry => 'nodegroup.wherevals',
                 access_tabentry => 'nodegroup.groupname=attr:groupname',
                 description => 'A list of comma-separated "attr=val" pairs that can be used to determine the members of a dynamic group.'},
		{attr_name => 'usercomment',
                 tabentry => 'nodegroup.comments',
                 access_tabentry => 'nodegroup.groupname=attr:groupname',
                description => 'User comment.'},

#
#  Node attrs that can be used with static groups - from above!!!!
#
			);

@{$defspec{policy}->{'attrs'}} = (
        {attr_name => 'priority',
                 tabentry => 'policy.priority',
                 access_tabentry => 'policy.priority=attr:priority',
				description => '??????.'},
        {attr_name => 'name',
                 tabentry => 'policy.name',
                 access_tabentry => 'policy.priority=attr:priority',
				description => '??????.'},
        {attr_name => 'host',
                 tabentry => 'policy.host',
                 access_tabentry => 'policy.priority=attr:priority',
				description => '??????.'},
        {attr_name => 'commands',
                 tabentry => 'policy.commands',
                 access_tabentry => 'policy.priority=attr:priority',
				description => '??????.'},
        {attr_name => 'noderange',
                 tabentry => 'policy.noderange',
                 access_tabentry => 'policy.priority=attr:priority',
				description => '??????.'},
        {attr_name => 'parameters',
                 tabentry => 'policy.parameters',
                 access_tabentry => 'policy.priority=attr:priority',
				description => '??????.'},
        {attr_name => 'time',
                 tabentry => 'policy.time',
                 access_tabentry => 'policy.priority=attr:priority',
				description => '??????.'},
        {attr_name => 'rule',
                tabentry => 'policy.rule',
				access_tabentry => 'policy.priority=attr:priority',
				description => '??????.'},
		{attr_name => 'usercomment',
                 tabentry => 'policy.comments',
                 access_tabentry => 'policy.priority=attr:priority',
                description => 'User comment.'},
             );

@{$defspec{notification}->{'attrs'}} = (
	{attr_name => 'filename',
                 tabentry => 'notification.filename',
                 access_tabentry => 'notification.filename=attr:filename',
                 description => 'Specifies a file that implements the callback routine when the monitored table changes.'},
	{attr_name => 'tables',
                 tabentry => 'notification.tables',
                 access_tabentry => 'notification.filename=attr:filename',
                 description => 'The name of the xCAT database table to monitor.'},
        {attr_name => 'tableops',
                 tabentry => 'notification.tableops',
                 access_tabentry => 'notification.filename=attr:filename',
                 description => 'Specifies the table operation to monitor. It can be "d" for rows deleted, "a" for rows added or "u" for rows updated.'},
        {attr_name => 'comments',
                 tabentry => 'notification.comments',
                 access_tabentry => 'notification.filename=attr:filename',
                 description => 'User comment.'},
	 );
	 
@{$defspec{monitoring}->{'attrs'}} = (
        {attr_name => 'pname',
                 tabentry => 'monitoring.pname',
                 access_tabentry => 'monitoring.pname=attr:pname',
                 description => 'The product short name of the 3rd party monitor
ing software.'},
        {attr_name => 'nodestatmon',
                 tabentry => 'monitoring.nodestatmon',
                 access_tabentry => 'monitoring.pname=attr:pname',
                 description => 'Specifies if the product is used to feed the no
de status to the xCAT cluster.'},
        {attr_name => 'comments',
                 tabentry => 'monitoring.comments',
                 access_tabentry => 'monitoring.pname=attr:pname',
                 description => 'User comment.'},
);
