
#########
storage.5
#########

.. highlight:: perl


****
NAME
****


\ **storage**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **storage Attributes:**\   \ *node*\ , \ *osvolume*\ , \ *size*\ , \ *state*\ , \ *storagepool*\ , \ *hypervisor*\ , \ *fcprange*\ , \ *volumetag*\ , \ *type*\ , \ *controller*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********



*******************
storage Attributes:
*******************



\ **node**\ 
 
 The node name
 


\ **osvolume**\ 
 
 Specification of what storage to place the node OS image onto.  Examples include:
 
 
 .. code-block:: perl
 
                  localdisk (Install to first non-FC attached disk)
                  usbdisk (Install to first USB mass storage device seen)
                  wwn=0x50000393c813840c (Install to storage device with given WWN)
 
 


\ **size**\ 
 
 Size of the volume. Examples include: 10G, 1024M.
 


\ **state**\ 
 
 State of the volume. The valid values are: free, used, and allocated
 


\ **storagepool**\ 
 
 Name of storage pool where the volume is assigned.
 


\ **hypervisor**\ 
 
 Name of the hypervisor where the volume is configured.
 


\ **fcprange**\ 
 
 A range of acceptable fibre channels that the volume can use. Examples include: 3B00-3C00;4B00-4C00.
 


\ **volumetag**\ 
 
 A specific tag used to identify the volume in the autoyast or kickstart template.
 


\ **type**\ 
 
 The plugin used to drive storage configuration (e.g. svc)
 


\ **controller**\ 
 
 The management address to attach/detach new volumes. 
 In the scenario involving multiple controllers, this data must be
 passed as argument rather than by table value
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

