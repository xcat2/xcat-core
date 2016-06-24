
#######
hwinv.5
#######

.. highlight:: perl


****
NAME
****


\ **hwinv**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **hwinv Attributes:**\   \ *node*\ , \ *cputype*\ , \ *cpucount*\ , \ *memory*\ , \ *disksize*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


The hareware inventory for the node.


*****************
hwinv Attributes:
*****************



\ **node**\ 
 
 The node name or group name.
 


\ **cputype**\ 
 
 The cpu model name for the node.
 


\ **cpucount**\ 
 
 The number of cpus for the node.
 


\ **memory**\ 
 
 The size of the memory for the node in MB.
 


\ **disksize**\ 
 
 The size of the disks for the node in GB.
 


\ **comments**\ 
 
 Any user-provided notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

