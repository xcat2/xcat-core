
########
domain.5
########

.. highlight:: perl


****
NAME
****


\ **domain**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **domain Attributes:**\   \ *node*\ , \ *ou*\ , \ *authdomain*\ , \ *adminuser*\ , \ *adminpassword*\ , \ *type*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


Mapping of nodes to domain attributes


******************
domain Attributes:
******************



\ **node**\ 
 
 The node or group the entry applies to
 


\ **ou**\ 
 
 For an LDAP described machine account (i.e. Active Directory), the organizational unit to place the system.  If not set, defaults to cn=Computers,dc=your,dc=domain
 


\ **authdomain**\ 
 
 If a node should participate in an AD domain or Kerberos realm distinct from domain indicated in site, this field can be used to specify that
 


\ **adminuser**\ 
 
 Allow a node specific indication of Administrative user.  Most will want to just use passwd table to indicate this once rather than by node.
 


\ **adminpassword**\ 
 
 Allow a node specific indication of Administrative user password for the domain.  Most will want to ignore this in favor of passwd table.
 


\ **type**\ 
 
 Type, if any, of authentication domain to manipulate.  The only recognized value at the moment is activedirectory.
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

