
###########
rspconfig.1
###########

.. highlight:: perl


****
NAME
****


\ **rspconfig**\  - Configures nodes' service processors


********
SYNOPSIS
********


\ **rspconfig**\  [\ **-h | -**\ **-help | -v | -**\ **-version**\ ]

BMC/MPA specific:
=================


\ **rspconfig**\  \ *noderange*\  {\ **alert | snmpdest | community**\ }

\ **rspconfig**\  \ *noderange*\  \ **alert**\ ={\ **on | enable | off | disable**\ }

\ **rspconfig**\  \ *noderange*\  \ **snmpdest**\ =\ *snmpmanager-IP*\ 

\ **rspconfig**\  \ *noderange*\  \ **community**\ ={\ **public**\  | \ *string*\ }


BMC specific:
=============


\ **rspconfig**\  \ *noderange*\  {\ **ip | netmask | gateway | backupgateway | garp | vlan**\ }

\ **rspconfig**\  \ *noderange*\  \ **garp**\ =\ *time*\ 


OpenBMC specific:
=================


\ **rspconfig**\  \ *noderange*\  {\ **ip | netmask | gateway | hostname | vlan | sshcfg**\ }


MPA specific:
=============


\ **rspconfig**\  \ *noderange*\  {\ **sshcfg | snmpcfg | pd1 | pd2 | network | swnet | ntp | textid | frame**\ }

\ **rspconfig**\  \ *noderange*\  \ **USERID**\ ={\ **newpasswd**\ } \ **updateBMC**\ ={\ **y | n**\ }

\ **rspconfig**\  \ *noderange*\  \ **sshcfg**\ ={\ **enable | disable**\ }

\ **rspconfig**\  \ *noderange*\  \ **snmpcfg**\ ={\ **enable | disable**\ }

\ **rspconfig**\  \ *noderange*\  \ **solcfg**\ ={\ **enable | disable**\ }

\ **rspconfig**\  \ *noderange*\  \ **pd1**\ ={\ **nonred | redwoperf | redwperf**\ }

\ **rspconfig**\  \ *noderange*\  \ **pd2**\ ={\ **nonred | redwoperf | redwperf**\ }

\ **rspconfig**\  \ *noderange*\  \ **network**\ ={[\ *ip*\ ],[\ *host*\ ],[\ *gateway*\ ],[\ *netmask*\ ]|\*}

\ **rspconfig**\  \ *noderange*\  \ **initnetwork**\ ={[\ *ip*\ ],[\ *host*\ ],[\ *gateway*\ ],[\ *netmask*\ ]|\*}

\ **rspconfig**\  \ *noderange*\  \ **textid**\ ={\* | \ *textid*\ }

\ **rspconfig**\  \ *singlenode*\  \ **frame**\ ={\ *frame_number*\ }

\ **rspconfig**\  \ *noderange*\  \ **frame**\ ={\*}

\ **rspconfig**\  \ *noderange*\  \ **swnet**\ ={[\ **ip**\ ],[\ **gateway**\ ],[\ **netmask**\ ]}

\ **rspconfig**\  \ *noderange*\  \ **ntp**\ ={[\ **ntpenable**\ ],[\ **ntpserver**\ ],[\ **frequency**\ ],[\ **v3**\ ]}


FSP/CEC specific:
=================


\ **rspconfig**\  \ *noderange*\  {\ **autopower | iocap | decfg | memdecfg | procdecfg | time | date | spdump | sysdump | network**\ }

\ **rspconfig**\  \ *noderange*\  \ **autopower**\ ={\ **enable | disable**\ }

\ **rspconfig**\  \ *noderange*\  \ **iocap**\ ={\ **enable | disable**\ }

\ **rspconfig**\  \ *noderange*\  \ **time**\ =\ *hh:mm:ss*\ 

\ **rspconfig**\  \ *noderange*\  \ **date**\ =\ *mm:dd:yyyy*\ 

\ **rspconfig**\  \ *noderange*\  \ **decfg**\ ={\ **enable|disable**\ :\ *policyname,...*\ }

