
########
switch.5
########

.. highlight:: perl


****
NAME
****


\ **switch**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **switch Attributes:**\   \ *node*\ , \ *switch*\ , \ *port*\ , \ *vlan*\ , \ *interface*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


Contains what switch port numbers each node is connected to.


******************
switch Attributes:
******************



\ **node**\ 
 
 The node name or group name.
 


\ **switch**\ 
 
 The switch hostname.
 


\ **port**\ 
 
 The port number in the switch that this node is connected to. On a simple 1U switch, an administrator can generally enter the number as printed next to the ports, and xCAT will understand switch representation differences.  On stacked switches or switches with line cards, administrators should usually use the CLI representation (i.e. 2/0/1 or 5/8).  One notable exception is stacked SMC 8848M switches, in which you must add 56 for the proceeding switch, then the port number.  For example, port 3 on the second switch in an SMC8848M stack would be 59
 


\ **vlan**\ 
 
 The ID for the tagged vlan that is created on this port using mkvlan and chvlan commands.
 


\ **interface**\ 
 
 The interface name from the node perspective. For example, eth0. For the primary nic, it can be empty, the word "primary" or "primary:ethx" where ethx is the interface name.
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

