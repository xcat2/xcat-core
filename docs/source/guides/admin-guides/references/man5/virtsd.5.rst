
########
virtsd.5
########

.. highlight:: perl


****
NAME
****


\ **virtsd**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **virtsd Attributes:**\   \ *node*\ , \ *sdtype*\ , \ *stype*\ , \ *location*\ , \ *host*\ , \ *cluster*\ , \ *datacenter*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


The parameters which used to create the Storage Domain


******************
virtsd Attributes:
******************



\ **node**\ 
 
 The name of the storage domain
 


\ **sdtype**\ 
 
 The type of storage domain. Valid values: data, iso, export
 


\ **stype**\ 
 
 The type of storge. Valid values: nfs, fcp, iscsi, localfs
 


\ **location**\ 
 
 The path of the storage
 


\ **host**\ 
 
 For rhev, a hypervisor host needs to be specified to manage the storage domain as SPM (Storage Pool Manager). But the SPM role will be failed over to another host when this host down.
 


\ **cluster**\ 
 
 A cluster of hosts
 


\ **datacenter**\ 
 
 A collection for all host, vm that will shared the same storages, networks.
 


\ **comments**\ 



\ **disable**\ 




********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

