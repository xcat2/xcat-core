
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


\ **mac Attributes:**\   \ *node*\ , \ *interface*\ , \ *mac*\ , \ *comments*\ , \ *disable*\ 


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
 
 The mac address or addresses for which xCAT will manage static bindings for this node.  This may be simply a mac address, which would be bound to the node name (such as "01:02:03:04:05:0E").  This may also be a "|" delimited string of "mac address!hostname" format (such as "01:02:03:04:05:0E!node5|01:02:03:05:0F!node6-eth1").
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

