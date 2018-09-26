
##########
osdistro.5
##########

.. highlight:: perl


****
NAME
****


\ **osdistro**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **osdistro Attributes:**\   \ *osdistroname*\ , \ *basename*\ , \ *majorversion*\ , \ *minorversion*\ , \ *arch*\ , \ *type*\ , \ *dirpaths*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


Information about all the OS distros in the xCAT cluster


********************
osdistro Attributes:
********************



\ **osdistroname**\ 
 
 Unique name (e.g. rhels6.2-x86_64)
 


\ **basename**\ 
 
 The OS base name (e.g. rhels)
 


\ **majorversion**\ 
 
 The OS distro major version.(e.g. 6)
 


\ **minorversion**\ 
 
 The OS distro minor version. (e.g. 2)
 


\ **arch**\ 
 
 The OS distro arch (e.g. x86_64)
 


\ **type**\ 
 
 Linux or AIX
 


\ **dirpaths**\ 
 
 Directory paths where OS distro is store. There could be multiple paths if OS distro has more than one ISO image. (e.g. /install/rhels6.2/x86_64,...)
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

