
###########
taskstate.5
###########

.. highlight:: perl


****
NAME
****


\ **taskstate**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **taskstate Attributes:**\   \ *node*\ , \ *command*\ , \ *state*\ , \ *pid*\ , \ *reserve*\ 


***********
DESCRIPTION
***********


The task state for the node.


*********************
taskstate Attributes:
*********************



\ **node**\ 
 
 The node name.
 


\ **command**\ 
 
 Current command is running
 


\ **state**\ 
 
 The task state(callback, running) for the node.
 


\ **pid**\ 
 
 The process id of the request process.
 


\ **reserve**\ 
 
 used to lock the node
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

