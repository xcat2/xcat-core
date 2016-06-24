
######
deps.5
######

.. highlight:: perl


****
NAME
****


\ **deps**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **deps Attributes:**\   \ *node*\ , \ *nodedep*\ , \ *msdelay*\ , \ *cmd*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


Describes dependencies some nodes have on others.  This can be used, e.g., by rpower -d to power nodes on or off in the correct order.


****************
deps Attributes:
****************



\ **node**\ 
 
 The node name or group name.
 


\ **nodedep**\ 
 
 Comma-separated list of nodes or node groups it is dependent on.
 


\ **msdelay**\ 
 
 How long to wait between operating on the dependent nodes and the primary nodes.
 


\ **cmd**\ 
 
 Comma-separated list of which operation this dependency applies to.
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

