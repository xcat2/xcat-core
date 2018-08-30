
############
monitoring.5
############

.. highlight:: perl


****
NAME
****


\ **monitoring**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **monitoring Attributes:**\   \ *name*\ , \ *nodestatmon*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


Controls what external monitoring tools xCAT sets up and uses.  Entries should be added and removed from this table using the provided xCAT commands monstart and monstop.


**********************
monitoring Attributes:
**********************



\ **name**\ 
 
 The name of the monitoring plug-in module.  The plug-in must be put in /lib/perl/xCAT_monitoring/.  See the man page for monstart for details.
 


\ **nodestatmon**\ 
 
 Specifies if the monitoring plug-in is used to feed the node status to the xCAT cluster.  Any one of the following values indicates "yes":  y, Y, yes, Yes, YES, 1.  Any other value or blank (default), indicates "no".
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

