# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::Schema;

#  When making additions or deletions to this file please be sure to
#       modify BOTH the tabspec and defspec definitions.  This includes
#       adding descriptions for any new attributes.


#Note that the SQL is far from imaginative.  Fact of the matter is that
#certain SQL backends don't ascribe meaning to the data types anyway.
#New format, not sql statements, but info enough to describe xcat tables
%tabspec = (
  deps => {
    cols => [qw(node nodedep msdelay cmd comments disable)],
    keys => [qw(node)],
  },
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
    cols => [qw(node server target file userid passwd kernel kcmdline initrd comments disable)],
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
    keys => [qw(node)],
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
    cols => [qw(netname net mask mgtifname gateway dhcpserver tftpserver nameservers dynamicrange nodehostname comments disable)],
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
    cols => [qw(node switch port vlan comments disable)],
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
  postscripts => {
    cols => [qw(node postscripts)],
    keys => [qw(node)],
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
    cols => [qw(name nodestatmon comments disable)],
    keys => [qw(name)],
    required => [qw(name)]
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
		description => 'The list of post install scripts .'},
####################
#  noderes table   # 
####################
        {attr_name => 'xcatmaster',
                 tabentry => 'noderes.xcatmaster',
                 access_tabentry => 'noderes.node=attr:node',
		description => 'The hostname of the xCAT management node as known from this node.'},
###
# TODO:  Need to check/update code to make sure it really uses servicenode as
#        default if other server value not set
###
        {attr_name => 'servicenode',
                 tabentry => 'noderes.servicenode',
                 access_tabentry => 'noderes.node=attr:node',
		description => 'The node that provides most services for this node.  This is the default value if nfsserver, tftpserver, monserver, etc., are not set.'},
        {attr_name => 'tftpserver',
                 only_if => 'nodetype=osi',
                 tabentry => 'noderes.tftpserver',
                 access_tabentry => 'noderes.node=attr:node',
		description => 'The TFTP server for this node.'},
        {attr_name => 'nfsserver',
                 only_if => 'nodetype=osi',
                 tabentry => 'noderes.nfsserver',
                 access_tabentry => 'noderes.node=attr:node',
		description => 'The NFS server for this node.'},
###
# TODO:  Is noderes.nfsdir used anywhere?  Could not find any code references
#        to this attribute.
###
        {attr_name => 'nfsdir',
                 only_if => 'nodetype=osi',
                 tabentry => 'noderes.nfsdir',
                 access_tabentry => 'noderes.node=attr:node',
		description => '???  not sure if this is used ??? '},
        {attr_name => 'monserver',
                 only_if => 'nodetype=osi',
                 tabentry => 'noderes.monserver',
                 access_tabentry => 'noderes.node=attr:node',
		description => 'The monitoring server for this node.'},
	{attr_name => 'kernel',
                 tabentry => 'noderes.kernel',
                 access_tabentry => 'noderes.node=attr:node',
                description => 'The linux kernel image used to deploy the node.'},
	{attr_name => 'initrd',
                 tabentry => 'noderes.initrd',
                 access_tabentry => 'noderes.node=attr:node',
                description => 'The linux initial ramdisk image used to deploy the node.'},
	{attr_name => 'kcmdline',
                 tabentry => 'noderes.kcmdline',
                 access_tabentry => 'noderes.node=attr:node',
                description => 'The kernel command line used to deploy the node..'},
        # Note that the serialport attr is actually defined down below
        # with the other serial*  attrs from the nodehm table
        #{attr_name => 'serialport',
        #         tabentry => 'noderes.serialport',
        #         access_tabentry => 'noderes.node=attr:node',
        #	description => 'The serial port for this node.  For SOL on blades, this is typically 1.  For IPMI, this is typically 0.'},
        {attr_name => 'primarynic',
                 only_if => 'nodetype=osi',
                 tabentry => 'noderes.primarynic',
                 access_tabentry => 'noderes.node=attr:node',
		description => 'The network adapter on the node that will be used for xCAT management.  Default is eth0.'},
        {attr_name => 'installnic',
                 only_if => 'nodetype=osi',
                 tabentry => 'noderes.installnic',
                 access_tabentry => 'noderes.node=attr:node',
		description => 'The network adapter on the node that will be used for OS deployment.  If not set, the primarynic will be used.'},
        {attr_name => 'netboot',
                 only_if => 'nodetype=osi',
                 tabentry => 'noderes.netboot',
                 access_tabentry => 'noderes.node=attr:node',
		description => 'The type of network booting supported by this node.  Possible values are:  pxe, yaboot'},
        {attr_name => 'current_osimage',
                 only_if => 'nodetype=osi',
                 tabentry => 'noderes.current_osimage',
                 access_tabentry => 'noderes.node=attr:node',
		description => 'The name of the osimage data object that represents the OS image currently deployed to this node.  ??? Currently not used. ???'},
        {attr_name => 'next_osimage',
                 only_if => 'nodetype=osi',
                 tabentry => 'noderes.next_osimage',
                 access_tabentry => 'noderes.node=attr:node',
		description => 'The name of the osimage data object that represents the OS image that will be installed on the node the next time it is deployed.  ??? Currently not used. ???'},

######################
#  nodetype table    # 
######################
        {attr_name => 'arch',
                 tabentry => 'nodetype.arch',
                 access_tabentry => 'nodetype.node=attr:node',
		description => 'Specifies the hardware architecture for this node.'},
# TODO:  need to decide what to do with the os attr once the osimage stuff is
#        implemented.  The nodetype.os attr may be moved to the osimage table.
        {attr_name => 'os',
                 only_if => 'nodetype=osi',
                 tabentry => 'nodetype.os',
                 access_tabentry => 'nodetype.node=attr:node',
		description => 'Specifies the operating system for this node.'},
# TODO:  need to decide what to do with the profile attr once the osimage 
#        stuff is implemented.  May want to move this to the osimage table.
        {attr_name => 'profile',
                 only_if => 'nodetype=osi',
                 tabentry => 'nodetype.profile',
                 access_tabentry => 'nodetype.node=attr:node',
		description => 'Specifies the template used for OS deployment of this node.'},
####################
#  iscsi table     # 
####################
	{attr_name => iscsiserver,            
                 only_if => 'nodetype=osi',              
                 tabentry => 'iscsi.server',           
                 access_tabentry => 'iscsi.node=attr:node',              
                description => 'The server containing the iscsi boot device for this node.'},
	{attr_name => iscsitarget,            
                 only_if => 'nodetype=osi',              
                 tabentry => 'iscsi.target',           
                 access_tabentry => 'iscsi.node=attr:node',              
                description => 'The target of the iscsi disk used for boot device for this node.'},
	{attr_name => iscsiuserid,            
                 only_if => 'nodetype=osi',              
                 tabentry => 'iscsi.userid',           
                 access_tabentry => 'iscsi.node=attr:node',              
                description => 'The userid of the iscsi server containing the boot device for this node.'},
	{attr_name => iscsipassword,            
                 only_if => 'nodetype=osi',              
                 tabentry => 'iscsi.passwd',           
                 access_tabentry => 'iscsi.node=attr:node',              
                description => 'The password for the iscsi server containing the boot device for this node.'},
####################
#  nodehm table    # 
####################
        {attr_name => 'mgt',
                 tabentry => 'nodehm.mgt',
                 access_tabentry => 'nodehm.node=attr:node',
		description => 'Specifies the hardware management method.  Valid methods are ipmi, blade, hmc, ivm, fsp.'},
        {attr_name => 'power',
                 tabentry => 'nodehm.power',
                 access_tabentry => 'nodehm.node=attr:node',
		description => 'Specifies the power method. If not set, the mgt attribute will be use.'},
        {attr_name => 'cons',
                 tabentry => 'nodehm.cons',
                 access_tabentry => 'nodehm.node=attr:node',
		description => 'Specifies the console method. If not set, the mgt attribute will be use.'},
        {attr_name => 'termserver',
                 tabentry => 'nodehm.termserver',
                 access_tabentry => 'nodehm.node=attr:node',
		description => 'The name of the terminal server.'},
        {attr_name => 'termport',
                 tabentry => 'nodehm.termport',
                 access_tabentry => 'nodehm.node=attr:node',
		description => 'The terminal port on the console server for this node.'},
###
# TODO:  is nodehm.conserver used anywhere?  I couldn't find any code references
###
        {attr_name => 'conserver',
                 tabentry => 'nodehm.conserver',
                 access_tabentry => 'nodehm.node=attr:node',
		description => '???  not sure if this is used ???.'},
###
# TODO:  is nodehm.getmac used anywhere?  I couldn't find any code references
###
        {attr_name => 'getmac',
                 tabentry => 'nodehm.getmac',
                 access_tabentry => 'nodehm.node=attr:node',
		description => '???  not sure if this is used ???.'},
        # Note that serialport is in the noderes table.  Keeping it here in
        # the defspec so that it gets listed with the other serial* attrs
        {attr_name => 'serialport',
                 tabentry => 'noderes.serialport',
                 access_tabentry => 'noderes.node=attr:node',
		description => 'The serial port for this node.  For SOL on blades, this is typically 1.  For IPMI, this is typically 0.'},
        {attr_name => 'serialspeed',
                 tabentry => 'nodehm.serialspeed',
                 access_tabentry => 'nodehm.node=attr:node',
		description => 'The speed of the serial port for this node.  For SOL on blades, this is typically 19200. '},
        {attr_name => 'serialflow',
                 tabentry => 'nodehm.serialflow',
                 access_tabentry => 'nodehm.node=attr:node',
		description => 'The flow value of the serial port for this node.  For SOL on blades, this is typically \"hard\".'},
##################
#  vpd table     # 
##################
        {attr_name => 'serial',
                 tabentry => 'vpd.serial',
                 access_tabentry => 'vpd.node=attr:node',
		description => 'Serial number.'},
        {attr_name => 'mtm',
                 tabentry => 'vpd.mtm',
                 access_tabentry => 'vpd.node=attr:node',
		description => 'Machine type model.'},
##################
#  mac table     # 
##################
	{attr_name => 'interface',
                 tabentry => 'mac.interface',
                 access_tabentry => 'mac.node=attr:node',
                description => 'The Ethernet adapter interface name that will be used to install and manage the node. (For example, eth0 or en0.)'},
	{attr_name => 'mac',
                 tabentry => 'mac.mac',
                 access_tabentry => 'mac.node=attr:node',
                description => 'The machine address of the network adapter used for deployment.'},
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
                description => 'A comma-delimited chain of actions to be performed automatically for this node. Valid actions include:  discover, boot or reboot, install or netboot, runcmd=<cmd>, runimage=<image>, shell, standby (default - same as no chain) '},
