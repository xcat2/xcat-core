
#########
openbmc.5
#########

.. highlight:: perl


****
NAME
****


\ **openbmc**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **openbmc Attributes:**\   \ *node*\ , \ *bmc*\ , \ *consport*\ , \ *taggedvlan*\ , \ *username*\ , \ *password*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


Setting for nodes that are controlled by an on-board OpenBmc.


*******************
openbmc Attributes:
*******************



\ **node**\ 
 
 The node name or group name.
 


\ **bmc**\ 
 
 The hostname of the BMC adapter.
 


\ **consport**\ 
 
 The console port for OpenBMC.
 


\ **taggedvlan**\ 
 
 bmcsetup script will configure the network interface of the BMC to be tagged to the VLAN specified.
 


\ **username**\ 
 
 The BMC userid.
 


\ **password**\ 
 
 The BMC password.
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

