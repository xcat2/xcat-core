
#########
network.7
#########

.. highlight:: perl


****
NAME
****


\ **network**\  - a logical object definition in the xCAT database.


********
SYNOPSIS
********


\ **network Attributes:**\   \ *ddnsdomain*\ , \ *dhcpserver*\ , \ *domain*\ , \ *dynamicrange*\ , \ *gateway*\ , \ *logservers*\ , \ *mask*\ , \ *mgtifname*\ , \ *mtu*\ , \ *nameservers*\ , \ *net*\ , \ *netname*\ , \ *nodehostname*\ , \ *ntpservers*\ , \ *staticrange*\ , \ *staticrangeincrement*\ , \ *tftpserver*\ , \ *usercomment*\ , \ *vlanid*\ 


***********
DESCRIPTION
***********


Logical objects of this type are stored in the xCAT database in one or more tables.  Use the following commands
to manipulate the objects: \ **mkdef**\ , \ **chdef**\ , \ **lsdef**\ , and \ **rmdef**\ .  These commands will take care of
knowing which tables the object attributes should be stored in.  The attribute list below shows, in
parentheses, what tables each attribute is stored in.


*******************
network Attributes:
*******************



\ **ddnsdomain**\  (networks.ddnsdomain)
 
 A domain to be combined with nodename to construct FQDN for DDNS updates induced by DHCP.  This is not passed down to the client as "domain"
 


\ **dhcpserver**\  (networks.dhcpserver)
 
 The DHCP server that is servicing this network.  Required to be explicitly set for pooled service node operation.
 


\ **domain**\  (networks.domain)
 
 The DNS domain name (ex. cluster.com).
 


\ **dynamicrange**\  (networks.dynamicrange)
 
 The IP address range used by DHCP to assign dynamic IP addresses for requests on this network.  This should not overlap with entities expected to be configured with static host declarations, i.e. anything ever expected to be a node with an address registered in the mac table.
 


\ **gateway**\  (networks.gateway)
 
 The network gateway. It can be set to an ip address or the keyword <xcatmaster>, the keyword <xcatmaster> indicates the cluster-facing ip address configured on this management node or service node. Leaving this field blank means that there is no gateway for this network.
 


\ **logservers**\  (networks.logservers)
 
 The log servers for this network.  Used in creating the DHCP network definition.  Assumed to be the DHCP server if not set.
 


\ **mask**\  (networks.mask)
 
 The network mask.
 


\ **mgtifname**\  (networks.mgtifname)
 
 The interface name of the management/service node facing this network.  !remote!<nicname> indicates a non-local network on a specific nic for relay DHCP.
 


\ **mtu**\  (networks.mtu)
 
 The default MTU for the network
 


\ **nameservers**\  (networks.nameservers)
 
 A comma delimited list of DNS servers that each node in this network should use. This value will end up in the nameserver settings of the /etc/resolv.conf on each node in this network. If this attribute value is set to the IP address of an xCAT node, make sure DNS is running on it. In a hierarchical cluster, you can also set this attribute to "<xcatmaster>" to mean the DNS server for each node in this network should be the node that is managing it (either its service node or the management node).  Used in creating the DHCP network definition, and DNS configuration.
 


\ **net**\  (networks.net)
 
 The network address.
 


\ **netname**\  (networks.netname)
 
 Name used to identify this network definition.
 


\ **nodehostname**\  (networks.nodehostname)
 
 A regular expression used to specify node name to network-specific hostname.  i.e. "/\z/-secondary/" would mean that the hostname of "n1" would be n1-secondary on this network.  By default, the nodename is assumed to equal the hostname, followed by nodename-interfacename.
 


\ **ntpservers**\  (networks.ntpservers)
 
 The ntp servers for this network.  Used in creating the DHCP network definition.  Assumed to be the DHCP server if not set.
 


\ **staticrange**\  (networks.staticrange)
 
 The IP address range used to dynamically assign static IPs to newly discovered nodes.  This should not overlap with the dynamicrange nor overlap with entities that were manually assigned static IPs.  The format for the attribute value is:    <startip>-<endip>.
 


\ **staticrangeincrement**\  (networks.staticrangeincrement)



\ **tftpserver**\  (networks.tftpserver)
 
 The TFTP server that is servicing this network.  If not set, the DHCP server is assumed.
 


\ **usercomment**\  (networks.comments)
 
 Any user-written notes.
 


\ **vlanid**\  (networks.vlanid)
 
 The vlan ID if this network is within a vlan.
 



********
SEE ALSO
********


\ **mkdef(1)**\ , \ **chdef(1)**\ , \ **lsdef(1)**\ , \ **rmdef(1)**\ 