###
# TODO:  What is chain.ondiscover used for?  Could not find any code references
#        to this table entry
###
	{attr_name => 'ondiscover',
                 tabentry => 'chain.ondiscover',
                 access_tabentry => 'chain.node=attr:node',
                description => '?? not sure if this is used ???'},
	{attr_name => 'currstate',
                 tabentry => 'chain.currstate',
                 access_tabentry => 'chain.node=attr:node',
                description => 'The current chain state for this node.  Set by xCAT.'},
	{attr_name => 'currchain',
                 tabentry => 'chain.currchain',
                 access_tabentry => 'chain.node=attr:node',
                description => 'The current execution chain for this node.  Set by xCAT.  Initialized from chain and updated as chain is executed.'},
####################
#  ppchcp table    # 
####################
	{attr_name => username,            
                 only_if => 'nodetype=ivm',              
                 tabentry => 'ppchcp.username',           
                 access_tabentry => 'ppchcp.hcp=attr:node',              
                description => 'The IVM userid used for hardware control.'},
	{attr_name => password,            
                 only_if => 'nodetype=ivm',              
                 tabentry => 'ppchcp.password',           
                 access_tabentry => 'ppchcp.hcp=attr:node',              
                description => 'The IVM password used for hardware control.'},
	{attr_name => username,            
                 only_if => 'nodetype=hmc',              
                 tabentry => 'ppchcp.username',           
                 access_tabentry => 'ppchcp.hcp=attr:node',              
                description => 'The HMC userid used for hardware control.'},
	{attr_name => password,            
                 only_if => 'nodetype=hmc',              
                 tabentry => 'ppchcp.password',           
                 access_tabentry => 'ppchcp.hcp=attr:node',              
                description => 'The HMC password used for hardware control.'},
