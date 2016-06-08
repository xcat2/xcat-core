
############
monitoring.7
############

.. highlight:: perl


****
NAME
****


\ **monitoring**\  - a logical object definition in the xCAT database.


********
SYNOPSIS
********


\ **monitoring Attributes:**\   \ *comments*\ , \ *disable*\ , \ *name*\ , \ *nodestatmon*\ 


***********
DESCRIPTION
***********


Logical objects of this type are stored in the xCAT database in one or more tables.  Use the following commands
to manipulate the objects: \ **mkdef**\ , \ **chdef**\ , \ **lsdef**\ , and \ **rmdef**\ .  These commands will take care of
knowing which tables the object attributes should be stored in.  The attribute list below shows, in
parentheses, what tables each attribute is stored in.


**********************
monitoring Attributes:
**********************



\ **comments**\  (monitoring.comments)
 
 Any user-written notes.
 


\ **disable**\  (monitoring.disable)
 
 Set to 'yes' or '1' to comment out this row.
 


\ **name**\  (monitoring.name)
 
 The name of the monitoring plug-in module.  The plug-in must be put in /lib/perl/xCAT_monitoring/.  See the man page for monstart for details.
 


\ **nodestatmon**\  (monitoring.nodestatmon)
 
 Specifies if the monitoring plug-in is used to feed the node status to the xCAT cluster.  Any one of the following values indicates "yes":  y, Y, yes, Yes, YES, 1.  Any other value or blank (default), indicates "no".
 



********
SEE ALSO
********


\ **mkdef(1)**\ , \ **chdef(1)**\ , \ **lsdef(1)**\ , \ **rmdef(1)**\ 

