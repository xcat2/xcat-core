
########
rpower.1
########

.. highlight:: perl


****
NAME
****


\ **rpower**\  - remote power control of nodes


********
SYNOPSIS
********


\ **rpower**\  \ *noderange*\  [\ **-**\ **-nodeps**\ ] [\ **on | onstandby | off | suspend | stat | state | reset | boot**\ ] [\ **-m**\  \ *table.column*\ ==\ *expectedstatus*\  [\ **-m**\  \ *table.column*\ =~\ *expectedstatus*\ ]] [\ **-t**\  \ *timeout*\ ] [\ **-r**\  \ *retrycount*\ ]

\ **rpower**\  [\ **-h | -**\ **-help | -v | -**\ **-version**\ ]

BMC (using IPMI) specific:
==========================


\ **rpower**\  \ *noderange*\  [\ **on | off | softoff | reset | boot | stat | state | status | wake | suspend**\  [\ **-w**\  \ *timeout*\ ] [\ **-o**\ ] [\ **-r**\ ]]

\ **rpower**\  \ *noderange*\  [\ **pduon | pduoff | pdustat**\ ]


PPC (with IVM or HMC) specific:
===============================


\ **rpower**\  \ *noderange*\  [\ **-**\ **-nodeps**\ ] {\ **of**\ }


CEC (with HMC) specific:
========================


\ **rpower**\  \ *noderange*\  [\ **on | off | reset | boot | onstandby**\ ]


LPAR (with HMC) specific:
=========================


\ **rpower**\  \ *noderange*\  [\ **on | off | stat | state | reset | boot | of | sms | softoff**\ ]


CEC (using Direct FSP Management) specific:
===========================================


\ **rpower**\  \ *noderange*\  [\ **onstandby | stat | state**\ ] [\ **-T tooltype**\ ]

\ **rpower**\  \ *noderange*\  [\ **on | off | resetsp**\ ]


Frame (using Direct FSP Management) specific:
=============================================


\ **rpower**\  \ *noderange*\  [\ **rackstandby | exit_rackstandby | stat | state | resetsp**\ ]


LPAR (using Direct FSP Management) specific:
============================================


\ **rpower**\  \ *noderange*\  [\ **on | off | stat | state | reset | boot | of | sms**\ ]


Blade (using Direct FSP Management) specific:
=============================================


\ **rpower**\  \ *noderange*\  [\ **on | onstandby | off | stat | state | sms**\ ]


Blade specific:
===============


\ **rpower**\  \ *noderange*\  [\ **cycle | softoff**\ ]


zVM specific:
=============


\ **rpower**\  \ *noderange*\  [\ **on | off | reset | stat | softoff**\ ]


docker specific:
================


\ **rpower**\  \ *noderange*\  [\ **start | stop | restart | pause | unpause | state**\ ]


pdu specific:
=============


\ **rpower**\  \ *noderange*\  [\ **stat | off | on**\ ]



***********
DESCRIPTION
***********


\ **rpower**\  controls the power for a single or range of nodes,  via the out-of-band path.


*******
OPTIONS
*******



\ **on**\ 
 
 Turn power on.
 


\ **onstandby**\ 
 
 Turn power on to standby state
 


\ **-T**\ 
 
 The value could be \ **lpar**\  or \ **fnm**\ . The tooltype value \ **lpar**\  is for xCAT and \ **fnm**\  is for CNM. The default value is "\ **lpar**\ ". For cold start in the large cluster, it will save a lot of time if the admins use "\ **rpower**\  \ *noderange*\  \ **onstandby**\  \ **-T**\  \ **fnm**\ " to power on all the CECs from the management node through the \ **fnm**\  connections.
 


\ **rackstandby**\ 
 
 Places the rack in the rack standby state. It requires that all CECs and DE be powered off before it will run.
 


\ **exit_rackstandby**\ 
 
 Exit Rack standby will be the default state that a rack goes into when power is initially applied to the rack. It simply moves the BPA from Rack standby to both bpa's in standby state.
 


\ **resetsp**\ 
 
 Reboot the service processor. If there are primary and secondary FSPs/BPAs of one cec/frame, it will reboot them almost at the sametime.
 


\ **softoff**\ 
 
 Attempt to request clean shutdown of OS (may not detect failures in completing command)
 


\ **off**\ 
 
 Turn power off.
 


\ **suspend**\ 
 
 Suspend the target nodes execution.
 
 The \ **suspend**\  action could be run together with \ **-w**\  \ **-o**\  \ **-r**\ .
 
 Refer to the following steps to enable the \ **suspend**\  function:
 
 1. Add the 'acpid' and 'suspend'(the suspend package is not needed on RHEL) package to the .pkglist of your osimage so that the required package could be installed correctly to your target system.
 
 2. Add two configuration files for the base function:
 
 
 .. code-block:: perl
 
   /etc/pm/config.d/suspend
       S2RAM_OPTS="--force --vbe_save --vbe_post --vbe_mode"
  
   /etc/acpi/events/suspend_event
       event=button/sleep.*
       action=/usr/sbin/pm-suspend
 
 
 3. Add the hook files for your specific applications which need specific action before or after the suspend action.
 
 Refer to the 'pm-utils' package for how to create the specific hook files.
 