\ **rspconfig**\  \ *noderange*\  \ **procdecfg**\ ={\ **configure|deconfigure**\ :\ *processingunit*\ :\ *id,...*\ }

\ **rspconfig**\  \ *noderange*\  \ **memdecfg**\ ={\ **configure|deconfigure**\ :\ *processingunit*\ :\ **unit|bank**\ :\ *id,...*\ >}

\ **rspconfig**\  \ *noderange*\  \ **network**\ ={\ **nic,**\ \*}

\ **rspconfig**\  \ *noderange*\  \ **network**\ ={\ **nic,[IP,][hostname,][gateway,][netmask]**\ }

\ **rspconfig**\  \ *noderange*\  \ **network**\ ={\ **nic,0.0.0.0**\ }

\ **rspconfig**\  \ *noderange*\  \ **HMC_passwd**\ ={\ *currentpasswd,newpasswd*\ }

\ **rspconfig**\  \ *noderange*\  \ **admin_passwd**\ ={\ *currentpasswd,newpasswd*\ }

\ **rspconfig**\  \ *noderange*\  \ **general_passwd**\ ={\ **currentpasswd,newpasswd**\ }

\ **rspconfig**\  \ *noderange*\  \*\ **_passwd**\ ={\ **currentpasswd,newpasswd**\ }

\ **rspconfig**\  \ *noderange*\  {\ *hostname*\ }

\ **rspconfig**\  \ *noderange*\  \ **hostname**\ ={\* | \ *name*\ }

\ **rspconfig**\  \ *noderange*\  \ **-**\ **-resetnet**\ 


Flex system Specific:
=====================


\ **rspconfig**\  \ *noderange*\  \ **sshcfg**\ ={\ **enable | disable**\ }

\ **rspconfig**\  \ *noderange*\  \ **snmpcfg**\ ={\ **enable | disable**\ }

\ **rspconfig**\  \ *noderange*\  \ **network**\ ={[\ **ip**\ ],[\ **host**\ ],[\ **gateway**\ ],[\ **netmask**\ ] | \*}

\ **rspconfig**\  \ *noderange*\  \ **solcfg**\ ={\ **enable | disable**\ }

\ **rspconfig**\  \ *noderange*\  \ **textid**\ ={\* | \ *textid*\ }

\ **rspconfig**\  \ *noderange*\  \ **cec_off_policy**\ ={\ **poweroff | stayon**\ }


BPA/Frame Specific:
===================


\ **rspconfig**\  \ *noderange*\  {\ **network**\ }

\ **rspconfig**\  \ *noderange*\  \ **network**\ ={\ **nic,**\ \*}

\ **rspconfig**\  \ *noderange*\  \ **network**\ ={\ **nic,[IP,][hostname,][gateway,][netmask]**\ }

\ **rspconfig**\  \ *noderange*\  \ **network**\ ={\ **nic,0.0.0.0**\ }

\ **rspconfig**\  \ *noderange*\  \ **HMC_passwd**\ ={\ *currentpasswd,newpasswd*\ }

\ **rspconfig**\  \ *noderange*\  \ **admin_passwd**\ ={\ *currentpasswd,newpasswd*\ }

\ **rspconfig**\  \ *noderange*\  \ **general_passwd**\ ={\ **currentpasswd,newpasswd**\ }

\ **rspconfig**\  \ *noderange*\  \*\ **_passwd**\ ={\ **currentpasswd,newpasswd**\ }

\ **rspconfig**\  \ *noderange*\  {\ **hostname**\ }

\ **rspconfig**\  \ *noderange*\  \ **hostname**\ ={\* | \ *name*\ }

\ **rspconfig**\  \ *noderange*\  \ **-**\ **-resetnet**\ 


FSP/CEC (using Direct FSP Management) Specific:
===============================================


\ **rspconfig**\  \ *noderange*\  \ **HMC_passwd**\ ={\ *currentpasswd,newpasswd*\ }

\ **rspconfig**\  \ *noderange*\  \ **admin_passwd**\ ={\ *currentpasswd,newpasswd*\ }

\ **rspconfig**\  \ *noderange*\  \ **general_passwd**\ ={\ **currentpasswd,newpasswd**\ }

