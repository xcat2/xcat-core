
###########
configfpc.1
###########

.. highlight:: perl


****
NAME
****


\ **configfpc**\  - discover the Fan Power Controllers (FPCs) and configure the FPC interface


********
SYNOPSIS
********


\ **configfpc**\  \ **-i**\  \ *interface*\ 

\ **configfpc**\  \ **-i**\  \ *interface*\  \ **-**\ **-ip**\  \ *default ip address*\ 

\ **configfpc**\  [\ **-V | -**\ **-verbose**\ ]

\ **configfpc**\  [\ **-h | -**\ **-help | -?**\ ]


***********
DESCRIPTION
***********


\ **configfpc**\  will discover and configure all FPCs that are set to the default IP address. If not supplied the default ip is 192.168.0.100.

The \ **-i**\  \ *interface*\  is required to direct \ **configfpc**\  to the xCAT MN interface which is on the same VLAN as the FPCs.

There are several bits of information that must be included in the xCAT database before running this command.

You must create the FPC node definitions for all FPCs being discovered including the IP address and switch port information.

The \ **configfpc**\  command discovers the FPCs and collects the MAC address. The MAC address is used to relate the FPC to a FPC node using the switch information for this MAC. Once the relationship is discovered the FPC is configured with the FPC node IP settings.

This process is repeated until no more FPCs are discovered.

For more information on xCAT support of NeXtScale and configfpc see the following doc:
XCAT_NeXtScale_Clusters


*******
OPTIONS
*******



\ **-i**\  \ *interface*\ 
 
 Use this flag to specify which xCAT MN interface (example: eth4) that is connected to the NeXtScale FPCs. This option is required.
 


\ **-**\ **-ip**\  \ *default ip address*\ 
 
 Use this flag to override the default ip address of 192.168.0.100 with a new address.
 


\ **-V | -**\ **-verbose**\ 
 
 Verbose mode
 



********
EXAMPLES
********



1. To discover and configure all NeXtScale Fan Power Controllers (FPCs) connected on eth0 interface.
 
 
 .. code-block:: perl
 
   configfpc -i eth0
 
 


2. To override the default ip address and run in Verbose mode.
 
 
 .. code-block:: perl
 
   configfpc -i eth0 --ip 196.68.0.100 -V
 
 