####################
#  ppc table       # 
####################
        {attr_name => hcp,
                 only_if => 'mgt=hmc',
                 tabentry => 'ppc.hcp',
                 access_tabentry => 'ppc.node=attr:node',
		description => 'The host name or IP address of HMC that is the hardware control point for this node.'},
        {attr_name => hcp,
                 only_if => 'mgt=ivm',
                 tabentry => 'ppc.hcp',
                 access_tabentry => 'ppc.node=attr:node',
		description => 'The host name or IP address of IVM that is the hardware control point for this node.'},
	{attr_name => id,
                 only_if => 'mgt=hmc',
                 tabentry => 'ppc.id',
                 access_tabentry => 'ppc.node=attr:node',
                description => 'For LPARs: the LPAR numeric id; for FSPs: the cage number; for BPAs: the frame number.'},
	{attr_name => id,
                 only_if => 'mgt=ivm',
                 tabentry => 'ppc.id',
                 access_tabentry => 'ppc.node=attr:node',
                description => 'For LPARs: the LPAR numeric id; for FSPs: the cage number; for BPAs: the frame number.'},
	{attr_name => profile,            
                 only_if => 'nodetype=LPAR',              
                 tabentry => 'ppc.profile',           
                 access_tabentry => 'ppc.node=attr:node',              
                description => 'The LPAR profile that will be used the next time the LPAR is powered on with rpower.'},
	{attr_name => parent,            
                 only_if => 'mgt=hmc',              
                 tabentry => 'ppc.parent',           
                 access_tabentry => 'ppc.node=attr:node',              
                description => 'For LPARs: the FSP/CEC; for FSPs: the BPA (if one exists)'},
	{attr_name => parent,            
                 only_if => 'mgt=ivm',              
                 tabentry => 'ppc.parent',           
                 access_tabentry => 'ppc.node=attr:node',              
                description => 'For LPARs: the FSP/CEC; for FSPs: the BPA (if one exists)'},