\ **rspconfig**\  \ *noderange*\  \*\ **_passwd**\ ={\ **currentpasswd,newpasswd**\ }

\ **rspconfig**\  \ *noderange*\  {\ **sysname**\ }

\ **rspconfig**\  \ *noderange*\  \ **sysname**\ ={\* | \ *name*\ }

\ **rspconfig**\  \ *noderange*\  {\ **pending_power_on_side**\ }

\ **rspconfig**\  \ *noderange*\  \ **pending_power_on_side**\ ={\ **temp | perm**\ }

\ **rspconfig**\  \ *noderange*\  {\ **cec_off_policy**\ }

\ **rspconfig**\  \ *noderange*\  \ **cec_off_policy**\ ={\ **poweroff | stayon**\ }

\ **rspconfig**\  \ *noderange*\  {\ **BSR**\ }

\ **rspconfig**\  \ *noderange*\  {\ **huge_page**\ }

\ **rspconfig**\  \ *noderange*\  \ **huge_page**\ ={\ *NUM*\ }

\ **rspconfig**\  \ *noderange*\  {\ **setup_failover**\ }

\ **rspconfig**\  \ *noderange*\  \ **setup_failover**\ ={\ **enable | disable**\ }

\ **rspconfig**\  \ *noderange*\  {\ **force_failover**\ }

\ **rspconfig**\  \ *noderange*\  \ **-**\ **-resetnet**\ 


BPA/Frame (using Direct FSP Management) Specific:
=================================================


\ **rspconfig**\  \ *noderange*\  \ **HMC_passwd**\ ={\ *currentpasswd,newpasswd*\ }

\ **rspconfig**\  \ *noderange*\  \ **admin_passwd**\ ={\ *currentpasswd,newpasswd*\ }

\ **rspconfig**\  \ *noderange*\  \ **general_passwd**\ ={\ **currentpasswd,newpasswd**\ }

\ **rspconfig**\  \ *noderange*\  \*\ **_passwd**\ ={\ **currentpasswd,newpasswd**\ }

\ **rspconfig**\  \ *noderange*\  {\ **frame**\ }

\ **rspconfig**\  \ *noderange*\  \ **frame**\ ={\* | \ *frame_number*\ }

\ **rspconfig**\  \ *noderange*\  {\ **sysname**\ }

\ **rspconfig**\  \ *noderange*\  \ **sysname**\ ={\* | \ *name*\ }

\ **rspconfig**\  \ *noderange*\  {\ **pending_power_on_side**\ }

\ **rspconfig**\  \ *noderange*\  \ **pending_power_on_side**\ ={\ **temp | perm**\ }

\ **rspconfig**\  \ *noderange*\  \ **-**\ **-resetnet**\ 


HMC Specific:
=============


\ **rspconfig**\  \ *noderange*\  {\ **sshcfg**\ }

\ **rspconfig**\  \ *noderange*\  \ **sshcfg**\ ={\ **enable | disable**\ }

\ **rspconfig**\  \ *noderange*\  \ **-**\ **-resetnet**\ 



***********
DESCRIPTION
***********


\ **rspconfig**\  configures various settings in the nodes' service processors.

For options \ **autopower | iocap | decfg | memdecfg | procdecfg | time | date | spdump | sysdump | network**\ , user need to use \ *chdef -t site enableASMI=yes*\  to enable ASMI first.


*******
OPTIONS
*******



\ **alert={on | enable | off | disable}**\ 
 
 Turn on or off SNMP alerts.
 


\ **autopower**\ ={\ *enable*\  | \ *disable*\ }
 
 Select the policy for auto power restart. If enabled, the system will boot automatically once power is restored after a power disturbance.
 


\ **backupgateway**\ 
 
 Get the BMC backup gateway ip address.
 


\ **community**\ ={\ **public**\  | \ *string*\ }
 
 Get or set the SNMP commmunity value. The default is \ **public**\ .
 


\ **date**\ =\ *mm:dd:yyy*\ 
 
 Enter the current date.
 


\ **decfg**\ ={\ **enable | disable**\ :\ *policyname,...*\ }
 
 Enables or disables deconfiguration policies.
 


