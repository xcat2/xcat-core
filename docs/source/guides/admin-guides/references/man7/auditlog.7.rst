
##########
auditlog.7
##########

.. highlight:: perl


****
NAME
****


\ **auditlog**\  - a logical object definition in the xCAT database.


********
SYNOPSIS
********


\ **auditlog Attributes:**\   \ *args*\ , \ *audittime*\ , \ *clientname*\ , \ *clienttype*\ , \ *command*\ , \ *comments*\ , \ *disable*\ , \ *noderange*\ , \ *recid*\ , \ *status*\ , \ *userid*\ 


***********
DESCRIPTION
***********


Logical objects of this type are stored in the xCAT database in one or more tables.  Use the following commands
to manipulate the objects: \ **mkdef**\ , \ **chdef**\ , \ **lsdef**\ , and \ **rmdef**\ .  These commands will take care of
knowing which tables the object attributes should be stored in.  The attribute list below shows, in
parentheses, what tables each attribute is stored in.


********************
auditlog Attributes:
********************



\ **args**\  (auditlog.args)
 
 The command argument list.
 


\ **audittime**\  (auditlog.audittime)
 
 The timestamp for the audit entry.
 


\ **clientname**\  (auditlog.clientname)
 
 The client machine, where the command originated.
 


\ **clienttype**\  (auditlog.clienttype)
 
 Type of command: cli,java,webui,other.
 


\ **command**\  (auditlog.command)
 
 Command executed.
 


\ **comments**\  (auditlog.comments)
 
 Any user-provided notes.
 


\ **disable**\  (auditlog.disable)
 
 Do not use.  tabprune will not work if set to yes or 1
 


\ **noderange**\  (auditlog.noderange)
 
 The noderange on which the command was run.
 


\ **recid**\  (auditlog.recid)
 
 The record id.
 


\ **status**\  (auditlog.status)
 
 Allowed or Denied.
 


\ **userid**\  (auditlog.userid)
 
 The user running the command.
 



********
SEE ALSO
********


\ **mkdef(1)**\ , \ **chdef(1)**\ , \ **lsdef(1)**\ , \ **rmdef(1)**\ 

