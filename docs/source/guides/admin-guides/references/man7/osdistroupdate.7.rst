
################
osdistroupdate.7
################

.. highlight:: perl


****
NAME
****


\ **osdistroupdate**\  - a logical object definition in the xCAT database.


********
SYNOPSIS
********


\ **osdistroupdate Attributes:**\   \ *dirpath*\ , \ *downloadtime*\ , \ *osdistroname*\ , \ *osupdatename*\ , \ *usercomment*\ 


***********
DESCRIPTION
***********


Logical objects of this type are stored in the xCAT database in one or more tables.  Use the following commands
to manipulate the objects: \ **mkdef**\ , \ **chdef**\ , \ **lsdef**\ , and \ **rmdef**\ .  These commands will take care of
knowing which tables the object attributes should be stored in.  The attribute list below shows, in
parentheses, what tables each attribute is stored in.


**************************
osdistroupdate Attributes:
**************************



\ **dirpath**\  (osdistroupdate.dirpath)
 
 Path to where OS distro update is stored. (e.g. /install/osdistroupdates/rhels6.2-x86_64-20120716-update)
 


\ **downloadtime**\  (osdistroupdate.downloadtime)
 
 The timestamp when OS distro update was downloaded..
 


\ **osdistroname**\  (osdistroupdate.osdistroname)
 
 The OS distro name to update. (e.g. rhels)
 


\ **osupdatename**\  (osdistroupdate.osupdatename)
 
 Name of OS update. (e.g. rhn-update1)
 


\ **usercomment**\  (osdistroupdate.comments)
 
 Any user-written notes.
 



********
SEE ALSO
********


\ **mkdef(1)**\ , \ **chdef(1)**\ , \ **lsdef(1)**\ , \ **rmdef(1)**\ 

