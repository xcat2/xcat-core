
######
rack.7
######

.. highlight:: perl


****
NAME
****


\ **rack**\  - a logical object definition in the xCAT database.


********
SYNOPSIS
********


\ **rack Attributes:**\   \ *displayname*\ , \ *height*\ , \ *num*\ , \ *rackname*\ , \ *room*\ , \ *usercomment*\ 


***********
DESCRIPTION
***********


Logical objects of this type are stored in the xCAT database in one or more tables.  Use the following commands
to manipulate the objects: \ **mkdef**\ , \ **chdef**\ , \ **lsdef**\ , and \ **rmdef**\ .  These commands will take care of
knowing which tables the object attributes should be stored in.  The attribute list below shows, in
parentheses, what tables each attribute is stored in.


****************
rack Attributes:
****************



\ **displayname**\  (rack.displayname)
 
 Alternative name for rack. Only used by PCM.
 


\ **height**\  (rack.height)
 
 Number of units which can be stored in the rack.
 


\ **num**\  (rack.num)
 
 The rack number.
 


\ **rackname**\  (rack.rackname)
 
 The rack name.
 


\ **room**\  (rack.room)
 
 The room in which the rack is located.
 


\ **usercomment**\  (rack.comments)
 
 Any user-written notes.
 



********
SEE ALSO
********


\ **mkdef(1)**\ , \ **chdef(1)**\ , \ **lsdef(1)**\ , \ **rmdef(1)**\ 