\ **frame**\ ={\ *framenumber*\  | \*}
 
 Set or get frame number.  If no framenumber and \* specified, framenumber for the nodes will be displayed and updated in xCAAT database.  If framenumber is specified, it only supports single node and the framenumber will be set for that frame.  If \* is specified, it supports noderange and all the frame numbers for the noderange will be read from xCAT database and set to frames. Setting the frame number is a disruptive command which requires all CECs to be powered off prior to issuing the command.
 


\ **cec_off_policy**\ ={\ **poweroff | stayon**\ }
 
 Set or get cec off policy after lpars are powered off.  If no cec_off_policy value specified, the cec_off_policy for the nodes will be displayed. the cec_off_policy has two values: \ **poweroff**\  and \ **stayon**\ . \ **poweroff**\  means Power off when last partition powers off. \ **stayon**\  means Stay running after last partition powers off. If cec_off_policy value is specified, the cec off policy will be set for that cec.
 


\ **HMC_passwd**\ ={\ *currentpasswd,newpasswd*\ }
 
 Change the password of the userid \ **HMC**\  for CEC/Frame. If the CEC/Frame is the factory default, the currentpasswd should NOT be specified; otherwise, the currentpasswd should be specified to the current password of the userid \ **HMC**\  for the CEC/Frame.
 


\ **admin_passwd**\ ={\ *currentpasswd,newpasswd*\ }
 
 Change the password of the userid \ **admin**\  for CEC/Frame from currentpasswd to newpasswd. If the CEC/Frame is the factory default, the currentpasswd should NOT be specified; otherwise, the currentpasswd should be specified to the current password of the userid \ **admin**\  for the CEC/Frame.
 


\ **general_passwd**\ ={\ *currentpasswd,newpasswd*\ }
 
 Change the password of the userid \ **general**\  for CEC/Frame from currentpasswd to newpasswd. If the CEC/Frame is the factory default, the currentpasswd should NOT be specified; otherwise, the currentpasswd should be specified to the current password of the userid \ **general**\  for the CEC/Frame.
 


\*\ **_passwd**\ ={\ *currentpasswd,newpasswd*\ }
 
 Change the passwords of the userids \ **HMC**\ , \ **admin**\  and \ **general**\  for CEC/Frame from currentpasswd to newpasswd. If the CEC/Frame is the factory default, the currentpasswd should NOT be specified; otherwise, if the current passwords of the userids \ **HMC**\ , \ **admin**\  and \ **general**\  for CEC/Frame are the same one, the currentpasswd should be specified to the current password, and then the password will be changed to the newpasswd. If the CEC/Frame is NOT the factory default, and the current passwords of the userids \ **HMC**\ , \ **admin**\  and \ **general**\  for CEC/Frame are NOT the same one, this option could NOT be used, and we should change the password one by one.
 


\ **frequency**\ 
 
 The NTP update frequency (in minutes).
 


\ **garp**\ =\ *time*\ 
 
 Get or set Gratuitous ARP generation interval. The unit is number of 1/2 second.
 


\ **gateway**\ 
 
 The gateway ip address.
 


\ **hostname**\ 
 
 Display the CEC/BPA system names.
 


\ **BSR**\ 
 
 Get Barrier Synchronization Register (BSR) allocation for a CEC.
 


\ **huge_page**\ 
 
 Query huge page information or request NUM of huge pages for CEC. If no value specified, it means query huge page information for the specified CECs, if a CEC is specified, the specified huge_page value NUM will be used as the requested number of huge pages for the CEC, if CECs are specified, it means to request the same NUM huge pages for all the specified CECs.
 


\ **setup_failover**\ ={\ **enable**\  | \ **disable**\ }
 
 Enable or disable the service processor failover function of a CEC or display status of this function.
 


\ **force_failover**\ 
 
 Force a service processor failover from the primary service processor to the secondary service processor.
 


\ **hostname**\ ={\* | \ *name*\ }
 
 Set CEC/BPA system names to the names in xCAT DB or the input name.
 


\ **iocap**\ ={\ **enable**\  | \ **disable**\ }
 
 Select the policy for I/O Adapter Enlarged Capacity. This option controls the size of PCI memory space allocated to each PCI slot.
 


