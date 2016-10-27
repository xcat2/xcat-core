
############
monsetting.5
############

.. highlight:: perl


****
NAME
****


\ **monsetting**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **monsetting Attributes:**\   \ *name*\ , \ *key*\ , \ *value*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


Specifies the monitoring plug-in specific settings. These settings will be used by the monitoring plug-in to customize the behavior such as event filter, sample interval, responses etc. Entries should be added, removed or modified by chtab command. Entries can also be added or modified by the monstart command when a monitoring plug-in is brought up.


**********************
monsetting Attributes:
**********************



\ **name**\ 
 
 The name of the monitoring plug-in module.  The plug-in must be put in /lib/perl/xCAT_monitoring/.  See the man page for monstart for details.
 


\ **key**\ 
 
 Specifies the name of the attribute. The valid values are specified by each monitoring plug-in. Use "monls name -d" to get a list of valid keys.
 


\ **value**\ 
 
 Specifies the value of the attribute.
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

