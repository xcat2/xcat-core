
##############
notification.5
##############

.. highlight:: perl


****
NAME
****


\ **notification**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **notification Attributes:**\   \ *filename*\ , \ *tables*\ , \ *tableops*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


Contains registrations to be notified when a table in the xCAT database changes.  Users can add entries to have additional software notified of changes.  Add and remove entries using the provided xCAT commands regnotif and unregnotif.


************************
notification Attributes:
************************



\ **filename**\ 
 
 The path name of a file that implements the callback routine when the monitored table changes.  Can be a perl module or a command.  See the regnotif man page for details.
 


\ **tables**\ 
 
 Comma-separated list of xCAT database tables to monitor.
 


\ **tableops**\ 
 
 Specifies the table operation to monitor for. Valid values:  "d" (rows deleted), "a" (rows added), "u" (rows updated).
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