#######################
#  ppcdirect table    # 
#######################
        {attr_name => username,
                 only_if => 'mgt=fsp',
                 tabentry => 'ppcdirect.username',
                 access_tabentry => 'ppcdirect.hcp=attr:node',
		description => 'The FSP userid used for hardware control.'},
        {attr_name => password,
                 only_if => 'mgt=fsp',
                 tabentry => 'ppcdirect.password',
                 access_tabentry => 'ppcdirect.hcp=attr:node',
		description => 'The FSP password used for hardware control.'},
##################
#  ipmi table    # 
##################
        {attr_name => bmc,
                 only_if => 'mgt=ipmi',
                 tabentry => 'ipmi.bmc',
                 access_tabentry => 'ipmi.node=attr:node',
		description => 'The BMC IP address used for hardware control.'},
        {attr_name => bmcusername,
                 only_if => 'mgt=ipmi',
                 tabentry => 'ipmi.username',
                 access_tabentry => 'ipmi.node=attr:node',
		description => 'The BMC userid used for hardware control.'},
        {attr_name => bmcpassword,
                 only_if => 'mgt=ipmi',
                 tabentry => 'ipmi.password',
                 access_tabentry => 'ipmi.node=attr:node',
		description => 'The BMC password used for hardware control.'},
################
#  mp table    # 
################
        {attr_name => mpa,
                 only_if => 'mgt=blade',
                 tabentry => 'mp.mpa',
                 access_tabentry => 'mp.node=attr:node',
		description => 'The managment module used for hardware control.'},
        {attr_name => id,
                 only_if => 'mgt=blade',
                 tabentry => 'mp.id',
                 access_tabentry => 'mp.node=attr:node',
		description => 'The slot id in the managment module used for hardware control.'},
#################
#  mpa table    # 
#################
        {attr_name => username,
                 only_if => 'nodetype=mm',
                 tabentry => 'mpa.username',
                 access_tabentry => 'mpa.mpa=attr:node',
		description => 'The managment module userid.'},
        {attr_name => password,
                 only_if => 'nodetype=mm',
                 tabentry => 'mpa.password',
                 access_tabentry => 'mpa.mpa=attr:node',
		description => 'The managment module password.'},
