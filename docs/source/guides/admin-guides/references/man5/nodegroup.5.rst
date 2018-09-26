
###########
nodegroup.5
###########

.. highlight:: perl


****
NAME
****


\ **nodegroup**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **nodegroup Attributes:**\   \ *groupname*\ , \ *grouptype*\ , \ *members*\ , \ *membergroups*\ , \ *wherevals*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


Contains group definitions, whose membership is dynamic depending on characteristics of the node.


*********************
nodegroup Attributes:
*********************



\ **groupname**\ 
 
 Name of the group.
 


\ **grouptype**\ 
 
 The only current valid value is dynamic.  We will be looking at having the object def commands working with static group definitions in the nodelist table.
 


\ **members**\ 
 
 The value of the attribute is not used, but the attribute is necessary as a place holder for the object def commands.  (The membership for static groups is stored in the nodelist table.)
 


\ **membergroups**\ 
 
 This attribute stores a comma-separated list of nodegroups that this nodegroup refers to. This attribute is only used by PCM.
 


\ **wherevals**\ 
 
 A list of "attr\*val" pairs that can be used to determine the members of a dynamic group, the delimiter is "::" and the operator \* can be ==, =~, != or !~.
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