\ **hostname**\ 
 
 Get or set hostname on the service processor.
 


\ **vlan**\ 
 
 Get or set vlan ID. For get vlan ID, if vlan is not enabled, 'BMC VLAN disabled' will be outputed. For set vlan ID, the valid value are [1-4096].
 


\ **ip**\ 
 
 The ip address.
 


\ **memdecfg**\ ={\ **configure | deconfigure**\ :\ *processingunit*\ :\ *unit|bank*\ :\ *id,...*\ }
 
 Select whether each memory bank should be enabled or disabled. State changes take effect on the next platform boot.
 


\ **netmask**\ 
 
 The subnet mask.
 


\ **network**\ ={[\ *ip*\ ],[\ *host*\ ],[\ *gateway*\ ],[\ *netmask*\ ]|\*}
 
 For MPA:  get or set the MPA network parameters. If '\*' is specified, all parameters are read from the xCAT database.
 
 For FSP of Flex system P node: set the network parameters. If '\*' is specified, all parameters are read from the xCAT database.
 


\ **initnetwork**\ ={[\ *ip*\ ],[\ *host*\ ],[\ *gateway*\ ],[\ *netmask*\ ]|\*}
 
 For MPA only. Connecting to the IP of MPA from the hosts.otherinterfaces to set the MPA network parameters. If '\*' is specified, all parameters are read from the xCAT database.
 


\ **network**\ ={\ *nic*\ ,{[\ *ip*\ ],[\ *host*\ ],[\ *gateway*\ ],[\ *netmask*\ ]}|\*}
 
 Not only for FSP/BPA but also for IMM. Get or set the FSP/BPA/IMM network parameters. If '\*' is specified, all parameters are read from the xCAT database. 
 If the value of \ *ip*\  is '0.0.0.0', this \ *nic*\  will be configured as a DHCP client. Otherwise this \ *nic*\  will be configured with a static IP.
 
 Note that IPs of FSP/BPAs will be updated with this option, user needs to put the new IPs to /etc/hosts manually or with xCAT command makehosts. For more details, see the man page of makehosts.
 


\ **nonred**\ 
 
 Allows loss of redundancy.
 


\ **ntp**\ ={[\ *ntpenable*\ ],[\ *ntpserver*\ ],[\ *frequency*\ ],[\ *v3*\ ]}
 
 Get or set the MPA Network Time Protocol (NTP) parameters.
 


\ **ntpenable**\ 
 
 Enable or disable NTP (enable|disable).
 


\ **ntpserver**\ 
 
 Get or set NTP server IP address or name.
 


\ **pd1**\ ={\ **nonred | redwoperf | redwperf**\ }
 
 Power Domain 1 - determines how an MPA responds to a loss of redundant power.
 


\ **pd2**\ ={\ **nonred | redwoperf | redwperf**\ }
 
 Power Domain 2 - determines how an MPA responds to a loss of redundant power.
 


\ **procdecfg**\ ={\ **configure|deconfigure**\ :\ *processingunit*\ :\ *id,...*\ }
 
 Selects whether each processor should be enabled or disabled. State changes take effect on the next platform boot.
 


\ **redwoperf**\ 
 
 Prevents components from turning on that will cause loss of power redundancy.
 


\ **redwperf**\ 
 
 Power throttles components to maintain power redundancy and prevents components from turning on that will cause loss of power redundancy.
 


\ **snmpcfg**\ ={\ **enable | disable**\ }
 
 Enable or disable SNMP on MPA.
 


\ **snmpdest**\ =\ *snmpmanager-IP*\ 
 
 Get or set where the SNMP alerts should be sent to.
 


\ **solcfg**\ ={\ **enable | disable**\ }
 
 Enable or disable the sol on MPA (or CMM) and blade servers belongs to it.
 


\ **spdump**\ 
 
 Performs a service processor dump.
 


\ **sshcfg**\ ={\ **enable | disable**\ }
 
 Enable or disable SSH on MPA.
 


\ **sshcfg**\ 
 
 Copy SSH keys.
 


