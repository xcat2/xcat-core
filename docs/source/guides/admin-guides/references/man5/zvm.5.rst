
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


\ **zvm Attributes:**\   \ *node*\ , \ *hcp*\ , \ *userid*\ , \ *nodetype*\ , \ *parent*\ , \ *comments*\ , \ *disable*\ 


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
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

