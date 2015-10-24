
######
site.7
######

.. highlight:: perl


****
NAME
****


\ **site**\  - a logical object definition in the xCAT database.


********
SYNOPSIS
********


\ **site Attributes:**\   \ *installdir*\ , \ *master*\ , \ *xcatdport*\ 


***********
DESCRIPTION
***********


Logical objects of this type are stored in the xCAT database in one or more tables.  Use the following commands
to manipulate the objects: \ **mkdef**\ , \ **chdef**\ , \ **lsdef**\ , and \ **rmdef**\ .  These commands will take care of
knowing which tables the object attributes should be stored in.  The attribute list below shows, in
parentheses, what tables each attribute is stored in.


****************
site Attributes:
****************



\ **installdir**\  (site.value)
 
 The installation directory
 


\ **master**\  (site.value)
 
 The management node
 


\ **xcatdport**\  (site.value)
 
 Port used by xcatd daemon on master
 



********
SEE ALSO
********


\ **mkdef(1)**\ , \ **chdef(1)**\ , \ **lsdef(1)**\ , \ **rmdef(1)**\ 

