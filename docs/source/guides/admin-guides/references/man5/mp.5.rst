
####
mp.5
####

.. highlight:: perl


****
NAME
****


\ **mp**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **mp Attributes:**\   \ *node*\ , \ *mpa*\ , \ *id*\ , \ *nodetype*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


Contains the hardware control info specific to blades.  This table also refers to the mpa table, which contains info about each Management Module.


**************
mp Attributes:
**************



\ **node**\ 
 
 The blade node name or group name.
 


\ **mpa**\ 
 
 The management module used to control this blade.
 


\ **id**\ 
 
 The slot number of this blade in the BladeCenter chassis.
 


\ **nodetype**\ 
 
 The hardware type for mp node. Valid values: mm,cmm, blade.
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