\ **swnet**\ ={[\ *ip*\ ],[\ *gateway*\ ],[\ *netmask*\ ]}
 
 Set the Switch network parameters.
 


\ **sysdump**\ 
 
 Performs a system dump.
 


\ **sysname**\ 
 
 Query or set sysname for CEC or Frame. If no value specified, means to query sysname of the specified nodes. If '\*' specified, it means to set sysname for the specified nodes, and the sysname values would get from xCAT datebase. If a string is specified, it means to use the string as sysname value to set for the specified node.
 


\ **pending_power_on_side**\ ={\ **temp|perm**\ }
 
 List or set pending power on side for CEC or Frame. If no pending_power_on_side value specified, the pending power on side for the CECs or frames will be displayed. If specified, the pending_power_on_side value will be set to CEC's FSPs or Frame's BPAs. The value 'temp' means T-side or temporary side. The value 'perm' means P-side or permanent side.
 


\ **time**\ =\ *hh:mm:ss*\ 
 
 Enter the current time in UTC (Coordinated Universal Time) format.
 


\ **textid**\ ={\ *\\*|textid*\ }
 
 Set the blade or MPA textid. When using '\*', the textid used is the node name specified on the command-line. Note that when specifying an actual textid, only a single node can be specified in the noderange.
 


\ **USERID**\ ={\ *newpasswd*\ } \ **updateBMC**\ ={\ **y|n**\ }
 
 Change the password of the userid \ **USERID**\  for CMM in Flex system cluster. The option \ *updateBMC*\  can be used to specify whether updating the password of BMCs that connected to the specified CMM. The value is 'y' by default which means whenever updating the password of CMM, the password of BMCs will be also updated. Note that there will be several seconds needed before this command complete.
 
 If value "\*" is specified for USERID and the object node is \ *Flex System X node*\ , the password used to access the BMC of the System X node through IPMI will be updated as the same password of the userid \ **USERID**\  of the CMM in the same cluster.
 


\ **-**\ **-resetnet**\ 
 
 Reset the network interfaces of the specified nodes.
 


\ **v3**\ 
 
 Enable or disable v3 authentication (enable|disable).
 


\ **-h | -**\ **-help**\ 
 
 Prints out a brief usage message.
 


\ **-v**\  | \ **-**\ **-version**\ 
 
 Display the version number.
 



********
EXAMPLES
********



1. To setup new ssh keys on the Management Module mm:
 
 
 .. code-block:: perl
 
   rspconfig mm snmpcfg=enable sshcfg=enable
 
 


2. To turn on SNMP alerts for node5:
 
 
 .. code-block:: perl
 
   rspconfig node5 alert=on
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   node5: Alerts: enabled
 
 


3. To display the destination setting for SNMP alerts for node4:
 
 
 .. code-block:: perl
 
   rspconfig node4 snmpdest
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   node4: BMC SNMP Destination 1: 9.114.47.227
 
 


4.
 
 To display the frame number for frame 9A00-10000001
 
 
 .. code-block:: perl
 
   rspconfig> 9A00-10000001 frame
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   9A00-10000001: 1
 
 


5. To set the frame number for frame 9A00-10000001
 
 
 .. code-block:: perl
 
   rspconfig 9A00-10000001 frame=2
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   9A00-10000001: SUCCESS
 
 


6. To set the frame numbers for frame 9A00-10000001 and 9A00-10000002
 
 
 .. code-block:: perl
 
   rspconfig 9A00-10000001,9A00-10000002 frame=*
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   9A00-10000001: SUCCESS
   9A00-10000002: SUCCESS
 
 


7. To display the MPA network parameters for mm01:
 
 
 .. code-block:: perl
 
   rspconfig mm01 network
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   mm01: MM IP: 192.168.1.47
   mm01: MM Hostname: MM001125C31F28
   mm01: Gateway: 192.168.1.254
   mm01: Subnet Mask: 255.255.255.224
 
 


8. To change the MPA network parameters with the values in the xCAT database for mm01:
 
 
 .. code-block:: perl
 
   rspconfig mm01 network=*
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   mm01: MM IP: 192.168.1.47
   mm01: MM Hostname: mm01
   mm01: Gateway: 192.168.1.254
   mm01: Subnet Mask: 255.255.255.224
 
 


