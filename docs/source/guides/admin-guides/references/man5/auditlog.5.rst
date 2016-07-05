
##########
auditlog.5
##########

.. highlight:: perl


****
NAME
****


\ **auditlog**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **auditlog Attributes:**\   \ *recid*\ , \ *audittime*\ , \ *userid*\ , \ *clientname*\ , \ *clienttype*\ , \ *command*\ , \ *noderange*\ , \ *args*\ , \ *status*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


Audit Data log.


********************
auditlog Attributes:
********************



\ **recid**\ 
 
 The record id.
 


\ **audittime**\ 
 
 The timestamp for the audit entry.
 


\ **userid**\ 
 
 The user running the command.
 


\ **clientname**\ 
 
 The client machine, where the command originated.
 


\ **clienttype**\ 
 
 Type of command: cli,java,webui,other.
 


\ **command**\ 
 
 Command executed.
 


\ **noderange**\ 
 
 The noderange on which the command was run.
 


\ **args**\ 
 
 The command argument list.
 


\ **status**\ 
 
 Allowed or Denied.
 


\ **comments**\ 
 
 Any user-provided notes.
 


\ **disable**\ 
 
 Do not use.  tabprune will not work if set to yes or 1
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

