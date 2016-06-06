
################
osdistroupdate.5
################

.. highlight:: perl


****
NAME
****


\ **osdistroupdate**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **osdistroupdate Attributes:**\   \ *osupdatename*\ , \ *osdistroname*\ , \ *dirpath*\ , \ *downloadtime*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


Information about the OS distro updates in the xCAT cluster


**************************
osdistroupdate Attributes:
**************************



\ **osupdatename**\ 
 
 Name of OS update. (e.g. rhn-update1)
 


\ **osdistroname**\ 
 
 The OS distro name to update. (e.g. rhels)
 


\ **dirpath**\ 
 
 Path to where OS distro update is stored. (e.g. /install/osdistroupdates/rhels6.2-x86_64-20120716-update)
 


\ **downloadtime**\ 
 
 The timestamp when OS distro update was downloaded..
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

