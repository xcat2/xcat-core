
###############
discoverydata.5
###############

.. highlight:: perl


****
NAME
****


\ **discoverydata**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **discoverydata Attributes:**\   \ *uuid*\ , \ *node*\ , \ *method*\ , \ *discoverytime*\ , \ *arch*\ , \ *cpucount*\ , \ *cputype*\ , \ *memory*\ , \ *mtm*\ , \ *serial*\ , \ *nicdriver*\ , \ *nicipv4*\ , \ *nichwaddr*\ , \ *nicpci*\ , \ *nicloc*\ , \ *niconboard*\ , \ *nicfirm*\ , \ *switchname*\ , \ *switchaddr*\ , \ *switchdesc*\ , \ *switchport*\ , \ *otherdata*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


Discovery data which sent from genesis.


*************************
discoverydata Attributes:
*************************



\ **uuid**\ 
 
 The uuid of the node which send out the discovery request.
 


\ **node**\ 
 
 The node name which assigned to the discovered node.
 


\ **method**\ 
 
 The method which handled the discovery request. The method could be one of: switch, blade, profile, sequential.
 


\ **discoverytime**\ 
 
 The last time that xCAT received the discovery message.
 


\ **arch**\ 
 
 The architecture of the discovered node. e.g. x86_64.
 


\ **cpucount**\ 
 
 The number of cores multiply by threads core supported for the discovered node. e.g. 192.
 


\ **cputype**\ 
 
 The cpu type of the discovered node. e.g. Intel(R) Xeon(R) CPU E5-2690 0 @ 2.90GHz
 


\ **memory**\ 
 
 The memory size of the discovered node. e.g. 198460852
 


\ **mtm**\ 
 
 The machine type model of the discovered node. e.g. 786310X
 


\ **serial**\ 
 
 The serial number of the discovered node. e.g. 1052EFB
 


\ **nicdriver**\ 
 
 The driver of the nic. The value should be comma separated <nic name!driver name>. e.g. eth0!be2net,eth1!be2net
 


\ **nicipv4**\ 
 
 The ipv4 address of the nic. The value should be comma separated <nic name!ipv4 address>. e.g. eth0!10.0.0.212/8
 


\ **nichwaddr**\ 
 
 The hardware address of the nic. The should will be comma separated <nic name!hardware address>. e.g. eth0!34:40:B5:BE:DB:B0,eth1!34:40:B5:BE:DB:B4
 


\ **nicpci**\ 
 
 The pic device of the nic. The value should be comma separated <nic name!pci device>. e.g. eth0!0000:0c:00.0,eth1!0000:0c:00.1
 


\ **nicloc**\ 
 
 The location of the nic. The value should be comma separated <nic name!nic location>. e.g. eth0!Onboard Ethernet 1,eth1!Onboard Ethernet 2
 


\ **niconboard**\ 
 
 The onboard info of the nic. The value should be comma separated <nic name!onboard info>. e.g. eth0!1,eth1!2
 


\ **nicfirm**\ 
 
 The firmware description of the nic. The value should be comma separated <nic name!fimware description>. e.g. eth0!ServerEngines BE3 Controller,eth1!ServerEngines BE3 Controller
 


\ **switchname**\ 
 
 The switch name which the nic connected to. The value should be comma separated <nic name!switch name>. e.g. eth0!c909f06sw01
 


\ **switchaddr**\ 
 
 The address of the switch which the nic connected to. The value should be comma separated <nic name!switch address>. e.g. eth0!192.168.70.120
 


\ **switchdesc**\ 
 
 The description of the switch which the nic connected to. The value should be comma separated <nic name!switch description>. e.g. eth0!IBM Flex System Fabric EN4093 10Gb Scalable Switch, flash image: version 7.2.6, boot image: version 7.2.6
 


\ **switchport**\ 
 
 The port of the switch that the nic connected to. The value should be comma separated <nic name!switch port>. e.g. eth0!INTA2
 


\ **otherdata**\ 
 
 The left data which is not parsed to specific attributes (The complete message comes from genesis)
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

