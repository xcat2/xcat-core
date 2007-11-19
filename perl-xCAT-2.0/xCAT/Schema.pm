# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::Schema;

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
  ppcDirect => {
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
    cols => [qw(node servicenode netboot tftpserver nfsserver kernel initrd kcmdline nfsdir serialport installnic primarynic xcatmaster current_osimage next_osimage comments disable)],
    keys => [qw(node)],
  },
  networks => {
    cols => [qw(netname net mask gateway dhcpserver tftpserver nameservers dynamicrange comments disable)],
    keys => [qw(net mask)]
  },
  switch =>  {
    cols => [qw(node switch vlan port comments disable)],
    keys => [qw(node switch port)]
  },
  nodelist => {
    cols => [qw(node nodetype groups comments disable)],
    keys => [qw(node)],
  },
  site => {
    cols => [qw(key value comments disable)],
    keys => [qw(key)]
  },
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
  site =>    { attrs => [], attrhash => {}, objkey => 'master' }
);
  
#############
#  TODO:  Need to figure out how to map the following to data objects:
#          nodetype table (does this get moved to the osimage table?)
#                --> do we need an arch attr per node that is stored in nodehm?
#          mac table (are we going to have an interface object definition?)
#          switch table (each interface on a node can have its own switch 
#               table entry, part of interface object, too?)
#          username/password from password, hmc, ivm, mpa, and ipmi tables
#             (do we need special encryption and display masking for passwords?)
#          chain table (I think this is internal use only, do not abstract?)
#          noderes entries for kernel, initrd, kcmdline
#          ppc table (waiting on Scot to add to tabspec)
#          policy table - ? do we need a data abstraction for this?
#          notification - is this handled by Ling's commands?
#          site - need to figure out what entries we will have in the 
#               site table since they are not listed individually in the
#               tabspec
#          nodelist.groups
#          new group table and object
#          new osimage table and object
###############
#  TODO:  need to fill out all the "description" fields
#         These will be used for verbose usage with the def* cmds  
##############
@{$defspec{node}->{'attrs'}} = (
                {attr_name => 'node',
                 tabentry => 'nodelist.node',
                 access_tabentry => 'objkeyvalue'},
############
# TODO:  The attr name for nodelist.nodetype is in conflict with the existing
#        nodetype table.  With the osimage table, the nodetype table should go
#        away.  Will reuse of this name cause confusion for xcat users?
############
                {attr_name => 'nodetype',
                 tabentry => 'nodelist.nodetype',
                 access_tabentry => 'nodelist.node=attr:node',
                 description => 'Type of node:  osi,hmc,fsp,mpa,???'},
                {attr_name => 'xcatmaster',
                 tabentry => 'noderes.xcatmaster',
                 access_tabentry => 'noderes.node=attr:node'},
                {attr_name => 'servicenode',
                 tabentry => 'noderes.servicenode',
                 access_tabentry => 'noderes.node=attr:node'},
                {attr_name => 'mgt',
                 tabentry => 'nodehm.mgt',
                 access_tabentry => 'nodehm.node=attr:node'},
                {attr_name => 'power',
                 tabentry => 'nodehm.power',
                 access_tabentry => 'nodehm.node=attr:node'},
                {attr_name => 'cons',
                 tabentry => 'nodehm.cons',
                 access_tabentry => 'nodehm.node=attr:node'},
                {attr_name => 'termserver',
                 tabentry => 'nodehm.termserver',
                 access_tabentry => 'nodehm.node=attr:node'},
                {attr_name => 'termport',
                 tabentry => 'nodehm.termport',
                 access_tabentry => 'nodehm.node=attr:node'},
                {attr_name => 'conserver',
                 tabentry => 'nodehm.conserver',
                 access_tabentry => 'nodehm.node=attr:node'},
                {attr_name => 'getmac',
                 tabentry => 'nodehm.getmac',
                 access_tabentry => 'nodehm.node=attr:node'},
                {attr_name => 'serialport',
                 tabentry => 'noderes.serialport',
                 access_tabentry => 'noderes.node=attr:node'},
                {attr_name => 'serialspeed',
                 tabentry => 'nodehm.serialspeed',
                 access_tabentry => 'nodehm.node=attr:node'},
                {attr_name => 'serialflow',
                 tabentry => 'nodehm.serialflow',
                 access_tabentry => 'nodehm.node=attr:node'},
                {attr_name => 'ip',
                 tabentry => 'hosts.ip',
                 access_tabentry => 'hosts.node=attr:node'},
                {attr_name => 'hostnames',
                 tabentry => 'hosts.hostnames',
                 access_tabentry => 'hosts.node=attr:node'},
                {attr_name => 'serialnumber',
                 tabentry => 'vpd.serial',
                 access_tabentry => 'vpd.node=attr:node'},
                {attr_name => 'mtm',
                 tabentry => 'vpd.mtm',
                 access_tabentry => 'vpd.node=attr:node'},
                {attr_name => 'rackloc',
                 tabentry => 'nodepos.rack',
                 access_tabentry => 'nodepos.node=attr:node'},
                {attr_name => 'unitloc',
                 tabentry => 'nodepos.u',
                 access_tabentry => 'nodepos.node=attr:node'},
                {attr_name => 'chassisloc',
                 tabentry => 'nodepos.chassis',
                 access_tabentry => 'nodepos.node=attr:node'},
                {attr_name => 'slotloc',
                 tabentry => 'nodepos.slot',
                 access_tabentry => 'nodepos.node=attr:node'},
                {attr_name => 'roomloc',
                 tabentry => 'nodepos.room',
                 access_tabentry => 'nodepos.node=attr:node'},

     # Conditional attributes:
     #    OSI node attributes:
                {attr_name => 'tftpserver',
                 only_if => 'nodetype=osi',
                 tabentry => 'noderes.tftpserver',
                 access_tabentry => 'noderes.node=attr:node'},
                {attr_name => 'nfsserver',
                 only_if => 'nodetype=osi',
                 tabentry => 'noderes.nfsserver',
                 access_tabentry => 'noderes.node=attr:node'},
                {attr_name => 'nfsdir',
                 only_if => 'nodetype=osi',
                 tabentry => 'noderes.nfsdir',
                 access_tabentry => 'noderes.node=attr:node'},
                {attr_name => 'primarynic',
                 only_if => 'nodetype=osi',
                 tabentry => 'noderes.primarynic',
                 access_tabentry => 'noderes.node=attr:node'},
                {attr_name => 'installnic',
                 only_if => 'nodetype=osi',
                 tabentry => 'noderes.installnic',
                 access_tabentry => 'noderes.node=attr:node'},
                {attr_name => 'netboot',
                 only_if => 'nodetype=osi',
                 tabentry => 'noderes.netboot',
                 access_tabentry => 'noderes.node=attr:node'},
                {attr_name => 'current_osimage',
                 only_if => 'nodetype=osi',
                 tabentry => 'noderes.current_osimage',
                 access_tabentry => 'noderes.node=attr:node'},
                {attr_name => 'next_osimage',
                 only_if => 'nodetype=osi',
                 tabentry => 'noderes.next_osimage',
                 access_tabentry => 'noderes.node=attr:node'},

     #    Hardware Control node attributes:
                {attr_name => hdwctrlpoint,
                 only_if => 'mgtmethod=mp',
                 tabentry => 'mp.mpa',
                 access_tabentry => 'mp.node=attr:node'},
#                {attr_name => hdwctrlpoint,
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
                 access_tabentry => 'mp.node=attr:node'},
