
#########
nodepos.5
#########

.. highlight:: perl


****
NAME
****


\ **nodepos**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **nodepos Attributes:**\   \ *node*\ , \ *rack*\ , \ *u*\ , \ *chassis*\ , \ *slot*\ , \ *room*\ , \ *height*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


Contains info about the physical location of each node.  Currently, this info is not used by xCAT, and therefore can be in whatevery format you want.  It will likely be used in xCAT in the future.


*******************
nodepos Attributes:
*******************



\ **node**\ 
 
 The node name or group name.
 


\ **rack**\ 
 
 The frame the node is in.
 


\ **u**\ 
 
 The vertical position of the node in the frame
 


\ **chassis**\ 
 
 The BladeCenter chassis the blade is in.
 


\ **slot**\ 
 
 The slot number of the blade in the chassis. For PCM, a comma-separated list of slot numbers is stored
 


\ **room**\ 
 
 The room where the node is located.
 


\ **height**\ 
 
 The server height in U(s).
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

