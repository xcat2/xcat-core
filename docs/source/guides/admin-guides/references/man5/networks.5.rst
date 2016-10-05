
##########
networks.5
##########

.. highlight:: perl


****
NAME
****


\ **networks**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **networks Attributes:**\   \ *netname*\ , \ *net*\ , \ *mask*\ , \ *mgtifname*\ , \ *gateway*\ , \ *dhcpserver*\ , \ *tftpserver*\ , \ *nameservers*\ , \ *ntpservers*\ , \ *logservers*\ , \ *dynamicrange*\ , \ *staticrange*\ , \ *staticrangeincrement*\ , \ *nodehostname*\ , \ *ddnsdomain*\ , \ *vlanid*\ , \ *domain*\ , \ *mtu*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


Describes the networks in the cluster and info necessary to set up nodes on that network.


********************
networks Attributes:
********************



\ **netname**\ 
 
 Name used to identify this network definition.
 


\ **net**\ 
 
 The network address.
 


\ **mask**\ 
 
 The network mask.
 


\ **mgtifname**\ 
 
 The interface name of the management/service node facing this network.  !remote!<nicname> indicates a non-local network on a specific nic for relay DHCP.
 


\ **gateway**\ 
 
 The network gateway. It can be set to an ip address or the keyword <xcatmaster>, the keyword <xcatmaster> indicates the cluster-facing ip address configured on this management node or service node. Leaving this field blank means that there is no gateway for this network.
 


\ **dhcpserver**\ 
 
 The DHCP server that is servicing this network.  Required to be explicitly set for pooled service node operation.
 


\ **tftpserver**\ 
 
 The TFTP server that is servicing this network.  If not set, the DHCP server is assumed.
 


\ **nameservers**\ 
 
 A comma delimited list of DNS servers that each node in this network should use. This value will end up in the nameserver settings of the /etc/resolv.conf on each node in this network. If this attribute value is set to the IP address of an xCAT node, make sure DNS is running on it. In a hierarchical cluster, you can also set this attribute to "<xcatmaster>" to mean the DNS server for each node in this network should be the node that is managing it (either its service node or the management node).  Used in creating the DHCP network definition, and DNS configuration.
 


\ **ntpservers**\ 
 
 The ntp servers for this network.  Used in creating the DHCP network definition.  Assumed to be the DHCP server if not set.
 


\ **logservers**\ 
 
 The log servers for this network.  Used in creating the DHCP network definition.  Assumed to be the DHCP server if not set.
 


\ **dynamicrange**\ 
 
 The IP address range used by DHCP to assign dynamic IP addresses for requests on this network.  This should not overlap with entities expected to be configured with static host declarations, i.e. anything ever expected to be a node with an address registered in the mac table.
 


\ **staticrange**\ 
 
 The IP address range used to dynamically assign static IPs to newly discovered nodes.  This should not overlap with the dynamicrange nor overlap with entities that were manually assigned static IPs.  The format for the attribute value is:    <startip>-<endip>.
 


\ **staticrangeincrement**\ 



\ **nodehostname**\ 
 
 A regular expression used to specify node name to network-specific hostname.  i.e. "/\z/-secondary/" would mean that the hostname of "n1" would be n1-secondary on this network.  By default, the nodename is assumed to equal the hostname, followed by nodename-interfacename.
 


\ **ddnsdomain**\ 
 
 A domain to be combined with nodename to construct FQDN for DDNS updates induced by DHCP.  This is not passed down to the client as "domain"
 


\ **vlanid**\ 
 
 The vlan ID if this network is within a vlan.
 


\ **domain**\ 
 
 The DNS domain name (ex. cluster.com).
 


\ **mtu**\ 
 
 The default MTU for the network
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