######################
#  nodepos table     # 
######################
        {attr_name => 'rack',
                 tabentry => 'nodepos.rack',
                 access_tabentry => 'nodepos.node=attr:node',
		description => 'Physical location information (customer use only).'},
        {attr_name => 'unit',
                 tabentry => 'nodepos.u',
                 access_tabentry => 'nodepos.node=attr:node',
		description => 'Physical location information (customer use only).'},
        {attr_name => 'chassis',
                 tabentry => 'nodepos.chassis',
                 access_tabentry => 'nodepos.node=attr:node',
		description => 'Physical location information (customer use only).'},
        {attr_name => 'slot',
                 tabentry => 'nodepos.slot',
                 access_tabentry => 'nodepos.node=attr:node',
		description => 'Physical location information (customer use only).'},
        {attr_name => 'room',
                 tabentry => 'nodepos.room',
                 access_tabentry => 'nodepos.node=attr:node',
		description => 'Physical location information (customer use only).'});


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
                 description => 'The name of this node definition .'},
        {attr_name => 'nodetype',
                 tabentry => 'nodelist.nodetype',
                 access_tabentry => 'nodelist.node=attr:node',
                 description => 'Specifies a comma-separated list of node type values. (Valid values: osi, hmc, fsp, blade, vm, lpar, ivm, bpa, mm, rsa, switch)'},
###
# TODO:  need to implement nodelist.nodetype as a comma-separated list.
#        right now, all references to attr:nodetype are for single values.
#        will need to globally change the def to make this work...
##
        {attr_name => 'groups',
                 tabentry => 'nodelist.groups',
                 access_tabentry => 'nodelist.node=attr:node',
                 description => 'Comma separated list of groups this node belongs to.'},
	{attr_name => 'status',
                 tabentry => 'nodelist.status',
                 access_tabentry => 'nodelist.node=attr:node',
                 description => 'Current status of the node. Default value is "defined". Valid values include defined, booting, installing, active, off etc.'},
