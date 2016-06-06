
########
policy.7
########

.. highlight:: perl


****
NAME
****


\ **policy**\  - a logical object definition in the xCAT database.


********
SYNOPSIS
********


\ **policy Attributes:**\   \ *commands*\ , \ *host*\ , \ *name*\ , \ *noderange*\ , \ *parameters*\ , \ *priority*\ , \ *rule*\ , \ *time*\ , \ *usercomment*\ 


***********
DESCRIPTION
***********


Logical objects of this type are stored in the xCAT database in one or more tables.  Use the following commands
to manipulate the objects: \ **mkdef**\ , \ **chdef**\ , \ **lsdef**\ , and \ **rmdef**\ .  These commands will take care of
knowing which tables the object attributes should be stored in.  The attribute list below shows, in
parentheses, what tables each attribute is stored in.


******************
policy Attributes:
******************



\ **commands**\  (policy.commands)
 
 The list of commands that this rule applies to.  Default is "\*" (all commands).
 


\ **host**\  (policy.host)
 
 The host from which users may issue the commands specified by this rule.  Default is "\*" (all hosts). Only all or one host is supported
 


\ **name**\  (policy.name)
 
 The username that is allowed to perform the commands specified by this rule.  Default is "\*" (all users).
 


\ **noderange**\  (policy.noderange)
 
 The Noderange that this rule applies to.  Default is "\*" (all nodes). Not supported with the \*def commands.
 


\ **parameters**\  (policy.parameters)
 
 A regular expression that matches the command parameters (everything except the noderange) that this rule applies to.  Default is "\*" (all parameters). Not supported with the \*def commands.
 


\ **priority**\  (policy.priority)
 
 The priority value for this rule.  This value is used to identify this policy data object (i.e. this rule) The table is sorted on this field with the lower the number the higher the priority. For example 1.0 is higher priority than 4.1 is higher than 4.9.
 


\ **rule**\  (policy.rule)
 
 Specifies how this rule should be applied.  Valid values are: allow, accept, trusted. Allow or accept  will allow the user to run the commands. Any other value will deny the user access to the commands. Trusted means that once this client has been authenticated via the certificate, all other information that is sent (e.g. the username) is believed without question.  This authorization should only be given to the xcatd on the management node at this time.
 


\ **time**\  (policy.time)
 
 Time ranges that this command may be executed in.  This is not supported.
 


\ **usercomment**\  (policy.comments)
 
 Any user-written notes.
 



********
SEE ALSO
********


\ **mkdef(1)**\ , \ **chdef(1)**\ , \ **lsdef(1)**\ , \ **rmdef(1)**\ 

