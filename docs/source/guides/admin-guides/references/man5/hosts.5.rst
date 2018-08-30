
#######
hosts.5
#######

.. highlight:: perl


****
NAME
****


\ **hosts**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **hosts Attributes:**\   \ *node*\ , \ *ip*\ , \ *hostnames*\ , \ *otherinterfaces*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


IP addresses and hostnames of nodes.  This info is optional and is only used to populate /etc/hosts and DNS via makehosts and makedns.  Using regular expressions in this table can be a quick way to populate /etc/hosts.


*****************
hosts Attributes:
*****************



\ **node**\ 
 
 The node name or group name.
 


\ **ip**\ 
 
 The IP address of the node. This is only used in makehosts.  The rest of xCAT uses system name resolution to resolve node names to IP addresses.
 


\ **hostnames**\ 
 
 Hostname aliases added to /etc/hosts for this node. Comma or blank separated list.
 


\ **otherinterfaces**\ 
 
 Other IP addresses to add for this node.  Format: -<ext>:<ip>,<intfhostname>:<ip>,...
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

