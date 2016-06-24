
######
zone.7
######

.. highlight:: perl


****
NAME
****


\ **zone**\  - a logical object definition in the xCAT database.


********
SYNOPSIS
********


\ **zone Attributes:**\   \ *defaultzone*\ , \ *sshbetweennodes*\ , \ *sshkeydir*\ , \ *usercomment*\ , \ *zonename*\ 


***********
DESCRIPTION
***********


Logical objects of this type are stored in the xCAT database in one or more tables.  Use the following commands
to manipulate the objects: \ **mkdef**\ , \ **chdef**\ , \ **lsdef**\ , and \ **rmdef**\ .  These commands will take care of
knowing which tables the object attributes should be stored in.  The attribute list below shows, in
parentheses, what tables each attribute is stored in.


****************
zone Attributes:
****************



\ **defaultzone**\  (zone.defaultzone)
 
 If nodes are not assigned to any other zone, they will default to this zone. If value is set to yes or 1.
 


\ **sshbetweennodes**\  (zone.sshbetweennodes)
 
 Indicates whether passwordless ssh will be setup between the nodes of this zone. Values are yes/1 or no/0. Default is yes.
 


\ **sshkeydir**\  (zone.sshkeydir)
 
 Directory containing the shared root ssh RSA keys.
 


\ **usercomment**\  (zone.comments)
 
 Any user-provided notes.
 


\ **zonename**\  (zone.zonename)
 
 The name of the zone.
 



********
SEE ALSO
********


\ **mkdef(1)**\ , \ **chdef(1)**\ , \ **lsdef(1)**\ , \ **rmdef(1)**\ 

