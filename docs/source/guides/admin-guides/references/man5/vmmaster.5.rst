
##########
vmmaster.5
##########

.. highlight:: perl


****
NAME
****


\ **vmmaster**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **vmmaster Attributes:**\   \ *name*\ , \ *os*\ , \ *arch*\ , \ *profile*\ , \ *storage*\ , \ *storagemodel*\ , \ *nics*\ , \ *vintage*\ , \ *originator*\ , \ *virttype*\ , \ *specializeparameters*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


Inventory of virtualization images for use with clonevm.  Manual intervention in this table is not intended.


********************
vmmaster Attributes:
********************



\ **name**\ 
 
 The name of a master
 


\ **os**\ 
 
 The value of nodetype.os at the time the master was captured
 


\ **arch**\ 
 
 The value of nodetype.arch at the time of capture
 


\ **profile**\ 
 
 The value of nodetype.profile at time of capture
 


\ **storage**\ 
 
 The storage location of bulk master information
 


\ **storagemodel**\ 
 
 The default storage style to use when modifying a vm cloned from this master
 


\ **nics**\ 
 
 The nic configuration and relationship to vlans/bonds/etc
 


\ **vintage**\ 
 
 When this image was created
 


\ **originator**\ 
 
 The user who created the image
 


\ **virttype**\ 
 
 The type of virtualization this image pertains to (e.g. vmware, kvm, etc)
 


\ **specializeparameters**\ 
 
 Implementation specific arguments, currently only "autoLogonCount=<number" for ESXi clonevme
 


\ **comments**\ 



\ **disable**\ 




********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

