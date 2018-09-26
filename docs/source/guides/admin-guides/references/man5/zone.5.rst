
######
zone.5
######

.. highlight:: perl


****
NAME
****


\ **zone**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **zone Attributes:**\   \ *zonename*\ , \ *sshkeydir*\ , \ *sshbetweennodes*\ , \ *defaultzone*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


Defines a cluster zone for nodes that share root ssh key access to each other.


****************
zone Attributes:
****************



\ **zonename**\ 
 
 The name of the zone.
 


\ **sshkeydir**\ 
 
 Directory containing the shared root ssh RSA keys.
 


\ **sshbetweennodes**\ 
 
 Indicates whether passwordless ssh will be setup between the nodes of this zone. Values are yes/1 or no/0. Default is yes.
 


\ **defaultzone**\ 
 
 If nodes are not assigned to any other zone, they will default to this zone. If value is set to yes or 1.
 


\ **comments**\ 
 
 Any user-provided notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

