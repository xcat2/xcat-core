
##########
switches.5
##########

.. highlight:: perl


****
NAME
****


\ **switches**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **switches Attributes:**\   \ *switch*\ , \ *snmpversion*\ , \ *username*\ , \ *password*\ , \ *privacy*\ , \ *auth*\ , \ *linkports*\ , \ *sshusername*\ , \ *sshpassword*\ , \ *protocol*\ , \ *switchtype*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


Parameters to use when interrogating switches


********************
switches Attributes:
********************



\ **switch**\ 
 
 The hostname/address of the switch to which the settings apply
 


\ **snmpversion**\ 
 
 The version to use to communicate with switch.  SNMPv1 is assumed by default.
 


\ **username**\ 
 
 The username to use for SNMPv3 communication, ignored for SNMPv1
 


\ **password**\ 
 
 The password string for SNMPv3 or community string for SNMPv1/SNMPv2.  Falls back to passwd table, and site snmpc value if using SNMPv1/SNMPv2.
 


\ **privacy**\ 
 
 The privacy protocol to use for v3. xCAT will use authNoPriv if this is unspecified. DES is recommended to use if v3 enabled, as it is the most readily available.
 


\ **auth**\ 
 
 The authentication protocol to use for SNMPv3.  SHA is assumed if v3 enabled and this is unspecified
 


\ **linkports**\ 
 
 The ports that connect to other switches. Currently, this column is only used by vlan configuration. The format is: "port_number:switch,port_number:switch...". Refer to the switch table for details on how to specify the port numbers.
 


\ **sshusername**\ 
 
 The remote login user name. It can be for ssh or telnet. If it is for telnet, set protocol to "telnet". If the sshusername is blank, the username, password and protocol will be retrieved from the passwd table with "switch" as the key.
 


\ **sshpassword**\ 
 
 The remote login password. It can be for ssh or telnet. If it is for telnet, set protocol to "telnet". If the sshusername is blank, the username, password and protocol will be retrieved from the passwd table with "switch" as the key.
 


\ **protocol**\ 
 
 Protocol for running remote commands for the switch. The valid values are: ssh, telnet. ssh is the default. If the sshusername is blank, the username, password and protocol will be retrieved from the passwd table with "switch" as the key. The passwd.comments attribute is used for protocol.
 


\ **switchtype**\ 
 
 The type of switch. It is used to identify the file name that implements the functions for this switch. The valid values are: Mellanox, Cisco, BNT and Juniper.
 


\ **comments**\ 



\ **disable**\ 




********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