9. To change only the gateway parameter for the MPA network mm01:
 
 
 .. code-block:: perl
 
   rspconfig mm01 network=,,192.168.1.1,
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   mm01: Gateway: 192.168.1.1
 
 


10. To display the FSP network parameters for fsp01:
 
 
 .. code-block:: perl
 
   rspconfig> fsp01 network
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   fsp01:
          eth0:
                  IP Type: Dynamic
                  IP Address: 192.168.1.215
                  Hostname:
                  Gateway:
                  Netmask: 255.255.255.0
  
          eth1:
                  IP Type: Dynamic
                  IP Address: 192.168.200.51
                  Hostname: fsp01
                  Gateway:
                  Netmask: 255.255.255.0
 
 


11. To change the FSP network parameters with the values in command line for eth0 on fsp01:
 
 
 .. code-block:: perl
 
   rspconfig fsp01 network=eth0,192.168.1.200,fsp01,,255.255.255.0
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   fsp01: Success to set IP address,hostname,netmask
 
 


12. To change the FSP network parameters with the values in the xCAT database for eth0 on fsp01:
 
 
 .. code-block:: perl
 
   rspconfig fsp01 network=eth0,*
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   fsp01: Success to set IP address,hostname,gateway,netmask
 
 


13. To configure eth0 on fsp01 to get dynamic IP address from DHCP server:
 
 
 .. code-block:: perl
 
   rspconfig fsp01 network=eth0,0.0.0.0
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   fsp01: Success to set IP type to dynamic.
 
 


14. To get the current power redundancy mode for power domain 1 on mm01:
 
 
 .. code-block:: perl
 
   rspconfig mm01 pd1
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   mm01: Redundant without performance impact
 
 


15. To change the current power redundancy mode for power domain 1 on mm01 to non-redundant:
 
 
 .. code-block:: perl
 
   rspconfig mm01 pd1=nonred
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   mm01: nonred
 
 


16. To enable NTP with an NTP server address of 192.168.1.1, an update frequency of 90 minutes, and with v3 authentication enabled on mm01:
 
 
 .. code-block:: perl
 
   rspconfig mm01 ntp=enable,192.168.1.1,90,enable
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   mm01: NTP: disabled
   mm01: NTP Server: 192.168.1.1
   mm01: NTP: 90 (minutes)
   mm01: NTP: enabled
 
 


17. To disable NTP v3 authentication only on mm01:
 
 
 .. code-block:: perl
 
   rspconfig mm01 ntp=,,,disable
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   mm01: NTP v3: disabled
 
 


18. To disable Predictive Failure and L2 Failure deconfiguration policies on mm01:
 
 
 .. code-block:: perl
 
   rspconfig mm01 decfg=disable:predictive,L3
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   mm01: Success
 
 


19. To deconfigure processors 4 and 5 of Processing Unit 0 on mm01:
 
 
 .. code-block:: perl
 
   rspconfig mm01 procedecfg=deconfigure:0:4,5
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   mm01: Success
 
 


20. To check if CEC sysname set correct on mm01:
 
 
 .. code-block:: perl
 
   rspconfig mm01 sysname
  
   mm01: mm01
  
   rspconfig mm01 sysname=cec01
  
   mm01: Success
  
   rspconfig mm01 sysname
  
   mm01: cec01
 
 


21. To check and change the pending_power_on_side value of cec01's fsps:
 
 
 .. code-block:: perl
 
   rspconfig cec01 pending_power_on_side
  
   cec01: Pending Power On Side Primary: temp
   cec01: Pending Power On Side Secondary: temp
  
   rspconfig cec01 pending_power_on_side=perm
  
   cec01: Success
  
   rspconfig cec01 pending_power_on_side
  
   cec01: Pending Power On Side Primary: perm
   cec01: Pending Power On Side Secondary: perm
 
 


