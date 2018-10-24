
##########
rinstall.8
##########

.. highlight:: perl


****
Name
****


\ **rinstall**\  - Begin OS provision on a noderange


****************
\ **Synopsis**\ 
****************


\ **rinstall**\  \ *noderange*\  [\ **boot**\  | \ **shell**\  | \ **runcmd=**\ \ *command*\ ] [\ **-c | -**\ **-console**\ ] [\ **-V | -**\ **-verbose**\ ]

\ **rinstall**\  \ *noderange*\  [\ **osimage**\ [=\ *imagename*\ ]] [\ **-**\ **-noupdateinitrd**\ ][\ **-**\ **-ignorekernelchk**\ ] [\ **-c | -**\ **-console**\ ] [\ **-u | -**\ **-uefimode**\ ] [\ **-V | -**\ **-verbose**\ ]

\ **rinstall**\  \ *noderange*\  \ **runimage=**\ \ *task*\ 

\ **rinstall**\  [\ **-h | -**\ **-help | -v | -**\ **-version**\ ]


*******************
\ **Description**\ 
*******************


\ **rinstall**\  is a convenience command to begin OS provision on a noderange.

If \ **osimage**\ =\ *imagename*\  is specified or \ **osimage**\  is specified and nodetype.provmethod=\ *osimage*\  is set, provision the noderange with the osimage specified/configured. If no task specified, default is \ **osimage**\ .

If \ **-c**\  is specified, \ **rinstall**\  will run \ **rcons**\  on the node. This is allowed only if one node is in the noderange. If consoles are needed on multiple nodes, see winstall(8)|winstall.8.


***************
\ **Options**\ 
***************



\ **boot**\ 
 
 Instruct network boot loader to be skipped, generally meaning boot to hard disk
 


\ **osimage**\ [=\ *imagename*\ ]
 
 Prepare server for installing a node using the specified OS image. The OS image is defined in the \ *osimage*\  table and \ *linuximage*\  table. If the \ *imagename*\  is omitted, the OS image name will be obtained from \ *nodetype.provmethod*\  for the node.
 


\ **-**\ **-noupdateinitrd**\ 
 
 Skip the rebuilding of initrd when the 'netdrivers', 'driverupdatesrc' or 'osupdatename' were set for injecting new drivers to initrd. But, the \ **geninitrd**\  command should be run to rebuild the initrd for new drivers injecting. This is used to improve the performance of \ **rinstall**\  command.
 


\ **-**\ **-ignorekernelchk**\ 
 
 Skip the kernel version checking when injecting drivers from osimage.driverupdatesrc. That means all drivers from osimage.driverupdatesrc will be injected to initrd for the specific target kernel.
 


\ **runimage=**\ \ *task*\ 
 
 If you would like to run a task after deployment, you can define that task with this attribute.
 


\ **runcmd=**\ \ *command*\ 
 
 This instructs the node to boot to the xCAT genesis environment and specified command to be executed.
 


\ **shell**\ 
 
 This instructs the node to boot to the xCAT genesis environment, and present a shell prompt on console.
 The node will also be able to be sshed into and have utilities such as wget, tftp, scp, nfs, and cifs.  It will have storage drivers available for many common systems.
 


\ **-h | -**\ **-help**\ 
 
 Display usage message.
 


\ **-v | -**\ **-version**\ 
 
 Display version.
 


\ **-u | -**\ **-uefimode**\ 
 
 For BMC-based servers, to specify the next boot mode to be "UEFI Mode".
 


\ **-V | -**\ **-verbose**\ 
 
 Verbose output.
 


\ **-c | -**\ **-console**\ 
 
 Requests that \ **rinstall**\  runs \ **rcons**\  once the provision starts.  This will only work if there is only one node in the noderange. See winstall(8)|winstall.8 for starting consoles on multiple nodes.
 



****************
\ **Examples**\ 
****************



1. Provision nodes 1 through 20, using their current configuration.
 
 
 .. code-block:: perl
 
   rinstall node1-node20
 
 


2. Provision nodes 1 through 20 with the osimage rhels6.4-ppc64-netboot-compute.
 
 
 .. code-block:: perl
 
   rinstall node1-node20 osimage=rhels6.4-ppc64-netboot-compute
 
 


3. Provision node1 and start a console to monitor the process.
 
 
 .. code-block:: perl
 
   rinstall node1 -c
 
 


4. Boot node1 into xCAT genesis environment and execute bmcsetup script. This causes the IP, netmask, gateway, username, and password to be programmed according to the configuration in node object definition.
 
 
 .. code-block:: perl
 
   rinstall node1 runcmd=bmcsetup
 
 



************************
\ **See**\  \ **Also**\ 
************************


noderange(3)|noderange.3, winstall(8)|winstall.8, rcons(1)|rcons.1

