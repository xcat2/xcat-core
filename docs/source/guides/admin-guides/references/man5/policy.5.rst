
########
policy.5
########

.. highlight:: perl


****
NAME
****


\ **policy**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **policy Attributes:**\   \ *priority*\ , \ *name*\ , \ *host*\ , \ *commands*\ , \ *noderange*\ , \ *parameters*\ , \ *time*\ , \ *rule*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


The policy table in the xCAT database controls who has authority to run specific xCAT operations. It is basically the Access Control List (ACL) for xCAT. It is sorted on the priority field before evaluating.


******************
policy Attributes:
******************



\ **priority**\ 
 
 The priority value for this rule.  This value is used to identify this policy data object (i.e. this rule) The table is sorted on this field with the lower the number the higher the priority. For example 1.0 is higher priority than 4.1 is higher than 4.9.
 


\ **name**\ 
 
 The username that is allowed to perform the commands specified by this rule.  Default is "\*" (all users).
 


\ **host**\ 
 
 The host from which users may issue the commands specified by this rule.  Default is "\*" (all hosts). Only all or one host is supported
 


\ **commands**\ 
 
 The list of commands that this rule applies to.  Default is "\*" (all commands).
 


\ **noderange**\ 
 
 The Noderange that this rule applies to.  Default is "\*" (all nodes). Not supported with the \*def commands.
 


\ **parameters**\ 
 
 A regular expression that matches the command parameters (everything except the noderange) that this rule applies to.  Default is "\*" (all parameters). Not supported with the \*def commands.
 


\ **time**\ 
 
 Time ranges that this command may be executed in.  This is not supported.
 


\ **rule**\ 
 
 Specifies how this rule should be applied.  Valid values are: allow, accept, trusted. Allow or accept  will allow the user to run the commands. Any other value will deny the user access to the commands. Trusted means that once this client has been authenticated via the certificate, all other information that is sent (e.g. the username) is believed without question.  This authorization should only be given to the xcatd on the management node at this time.
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