22. To show the BSR allocation for cec01:
 
 
 .. code-block:: perl
 
   rspconfig cec01 BSR
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   cec01: Barrier Synchronization Register (BSR)
   cec01: Number of BSR arrays: 256
   cec01: Bytes per BSR array : 4096
   cec01: Available BSR array : 0
   cec01: Partition name: BSR arrays
   cec01: lpar01        : 32
   cec01: lpar02        : 32
   cec01: lpar03        : 32
   cec01: lpar04        : 32
   cec01: lpar05        : 32
   cec01: lpar06        : 32
   cec01: lpar07        : 32
   cec01: lpar08        : 32
 
 


23. To query the huge page information for CEC1, enter:
 
 
 .. code-block:: perl
 
   rspconfig CEC1 huge_page
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   CEC1: Huge Page Memory
   CEC1: Available huge page memory(in pages):    0
   CEC1: Configurable huge page memory(in pages): 12
   CEC1: Page Size (in GB):                       16
   CEC1: Maximum huge page memory(in pages):      24
   CEC1: Requested huge page memory(in pages):    15
   CEC1: Partition name: Huge pages
   CEC1: lpar1         : 3
   CEC1: lpar5         : 3
   CEC1: lpar9         : 3
   CEC1: lpar13        : 3
   CEC1: lpar17        : 0
   CEC1: lpar21        : 0
   CEC1: lpar25        : 0
   CEC1: lpar29        : 0
 
 


24. To request 10 huge pages for CEC1, enter:
 
 
 .. code-block:: perl
 
   rspconfig CEC1 huge_page=10
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   CEC1: Success
 
 


25. To disable service processor failover for cec01, in order to complete this command, the user should power off cec01 first:
 
 
 .. code-block:: perl
 
   rspconfig cec01 setup_failover
  
   cec01: Failover status: Enabled
  
   rpower cec01 off
  
   rspconfig cec01 setup_failover=disable
  
   cec01: Success
  
   rspconfig cec01 setup_failover
  
   cec01: Failover status: Disabled
 
 


26. To force service processor failover for cec01:
 
 
 .. code-block:: perl
 
   lshwconn cec01
  
   cec01: 192.168.1.1: LINE DOWN
   cec01: 192.168.2.1: sp=primary,ipadd=192.168.2.1,alt_ipadd=unavailable,state=LINE UP
   cec01: 192.168.1.2: sp=secondary,ipadd=192.168.1.2,alt_ipadd=unavailable,state=LINE UP
   cec01: 192.168.2.2: LINE DOWN
   
   rspconfig cec01 force_failover
  
   cec01: Success.
   
   lshwconn> cec01                
  
   cec01: 192.168.1.1: sp=secondary,ipadd=192.168.1.1,alt_ipadd=unavailable,state=LINE UP
   cec01: 192.168.2.1: LINE DOWN
   cec01: 192.168.1.2: LINE DOWN
   cec01: 192.168.2.2: sp=primary,ipadd=192.168.2.2,alt_ipadd=unavailable,state=LINE UP
 
 


27.
 
 To deconfigure memory bank 9 and 10 of Processing Unit 0 on mm01:
 
 
 .. code-block:: perl
 
   rspconfig mm01 memdecfg=deconfigure:bank:0:9,10
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   mm01: Success
 
 


28.
 
 To reset the network interface of the specified nodes:
 
 
 .. code-block:: perl
 
   rspconfig --resetnet
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   Start to reset network..
  
   Reset network failed nodes:
  
   Reset network succeed nodes:
   Server-8233-E8B-SN1000ECP-A,Server-9119-FHA-SN0275995-B,Server-9119-FHA-SN0275995-A,
  
   Reset network finished.
 
 


29. To update the existing admin password on fsp:
 
 
 .. code-block:: perl
 
   rspconfig fsp admin_passwd=admin,abc123
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   fsp: Success
 
 


30. To set the initial password for user HMC on fsp:
 
 
 .. code-block:: perl
 
   rspconfig fsp HMC_passwd=,abc123
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   fsp: Success
 
 



********
SEE ALSO
********


noderange(3)|noderange.3, rpower(1)|rpower.1, rcons(1)|rcons.1, rinv(1)|rinv.1, rvitals(1)|rvitals.1, rscan(1)|rscan.1, rflash(1)|rflash.1

