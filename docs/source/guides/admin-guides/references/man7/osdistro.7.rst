
##########
osdistro.7
##########

.. highlight:: perl


****
NAME
****


\ **osdistro**\  - a logical object definition in the xCAT database.


********
SYNOPSIS
********


\ **osdistro Attributes:**\   \ *arch*\ , \ *basename*\ , \ *dirpaths*\ , \ *majorversion*\ , \ *minorversion*\ , \ *osdistroname*\ , \ *type*\ 


***********
DESCRIPTION
***********


Logical objects of this type are stored in the xCAT database in one or more tables.  Use the following commands
to manipulate the objects: \ **mkdef**\ , \ **chdef**\ , \ **lsdef**\ , and \ **rmdef**\ .  These commands will take care of
knowing which tables the object attributes should be stored in.  The attribute list below shows, in
parentheses, what tables each attribute is stored in.


********************
osdistro Attributes:
********************



\ **arch**\  (osdistro.arch)
 
 The OS distro arch (e.g. x86_64)
 


\ **basename**\  (osdistro.basename)
 
 The OS base name (e.g. rhels)
 


\ **dirpaths**\  (osdistro.dirpaths)
 
 Directory paths where OS distro is store. There could be multiple paths if OS distro has more than one ISO image. (e.g. /install/rhels6.2/x86_64,...)
 


\ **majorversion**\  (osdistro.majorversion)
 
 The OS distro major version.(e.g. 6)
 


\ **minorversion**\  (osdistro.minorversion)
 
 The OS distro minor version. (e.g. 2)
 


\ **osdistroname**\  (osdistro.osdistroname)
 
 Unique name (e.g. rhels6.2-x86_64)
 


\ **type**\  (osdistro.type)
 
 Linux or AIX
 



********
SEE ALSO
********


\ **mkdef(1)**\ , \ **chdef(1)**\ , \ **lsdef(1)**\ , \ **rmdef(1)**\ 

