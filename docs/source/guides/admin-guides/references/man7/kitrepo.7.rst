
#########
kitrepo.7
#########

.. highlight:: perl


****
NAME
****


\ **kitrepo**\  - a logical object definition in the xCAT database.


********
SYNOPSIS
********


\ **kitrepo Attributes:**\   \ *compat_osbasenames*\ , \ *kitname*\ , \ *kitrepodir*\ , \ *kitreponame*\ , \ *osarch*\ , \ *osbasename*\ , \ *osmajorversion*\ , \ *osminorversion*\ 


***********
DESCRIPTION
***********


Logical objects of this type are stored in the xCAT database in one or more tables.  Use the following commands
to manipulate the objects: \ **mkdef**\ , \ **chdef**\ , \ **lsdef**\ , and \ **rmdef**\ .  These commands will take care of
knowing which tables the object attributes should be stored in.  The attribute list below shows, in
parentheses, what tables each attribute is stored in.


*******************
kitrepo Attributes:
*******************



\ **compat_osbasenames**\  (kitrepo.compat_osbasenames)
 
 List of compatible OS base names.
 


\ **kitname**\  (kitrepo.kitname)
 
 The Kit name which this Kit Package Repository belongs to.
 


\ **kitrepodir**\  (kitrepo.kitrepodir)
 
 The path to Kit Repository directory on the Mgt Node.
 


\ **kitreponame**\  (kitrepo.kitreponame)
 
 The unique generated kit repo package name, when kit is added to the cluster.
 


\ **osarch**\  (kitrepo.osarch)
 
 The OS distro arch which this repository is based on.
 


\ **osbasename**\  (kitrepo.osbasename)
 
 The OS distro name which this repository is based on.
 


\ **osmajorversion**\  (kitrepo.osmajorversion)
 
 The OS distro major version which this repository is based on.
 


\ **osminorversion**\  (kitrepo.osminorversion)
 
 The OS distro minor version which this repository is based on. If this attribute is not set, it means that this repo applies to all minor versions.
 



********
SEE ALSO
********


\ **mkdef(1)**\ , \ **chdef(1)**\ , \ **lsdef(1)**\ , \ **rmdef(1)**\ 

