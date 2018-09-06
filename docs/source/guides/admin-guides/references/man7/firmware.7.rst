
##########
firmware.7
##########

.. highlight:: perl


****
NAME
****


\ **firmware**\  - a logical object definition in the xCAT database.


********
SYNOPSIS
********


\ **firmware Attributes:**\   \ *cfgfile*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


Logical objects of this type are stored in the xCAT database in one or more tables.  Use the following commands
to manipulate the objects: \ **mkdef**\ , \ **chdef**\ , \ **lsdef**\ , and \ **rmdef**\ .  These commands will take care of
knowing which tables the object attributes should be stored in.  The attribute list below shows, in
parentheses, what tables each attribute is stored in.


********************
firmware Attributes:
********************



\ **cfgfile**\  (firmware.cfgfile)
 
 The file to use.
 


\ **comments**\  (firmware.comments)
 
 Any user-written notes.
 


\ **disable**\  (firmware.disable)
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **mkdef(1)**\ , \ **chdef(1)**\ , \ **lsdef(1)**\ , \ **rmdef(1)**\ 