#                {attr_name => hdwctrlnodeid,
#                 only_if => 'mgtmethod=hmc',
#                 tabentry => 'ppc.id',
#                 access_tabentry => 'ppc.node=attr:node'}
             );
             
@{$defspec{osimage}->{'attrs'}} = (
                {attr_name => 'imagename',
                 tabentry => 'osimage.imagename',
                 access_tabentry => 'objkeyvalue',
                 description => 'Name of OS image'},
                {attr_name => 'osdistro',
                 tabentry => 'osimage.osdistro',
                 access_tabentry => 'osimage.objname=attr:imagename'},
             );
             
@{$defspec{network}->{'attrs'}} = (
                {attr_name => 'netname',
                 tabentry => 'networks.netname',
                 access_tabentry => 'objkeyvalue',
                 description => 'Name to identify the network'},
                {attr_name => 'net',
                 tabentry => 'networks.net',
                 access_tabentry => 'networks.netname=attr:netname'},
                {attr_name => 'mask',
                 tabentry => 'networks.mask',
                 access_tabentry => 'networks.netname=attr:netname'},
                {attr_name => 'gateway',
                 tabentry => 'networks.gateway',
                 access_tabentry => 'networks.netname=attr:netname'},
                {attr_name => 'dhcpserver',
                 tabentry => 'networks.dhcpserver',
                 access_tabentry => 'networks.netname=attr:netname'},
                {attr_name => 'tftpserver',
                 tabentry => 'networks.tftpserver',
                 access_tabentry => 'networks.netname=attr:netname'},
                {attr_name => 'nameservers',
                 tabentry => 'networks.nameservers',
                 access_tabentry => 'networks.netname=attr:netname'},
                {attr_name => 'dynamicrange',
                 tabentry => 'networks.dynamicrange',
                 access_tabentry => 'networks.netname=attr:netname'},
             );

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


