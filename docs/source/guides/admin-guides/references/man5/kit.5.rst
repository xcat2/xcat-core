
#####
kit.5
#####

.. highlight:: perl


****
NAME
****


\ **kit**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **kit Attributes:**\   \ *kitname*\ , \ *basename*\ , \ *description*\ , \ *version*\ , \ *release*\ , \ *ostype*\ , \ *isinternal*\ , \ *kitdeployparams*\ , \ *kitdir*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


This table stores all kits added to the xCAT cluster.


***************
kit Attributes:
***************



\ **kitname**\ 
 
 The unique generated kit name, when kit is added to the cluster.
 


\ **basename**\ 
 
 The kit base name
 


\ **description**\ 
 
 The Kit description.
 


\ **version**\ 
 
 The kit version
 


\ **release**\ 
 
 The kit release
 


\ **ostype**\ 
 
 The kit OS type.  Linux or AIX.
 


\ **isinternal**\ 
 
 A flag to indicated if the Kit is internally used. When set to 1, the Kit is internal. If 0 or undefined, the kit is not internal.
 


\ **kitdeployparams**\ 
 
 The file containing the default deployment parameters for this Kit.  These parameters are added to the OS Image definition.s list of deployment parameters when one or more Kit Components from this Kit are added to the OS Image.
 


\ **kitdir**\ 
 
 The path to Kit Installation directory on the Mgt Node.
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

