
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


\ **rinstall**\  \ *noderange*\  \ **boot**\  | \ **shell**\  | \ **runcmd=bmcsetup**\  [\ **-c | -**\ **-console**\ ] [\ **-V | -**\ **-verbose**\ ]

\ **rinstall**\  \ *noderange*\  \ **osimage**\ =\ *imagename*\  | [\ **-O**\ ] \ *imagename*\  [\ **-**\ **-ignorekernelchk**\ ] [\ **-c | -**\ **-console**\ ] [\ **-u | -**\ **-uefimode**\ ] [\ **-V | -**\ **-verbose**\ ]

\ **rinstall**\  [\ **-h | -**\ **-help | -v | -**\ **-version**\ ]


*******************
\ **Description**\ 
*******************


\ **winstall**\  is a convenience command to begin OS provision on a noderange(support nodes with "nodetype.mgt=ipmi,blade,hmc,ivm,fsp,kvm,esx,rhevm").

If \ **osimage**\ =\ *imagename*\  | \ **-O**\  \ *imagename*\  is specified or nodetype.provmethod=\ **osimage**\  is set, provision the noderange with the osimage specified/configured.

It  will then run wcons on the nodes.


***************
\ **Options**\ 
***************



\ **boot**\ 
 
 Instruct network boot loader to be skipped, generally meaning boot to hard disk
 


\ **osimage | osimage=**\ \ *imagename*\ |\ **-O**\ \ *imagename*\ 
 
 Prepare server for installing a node using the specified os image. The os image is defined in the \ *osimage*\  table and \ *linuximage*\  table. If the <imagename> is omitted, the os image name will be obtained from \ *nodetype.provmethod*\  for the node.
 


\ **-**\ **-ignorekernelchk**\ 
 
 Skip the kernel version checking when injecting drivers from osimage.driverupdatesrc. That means all drivers from osimage.driverupdatesrc will be injected to initrd for the specific target kernel.
 


\ **runimage**\ =\ *task*\ 
 
 If you would like to run a task after deployment, you can define that task with this attribute.
 


\ **runcmd=bmcsetup**\ 
 
 This instructs the node to boot to the xCAT nbfs environment and proceed to configure BMC
 for basic remote access.  This causes the IP, netmask, gateway, username, and password to be programmed according to the configuration table.
 


\ **shell**\ 
 
 This instructs tho node to boot to the xCAT genesis environment, and present a shell prompt on console.
 The node will also be able to be sshed into and have utilities such as wget, tftp, scp, nfs, and cifs.  It will have storage drivers available for many common systems.
 


\ **-h | -**\ **-help**\ 
 
 Display usage message.
 


\ **-v | -**\ **-version**\ 
 
 Display version.
 


\ **-u | -**\ **-uefimode**\ 
 
 For BMC-based servers, to specify the next boot mode to be "UEFI Mode".
 


\ **-V | -**\ **-Verbose**\ 
 
 Verbose output.
 


\ **-c | -**\ **-console**\ 
 
 Requests that rinstall runs rcons once the provision starts.  This will only work if there is only one node in the noderange. See winstall(8)|winstall.8 for starting consoles on multiple nodes.
 



****************
\ **Examples**\ 
****************



1. Provison nodes 1 through 20, using their current configuration.
 
 
 .. code-block:: perl
 
   winstall node1-node20
 
 


2. Provision nodes 1 through 20 with the osimage rhels6.4-ppc64-netboot-compute.
 
 
 .. code-block:: perl
 
   winstall node1-node20 -O rhels6.4-ppc64-netboot-compute
 
 



************************
\ **See**\  \ **Also**\ 
************************


noderange(3)|noderange.3, rinstall(8)|rinstall.8, wcons(1)|wcons.1

