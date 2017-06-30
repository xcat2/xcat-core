
##########
winstall.8
##########

.. highlight:: perl


****
Name
****


\ **winstall**\  - Begin OS provision on a noderange


****************
\ **Synopsis**\ 
****************


\ **winstall**\  \ *noderange*\  [\ **boot**\  | \ **shell**\  | \ **runcmd=bmcsetup**\ ] [\ **runimage=**\ \ *task*\ ] [\ **-V | -**\ **-verbose**\ ]

\ **winstall**\  \ *noderange*\  [\ **osimage**\ =\ *imagename*\  | \ *imagename*\ ] [\ **-**\ **-ignorekernelchk**\ ] [\ **-u | -**\ **-uefimode**\ ] [\ **-V | -**\ **-verbose**\ ]

\ **winstall**\  [\ **-h | -**\ **-help | -v | -**\ **-version**\ ]


*******************
\ **Description**\ 
*******************


\ **winstall**\  is a convenience command to begin OS provision on a noderange.

If \ **osimage**\ =\ *imagename*\  | \ *imagename*\  is specified or nodetype.provmethod=\ **osimage**\  is set, provision the noderange with the osimage specified/configured.

It  will then run \ **wcons**\  on the noderange.


***************
\ **Options**\ 
***************



\ **boot**\ 
 
 Instruct network boot loader to be skipped, generally meaning boot to hard disk
 


\ *imagename*\  | \ **osimage=**\ \ *imagename*\ 
 
 Prepare server for installing a node using the specified os image. The os image is defined in the \ *osimage*\  table and \ *linuximage*\  table. If the \ *imagename*\  is omitted, the os image name will be obtained from \ *nodetype.provmethod*\  for the node.
 


\ **-**\ **-ignorekernelchk**\ 
 
 Skip the kernel version checking when injecting drivers from osimage.driverupdatesrc. That means all drivers from osimage.driverupdatesrc will be injected to initrd for the specific target kernel.
 


\ **runimage=**\ \ *task*\ 
 
 If you would like to run a task after deployment, you can define that task with this attribute.
 


\ **runcmd=bmcsetup**\ 
 
 This instructs the node to boot to the xCAT nbfs environment and proceed to configure BMC for basic remote access.  This causes the IP, netmask, gateway, username, and password to be programmed according to the configuration table.
 


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
 



****************
\ **Examples**\ 
****************



1. Provision nodes 1 through 20, using their current configuration.
 
 
 .. code-block:: perl
 
   winstall node1-node20
 
 


2. Provision nodes 1 through 20 with the osimage rhels6.4-ppc64-netboot-compute.
 
 
 .. code-block:: perl
 
   winstall node1-node20 osimage=rhels6.4-ppc64-netboot-compute
 
 



************************
\ **See**\  \ **Also**\ 
************************


noderange(3)|noderange.3, rinstall(8)|rinstall.8, wcons(1)|wcons.1

