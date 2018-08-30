
###########
pduoutlet.5
###########

.. highlight:: perl


****
NAME
****


\ **pduoutlet**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **pduoutlet Attributes:**\   \ *node*\ , \ *pdu*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


Contains list of outlet numbers on the pdu each node is connected to.


*********************
pduoutlet Attributes:
*********************



\ **node**\ 
 
 The node name or group name.
 


\ **pdu**\ 
 
 a comma-separated list of outlet number for each PDU, ex: pdu1:outlet1,pdu2:outlet1
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

