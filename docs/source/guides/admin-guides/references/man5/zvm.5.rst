
#####
zvm.5
#####

.. highlight:: perl


****
NAME
****


\ **zvm**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **zvm Attributes:**\   \ *node*\ , \ *hcp*\ , \ *userid*\ , \ *nodetype*\ , \ *parent*\ , \ *comments*\ , \ *disable*\ , \ *discovered*\ , \ *status*\ 


***********
DESCRIPTION
***********


List of z/VM virtual servers.


***************
zvm Attributes:
***************



\ **node**\ 
 
 The node name.
 


\ **hcp**\ 
 
 The hardware control point for this node.
 


\ **userid**\ 
 
 The z/VM userID of this node.
 


\ **nodetype**\ 
 
 The node type. Valid values: cec (Central Electronic Complex), lpar (logical partition), zvm (z/VM host operating system), and vm (virtual machine).
 


\ **parent**\ 
 
 The parent node. For LPAR, this specifies the CEC. For z/VM, this specifies the LPAR. For VM, this specifies the z/VM host operating system.
 


\ **comments**\ 
 
 Any user provided notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 


\ **discovered**\ 
 
 Set to '1' to indicate this node was discovered.
 


\ **status**\ 
 
 The processing status.  Key value pairs (key=value) indicating status of the node.  Multiple pairs are separated by semi-colons.  Keys include: CLONING, CLONE_ONLY.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

