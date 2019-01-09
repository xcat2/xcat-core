
###########
taskstate.7
###########

.. highlight:: perl


****
NAME
****


\ **taskstate**\  - a logical object definition in the xCAT database.


********
SYNOPSIS
********


\ **taskstate Attributes:**\   \ *command*\ , \ *disable*\ , \ *node*\ , \ *pid*\ , \ *reserve*\ , \ *state*\ 


***********
DESCRIPTION
***********


Logical objects of this type are stored in the xCAT database in one or more tables.  Use the following commands
to manipulate the objects: \ **mkdef**\ , \ **chdef**\ , \ **lsdef**\ , and \ **rmdef**\ .  These commands will take care of
knowing which tables the object attributes should be stored in.  The attribute list below shows, in
parentheses, what tables each attribute is stored in.


*********************
taskstate Attributes:
*********************



\ **command**\  (taskstate.command)
 
 Current command is running
 


\ **disable**\  (taskstate.disable)
 
 Set to 'yes' or '1' to comment out this row.
 


\ **node**\  (taskstate.node)
 
 The node name.
 


\ **pid**\  (taskstate.pid)
 
 The process id of the request process.
 


\ **reserve**\  (taskstate.reserve)
 
 used to lock the node
 


\ **state**\  (taskstate.state)
 
 The task state(callback, running) for the node.
 



********
SEE ALSO
********


\ **mkdef(1)**\ , \ **chdef(1)**\ , \ **lsdef(1)**\ , \ **rmdef(1)**\ 

