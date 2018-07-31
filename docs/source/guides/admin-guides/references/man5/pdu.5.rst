
#####
pdu.5
#####

.. highlight:: perl


****
NAME
****


\ **pdu**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **pdu Attributes:**\   \ *node*\ , \ *nodetype*\ , \ *pdutype*\ , \ *outlet*\ , \ *username*\ , \ *password*\ , \ *snmpversion*\ , \ *community*\ , \ *snmpuser*\ , \ *authtype*\ , \ *authkey*\ , \ *privtype*\ , \ *privkey*\ , \ *seclevel*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


Parameters to use when interrogating pdus


***************
pdu Attributes:
***************



\ **node**\ 
 
 The hostname/address of the pdu to which the settings apply
 


\ **nodetype**\ 
 
 The node type should be pdu
 


\ **pdutype**\ 
 
 The type of pdu
 


\ **outlet**\ 
 
 The pdu outlet count
 


\ **username**\ 
 
 The remote login user name
 


\ **password**\ 
 
 The remote login password
 


\ **snmpversion**\ 
 
 The version to use to communicate with switch.  SNMPv1 is assumed by default.
 


\ **community**\ 
 
 The community string to use for SNMPv1/v2
 


\ **snmpuser**\ 
 
 The username to use for SNMPv3 communication, ignored for SNMPv1
 


\ **authtype**\ 
 
 The authentication protocol(MD5|SHA) to use for SNMPv3.
 


\ **authkey**\ 
 
 The authentication passphrase for SNMPv3
 


\ **privtype**\ 
 
 The privacy protocol(AES|DES) to use for SNMPv3.
 


\ **privkey**\ 
 
 The privacy passphrase to use for SNMPv3.
 


\ **seclevel**\ 
 
 The Security Level(noAuthNoPriv|authNoPriv|authPriv) to use for SNMPv3.
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

