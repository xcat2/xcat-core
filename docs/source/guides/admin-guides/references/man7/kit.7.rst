
#####
kit.7
#####

.. highlight:: perl


****
NAME
****


\ **kit**\  - a logical object definition in the xCAT database.


********
SYNOPSIS
********


\ **kit Attributes:**\   \ *basename*\ , \ *description*\ , \ *isinternal*\ , \ *kitdeployparams*\ , \ *kitdir*\ , \ *kitname*\ , \ *ostype*\ , \ *release*\ , \ *version*\ 


***********
DESCRIPTION
***********


Logical objects of this type are stored in the xCAT database in one or more tables.  Use the following commands
to manipulate the objects: \ **mkdef**\ , \ **chdef**\ , \ **lsdef**\ , and \ **rmdef**\ .  These commands will take care of
knowing which tables the object attributes should be stored in.  The attribute list below shows, in
parentheses, what tables each attribute is stored in.


***************
kit Attributes:
***************



\ **basename**\  (kit.basename)
 
 The kit base name
 


\ **description**\  (kit.description)
 
 The Kit description.
 


\ **isinternal**\  (kit.isinternal)
 
 A flag to indicated if the Kit is internally used. When set to 1, the Kit is internal. If 0 or undefined, the kit is not internal.
 


\ **kitdeployparams**\  (kit.kitdeployparams)
 
 The file containing the default deployment parameters for this Kit.  These parameters are added to the OS Image definition.s list of deployment parameters when one or more Kit Components from this Kit are added to the OS Image.
 


\ **kitdir**\  (kit.kitdir)
 
 The path to Kit Installation directory on the Mgt Node.
 


\ **kitname**\  (kit.kitname)
 
 The unique generated kit name, when kit is added to the cluster.
 


\ **ostype**\  (kit.ostype)
 
 The kit OS type.  Linux or AIX.
 


\ **release**\  (kit.release)
 
 The kit release
 


\ **version**\  (kit.version)
 
 The kit version
 



********
SEE ALSO
********


\ **mkdef(1)**\ , \ **chdef(1)**\ , \ **lsdef(1)**\ , \ **rmdef(1)**\ 

