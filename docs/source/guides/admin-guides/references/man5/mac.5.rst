
#####
mac.5
#####

.. highlight:: perl


****
NAME
****


\ **mac**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **mac Attributes:**\   \ *node*\ , \ *interface*\ , \ *mac*\ , \ *duid*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


The MAC address of the node's install adapter.  Normally this table is populated by getmacs or node discovery, but you can also add entries to it manually.


***************
mac Attributes:
***************



\ **node**\ 
 
 The node name or group name.
 


\ **interface**\ 
 
 The adapter interface name that will be used to install and manage the node. E.g. eth0 (for linux) or en0 (for AIX).)
 


\ **mac**\ 
 
 The mac address or addresses for which xCAT will manage static bindings for this node.  This may be simply a mac address, which would be bound to the node name (such as "01:02:03:04:05:0E").  This may also be a "|" delimited string of "mac address!hostname" format (such as "01:02:03:04:05:0E!node5|01:02:03:04:05:0F!node6-eth1"). If there are multiple nics connected to Management Network(usually for bond), in order to make sure the OS deployment finished successfully, the macs of those nics must be able to resolve to same IP address. First, users have to create alias of the node for each mac in the Management Network through either: 1. adding the alias into /etc/hosts for the node directly or: 2. setting the alias to the "hostnames" attribute and then run "makehost" against the node. Then, configure the "mac" attribute of the node like "mac1!node|mac2!node-alias". For the first mac address (mac1 in the example) set in "mac" attribute, do not need to set a "node name" string for it since the nodename of the node will be used for it by default.
 


\ **duid**\ 
 
 The DHCPv6 client identifier (DUID) that the IPv6 reservations of the node match. Valid values are firmware, canonical, or a DUID. firmware (the default): the DUID-UUID that UEFI firmware built on EDK2 sends, which holds vpd.uuid with its first three fields in the little-endian order that SMBIOS 2.6 and later use. canonical: the DUID-UUID with vpd.uuid in RFC 4122 network byte order, which a client sends when it encodes the UUID that the operating system reports. A DUID: the identifier itself, as colon-separated hexadecimal octets, for example 00:01:00:01:2e:4f:61:a0:02:00:00:00:00:61. Like a MAC address, a DUID identifies one client: when two nodes have the same DUID, the reservation belongs to the node that makedhcp updated last. A reservation matches one DUID. When the firmware and the operating system send different identifiers, set the identifier of the client that must get the reserved address.
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

