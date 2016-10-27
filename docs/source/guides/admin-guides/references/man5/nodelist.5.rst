
##########
nodelist.5
##########

.. highlight:: perl


****
NAME
****


\ **nodelist**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **nodelist Attributes:**\   \ *node*\ , \ *groups*\ , \ *status*\ , \ *statustime*\ , \ *appstatus*\ , \ *appstatustime*\ , \ *primarysn*\ , \ *hidden*\ , \ *updatestatus*\ , \ *updatestatustime*\ , \ *zonename*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


The list of all the nodes in the cluster, including each node's current status and what groups it is in.


********************
nodelist Attributes:
********************



\ **node**\ 
 
 The hostname of a node in the cluster.
 


\ **groups**\ 
 
 A comma-delimited list of groups this node is a member of.  Group names are arbitrary, except all nodes should be part of the 'all' group. Internal group names are designated by using __<groupname>.  For example, __Unmanaged, could be the internal name for a group of nodes that is not managed by xCAT. Admins should avoid using the __ characters when defining their groups.
 


\ **status**\ 
 
 The current status of this node.  This attribute will be set by xCAT software.  Valid values: defined, booting, netbooting, booted, discovering, configuring, installing, alive, standingby, powering-off, unreachable. If blank, defined is assumed. The possible status change sequences are: For installation: defined->[discovering]->[configuring]->[standingby]->installing->booting->booted->[alive],  For diskless deployment: defined->[discovering]->[configuring]->[standingby]->netbooting->booted->[alive],  For booting: [alive/unreachable]->booting->[alive],  For powering off: [alive]->powering-off->[unreachable], For monitoring: alive->unreachable. Discovering and configuring are for x Series discovery process. Alive and unreachable are set only when there is a monitoring plug-in start monitor the node status for xCAT. Note that the status values will not reflect the real node status if you change the state of the node from outside of xCAT (i.e. power off the node using HMC GUI).
 


\ **statustime**\ 
 
 The data and time when the status was updated.
 


\ **appstatus**\ 
 
 A comma-delimited list of application status. For example: 'sshd=up,ftp=down,ll=down'
 


\ **appstatustime**\ 
 
 The date and time when appstatus was updated.
 


\ **primarysn**\ 
 
 Not used currently. The primary servicenode, used by this node.
 


\ **hidden**\ 
 
 Used to hide fsp and bpa definitions, 1 means not show them when running lsdef and nodels
 


\ **updatestatus**\ 
 
 The current node update status. Valid states are synced, out-of-sync,syncing,failed.
 


\ **updatestatustime**\ 
 
 The date and time when the updatestatus was updated.
 


\ **zonename**\ 
 
 The name of the zone to which the node is currently assigned. If undefined, then it is not assigned to any zone.
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