####################
#  hosts table    #
####################
        {attr_name => 'ip',
                 tabentry => 'hosts.ip',
                 access_tabentry => 'hosts.node=attr:node',
                description => 'The IP address for this node.'},
        {attr_name => 'hostnames',
                 tabentry => 'hosts.hostnames',
                 access_tabentry => 'hosts.node=attr:node',
                description => 'Hostname aliases added to /etc/hosts for this no
de.'},
	{attr_name => 'usercomment',
                 tabentry => 'nodelist.comments',
                 access_tabentry => 'nodelist.node=attr:node',
                description => 'User comment.'},
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
                 description => '??? Currently not used by xCAT. ???'},
	{attr_name => 'osdistro',
                 tabentry => 'osimage.osdistro',
                 access_tabentry => 'osimage.imagename=attr:imagename',
#                 description => 'The Linux distribution name to be deployed. The valid values are RedHat, and SLES.'},
                 description => '??? Currently not used by xCAT. ???'},
        {attr_name => 'osname',
                 tabentry => 'osimage.osname',
                 access_tabentry => 'osimage.imagename=attr:imagename',
#                description => 'The name of the operating system to be deployed. The expected values are AIX or Linux.'},
                 description => '??? Currently not used by xCAT. ???'},
	{attr_name => 'osvers',
                 tabentry => 'osimage.osvers',
                 access_tabentry => 'osimage.imagename=attr:imagename',
#                 description => 'The operating system version to be deployed. The formats for the values are "version.release.mod" for AIX and "version" for Linux. (ex. AIX: "5.3.0", Linux: "5").'},
                 description => '??? Currently not used by xCAT. ???'},
	{attr_name => 'osarch',
                 tabentry => 'osimage.osarch',
                 access_tabentry => 'osimage.imagename=attr:imagename',
#                 description => 'The node machine architecture.'},
                 description => '??? Currently not used by xCAT. ???'},
	{attr_name => 'usercomment',
                 tabentry => 'osimage.comments',
                 access_tabentry => 'osimage.imagename=attr:imagename',
#                description => 'User comment.'},
                 description => '??? Currently not used by xCAT. ???'},
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
                 description => 'Name used to identify this network definition.'},
        {attr_name => 'net',
                 tabentry => 'networks.net',
                 access_tabentry => 'networks.netname=attr:netname',
		description => 'The network address.'},
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
		description => 'The DHCP server that is servicing this network.'},
        {attr_name => 'tftpserver',
                 tabentry => 'networks.tftpserver',
                 access_tabentry => 'networks.netname=attr:netname',
		description => 'The TFTP server that is servicing this network.'},
        {attr_name => 'nameservers',
                 tabentry => 'networks.nameservers',
                 access_tabentry => 'networks.netname=attr:netname',
		description => 'The nameservers for this network.  Used in creating the DHCP network definition.'},
        {attr_name => 'dynamicrange',
                 tabentry => 'networks.dynamicrange',
                 access_tabentry => 'networks.netname=attr:netname',
		description => 'The IP address range used by DHCP to assign dynamic IP addresses for requests on this network.'},
	{attr_name => 'usercomment',
                 tabentry => 'networks.comments',
                 access_tabentry => 'networks.netname=attr:netname',
                description => 'User comment.'},
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
                 description => 'The name of this xCAT group object definition.'},
	{attr_name => 'grouptype',
      		 tabentry => 'nodegroup.grouptype',
		 access_tabentry => 'nodegroup.groupname=attr:groupname',
		 description => 'The type of xCAT group - either static or dynamic.'},
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
		description => 'The priority value for this rule.  This value is used to identify this policy data object (i.e. this rule).  ??? Priorities have not been implemented in the xCAT rule processing yet ???.'},
        {attr_name => 'name',
                 tabentry => 'policy.name',
                 access_tabentry => 'policy.priority=attr:priority',
		description => 'The username that is allowed to perform the commands specified by this rule.  Default is "*" (all users).'},
        {attr_name => 'host',
                 tabentry => 'policy.host',
                 access_tabentry => 'policy.priority=attr:priority',
		description => 'The host from which users may issue the commands specified by this rule.  Default is "*" (all hosts).'},
        {attr_name => 'commands',
                 tabentry => 'policy.commands',
                 access_tabentry => 'policy.priority=attr:priority',
		description => 'The list of commands that this rule applies to.  Default is "*" (all commands).  ??? Command lists not implemented yet - only "*" or single command works ???.'},
        {attr_name => 'noderange',
                 tabentry => 'policy.noderange',
                 access_tabentry => 'policy.priority=attr:priority',
		description => 'Noderange that this rule applies to.  ??? Not implemented yet ???.'},
        {attr_name => 'parameters',
                 tabentry => 'policy.parameters',
                 access_tabentry => 'policy.priority=attr:priority',
		description => 'Command parameters that this rule applies to.  ??? Not implemented yet ???.'},
        {attr_name => 'time',
                 tabentry => 'policy.time',
                 access_tabentry => 'policy.priority=attr:priority',
		description => 'Time ranges that this command may be executed in.  ??? Not implemented yet ???.'},
        {attr_name => 'rule',
                tabentry => 'policy.rule',
		access_tabentry => 'policy.priority=attr:priority' ,
		description=> 'Specifies how this rule should be applied.  Valid values are: allow, accept.  Either of these values will allow the user to run the commands.  Any other value will deny the user access to the commands.'},
	{attr_name => 'usercomment',
                 tabentry => 'policy.comments',
                 access_tabentry => 'policy.priority=attr:priority',
                description => 'User comment.'},
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
		
###########################
#  monitoring data object #
###########################
#     monitoring table    # 
###########################
@{$defspec{monitoring}->{'attrs'}} = (
        {attr_name => 'name',
                 tabentry => 'monitoring.name',
                 access_tabentry => 'monitoring.name=attr:name',
                 description => 'The name of the mornitoring plug-in module.'},
        {attr_name => 'nodestatmon',
                 tabentry => 'monitoring.nodestatmon',
                 access_tabentry => 'monitoring.name=attr:name',
                 description => 'Specifies if the monitoring plug-in is used to feed the node status to the xCAT cluster.  Any one of the following values indicates "yes":  y, Y, yes, Yes, YES, 1.  Any other value or blank (default), indicates "no". '},
        {attr_name => 'comments',
                 tabentry => 'monitoring.comments',
                 access_tabentry => 'monitoring.name=attr:name',
                 description => 'User comment.'},
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

