
#########
kitrepo.5
#########

.. highlight:: perl


****
NAME
****


\ **kitrepo**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **kitrepo Attributes:**\   \ *kitreponame*\ , \ *kitname*\ , \ *osbasename*\ , \ *osmajorversion*\ , \ *osminorversion*\ , \ *osarch*\ , \ *compat_osbasenames*\ , \ *kitrepodir*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


This table stores all kits added to the xCAT cluster.


*******************
kitrepo Attributes:
*******************



\ **kitreponame**\ 
 
 The unique generated kit repo package name, when kit is added to the cluster.
 


\ **kitname**\ 
 
 The Kit name which this Kit Package Repository belongs to.
 


\ **osbasename**\ 
 
 The OS distro name which this repository is based on.
 


\ **osmajorversion**\ 
 
 The OS distro major version which this repository is based on.
 


\ **osminorversion**\ 
 
 The OS distro minor version which this repository is based on. If this attribute is not set, it means that this repo applies to all minor versions.
 


\ **osarch**\ 
 
 The OS distro arch which this repository is based on.
 


\ **compat_osbasenames**\ 
 
 List of compatible OS base names.
 


\ **kitrepodir**\ 
 
 The path to Kit Repository directory on the Mgt Node.
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