\ **wake**\ 
 
 Wake up the target nodes which is in \ **suspend**\  state.
 
 Don't try to run \ **wake**\  against the 'on' state node, it would cause the node gets to 'off' state.
 
 For some of xCAT hardware such as NeXtScale, it may need to enable S3 before using \ **wake**\ . The following steps can be used to enable S3. Reference pasu(1)|pasu.1 for "pasu" usage.
 
 
 .. code-block:: perl
 
   [root@xcatmn home]# echo "set Power.S3Enable Enable" > power-setting
   [root@xcatmn home]# pasu -b power-setting node01
   node01: Batch mode start.
   node01: [set Power.S3Enable Enable]
   node01: Power.S3Enable=Enable
   node01:
   node01: Beginning intermediate batch update.
   node01: Waiting for command completion status.
   node01: Command completed successfully.
   node01: Completed intermediate batch update.
   node01: Batch mode completed successfully.
  
   [root@xcatmn home]# pasu node01 show all|grep -i s3
   node01: IMM.Community_HostIPAddress3.1=
   node01: IMM.Community_HostIPAddress3.2=
   node01: IMM.Community_HostIPAddress3.3=
   node01: IMM.DNS_IP_Address3=0.0.0.0
   node01: IMM.IPv6DNS_IP_Address3=::
   node01: Power.S3Enable=Enable
 
 


\ **stat | state**\ 
 
 Print the current power state/status.
 


\ **reset**\ 
 
 Send a hard reset.
 


\ **boot**\ 
 
 If off, then power on.
 If on, then hard reset.
 This option is recommended over \ **cycle**\ .
 


\ **cycle**\ 
 
 Power off, then on.
 


\ **of**\ 
 
 Boot the node to open firmware console mode.
 


\ **sms**\ 
 
 Boot the node to open firmware SMS menu mode.
 


\ **-m**\  \ *table.column*\ ==\ *expectedstatus*\  \ **-m**\  \ *table.column*\ =~\ *expectedstatus*\ 
 
 Use one or multiple \ **-m**\  flags to specify the node attributes and the expected status for the node installation monitoring and automatic retry mechanism. The operators ==, !=, =~ and !~ are valid. This flag must be used with -t flag.
 
 Note: if the "val" fields includes spaces or any other characters that will be parsed by shell, the "attr<oper-ator>val" needs to be quoted. If the operator is "!~", the "attr<operator>val" needs to be quoted using single quote.
 


\ **-**\ **-nodeps**\ 
 
 Do not use dependency table (default is to use dependency table). Valid only with \ **on|off|boot|reset|cycle**\  for blade power method and \ **on|off|reset|softoff**\  for hmc/fsp power method.
 


\ **-r**\  \ *retrycount*\ 
 
 specify the number of retries that the monitoring process will perform before declare the failure. The default value is 3. Setting the retrycount to 0 means only monitoring the os installation progress and will not re-initiate the installation if the node status has not been changed to the expected value after timeout. This flag must be used with -m flag.
 


\ **-t**\  \ *timeout*\ 
 
 Specify the the timeout, in minutes, to wait for the expectedstatus specified by -m flag. This is a required flag if the -m flag is specified.
 
 Power off, then on.
 


\ **-w**\  \ *timeout*\ 
 
 To set the \ *timeout*\  for the \ **suspend**\  action to wait for the success.
 


\ **-o**\ 
 
 To specify that the target node will be power down if \ **suspend**\  action failed.
 


\ **-r**\ 
 
 To specify that the target node will be reset if \ **suspend**\  action failed.
 


\ **start**\ 
 
 To start a created docker instance.
 


\ **stop**\ 
 
 To stop a created docker instance.
 


\ **restart**\ 
 
 To restart a created docker instance.
 


\ **pause**\ 
 
 To pause all processes in the instance.
 


\ **unpause**\ 
 
 To unpause all processes in the instance.
 


\ **state**\ 
 
 To get state of the instance.
 


\ **-h | -**\ **-help**\ 
 
 Prints out a brief usage message.
 


\ **-v | -**\ **-version**\ 
 
 Display the version number.
 



********
EXAMPLES
********



1. To display power status of nodes4 and note5
 
 
 .. code-block:: perl
 
   rpower node4,node5 stat
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   node4: on
   node5: off
 
 


2. To power on node5
 
 
 .. code-block:: perl
 
   rpower node5 on
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   node5: on
 
 



********
SEE ALSO
********


noderange(3)|noderange.3, rcons(1)|rcons.1, rinv(1)|rinv.1, rvitals(1)|rvitals.1, rscan(1)|rscan.1

