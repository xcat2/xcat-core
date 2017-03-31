
#####
pdu.5
#####

.. highlight:: perl


****
NAME
****


\ **pdu**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **pdu Attributes:**\   \ *node*\ , \ *nodetype*\ , \ *outlet*\ , \ *machinetype*\ , \ *modelnum*\ , \ *serialnum*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


Parameters to use when interrogating pdus


***************
pdu Attributes:
***************



\ **node**\ 
 
 The hostname/address of the pdu to which the settings apply
 


\ **nodetype**\ 
 
 The node type should be pdu
 


\ **outlet**\ 
 
 The pdu outlet count
 


\ **machinetype**\ 
 
 The pdu machine type
 


\ **modelnum**\ 
 
 The pdu model number
 


\ **serialnum**\ 
 
 The pdu serial number
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

