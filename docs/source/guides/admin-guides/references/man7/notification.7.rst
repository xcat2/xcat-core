
##############
notification.7
##############

.. highlight:: perl


****
NAME
****


\ **notification**\  - a logical object definition in the xCAT database.


********
SYNOPSIS
********


\ **notification Attributes:**\   \ *comments*\ , \ *filename*\ , \ *tableops*\ , \ *tables*\ 


***********
DESCRIPTION
***********


Logical objects of this type are stored in the xCAT database in one or more tables.  Use the following commands
to manipulate the objects: \ **mkdef**\ , \ **chdef**\ , \ **lsdef**\ , and \ **rmdef**\ .  These commands will take care of
knowing which tables the object attributes should be stored in.  The attribute list below shows, in
parentheses, what tables each attribute is stored in.


************************
notification Attributes:
************************



\ **comments**\  (notification.comments)
 
 Any user-written notes.
 


\ **filename**\  (notification.filename)
 
 The path name of a file that implements the callback routine when the monitored table changes.  Can be a perl module or a command.  See the regnotif man page for details.
 


\ **tableops**\  (notification.tableops)
 
 Specifies the table operation to monitor for. Valid values:  "d" (rows deleted), "a" (rows added), "u" (rows updated).
 


\ **tables**\  (notification.tables)
 
 Comma-separated list of xCAT database tables to monitor.
 



********
SEE ALSO
********


\ **mkdef(1)**\ , \ **chdef(1)**\ , \ **lsdef(1)**\ , \ **rmdef(1)**\ 

