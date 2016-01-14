
#######
chain.5
#######

.. highlight:: perl


****
NAME
****


\ **chain**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **chain Attributes:**\   \ *node*\ , \ *currstate*\ , \ *currchain*\ , \ *chain*\ , \ *ondiscover*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


Controls what operations are done (and it what order) when a node is discovered and deployed.


*****************
chain Attributes:
*****************



\ **node**\ 
 
 The node name or group name.
 


\ **currstate**\ 
 
 The current or next chain step to be executed on this node by xCAT-genesis.  Set by xCAT during node discovery or as a result of nodeset.
 


\ **currchain**\ 
 
 The chain steps still left to do for this node.  This attribute will be automatically adjusted by xCAT while xCAT-genesis is running on the node (either during node discovery or a special operation like firmware update).  During node discovery, this attribute is initialized from the chain attribute and updated as the chain steps are executed.
 


\ **chain**\ 
 
 A comma-delimited chain of actions to be performed automatically when this node is discovered. ("Discovered" means a node booted, but xCAT and DHCP did not recognize the MAC of this node. In this situation, xCAT initiates the discovery process, the last step of which is to run the operations listed in this chain attribute, one by one.) Valid values:  boot, runcmd=<cmd>, runimage=<URL>, shell, standby. (Default - same as no chain - it will do only the discovery.).  Example, for BMC machines use: runcmd=bmcsetup,shell.
 


\ **ondiscover**\ 
 
 This attribute is currently not used by xCAT.  The "nodediscover" operation is always done during node discovery.
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

