
#########
nodeset.8
#########

.. highlight:: perl


****
Name
****


\ **nodeset**\  - set the boot state for a noderange


****************
\ **Synopsis**\ 
****************


\ **nodeset**\  \ *noderange*\  [\ **boot**\  | \ **stat**\  | \ **offline**\  | \ **runcmd=bmcsetup**\  | \ **osimage**\ [=\ *imagename*\ ] | \ **shell**\  | \ **shutdown**\ ]

\ **nodeset**\  \ *noderange*\  \ **osimage**\ [=\ *imagename*\ ] [\ **-**\ **-noupdateinitrd**\ ] [\ **-**\ **-ignorekernelchk**\ ]

\ **nodeset**\  \ *noderange*\  \ **runimage=**\ \ *task*\ 

\ **nodeset**\  [\ **-h | -**\ **-help | -v | -**\ **-version**\ ]


*******************
\ **Description**\ 
*******************


\ **nodeset**\   sets the next boot state for a single or range of
nodes or groups.  It tells xCAT what you want to happen the next time the
nodes are booted up.  See  noderange(3)|noderange.3.   \ **nodeset**\   accomplishes  this  by
changing  the network boot files.  Each xCAT node always boots from the
network and downloads a boot file with instructions on what  action  to
take next.

\ **nodeset**\  will manipulate the boot configuration files of yaboot and pxelinux.0.

Assume that /tftpboot is the root for tftpd (set in site(5)|site.5).

\ **nodeset**\  for pxe makes changes to /tftpboot/pxelinux.cfg/{node hex ip}

\ **nodeset**\  for yaboot makes changes to /tftpboot/etc/{node hex ip}

\ **nodeset**\  only sets the next boot state, but does not reboot.

\ **nodeset**\   is  called  by \ **rinstall**\  and \ **winstall**\  and is also called by the
installation process remotely to set the boot state back to "boot".

A user can supply their own scripts to be run on the mn or on the service node (if a hierarchical cluster) for a node when the nodeset command is run. Such scripts are called \ **prescripts**\ . They should be copied to /install/prescripts dirctory. A table called \ *prescripts*\  is used to specify the scripts and their associated actions. The scripts to be run at the beginning of the nodeset command are stored in the 'begin' column of \ *prescripts*\  table. The scripts to be run at the end of the nodeset command are stored in the 'end' column of \ *prescripts*\  table. You can run 'tabdump -d prescripts' command for details. The following two environment variables will be passed to each script: NODES contains all the names of the nodes that need to run the script for and ACTION contains the current nodeset action. If \ *#xCAT setting:MAX_INSTANCE=number*\  is specified in the script, the script will get invoked for each node in parallel, but no more than \ *number*\  of instances will be invoked at at a time. If it is not specified, the script will be invoked once for all the nodes.


***************
\ **Options**\ 
***************



\ **boot**\ 
 
 Instruct network boot loader to be skipped, generally meaning boot to hard disk
 


\ **offline**\ 
 
 Cleanup the current pxe/tftp boot configuration files for the nodes requested
 


\ **osimage | osimage=**\ \ *imagename*\ 
 
 Prepare server for installing a node using the specified os image. The os image is defined in the \ *osimage*\  table and \ *linuximage*\  table. If the <imagename> is omitted, the os image name will be obtained from \ *nodetype.provmethod*\  for the node.
 


\ **-**\ **-noupdateinitrd**\ 
 
 Skip the rebuilding of initrd when the 'netdrivers', 'drvierupdatesrc' or 'osupdatename' were set for injecting new drivers to initrd. But, the \ **geninitrd**\  command
 should be run to rebuild the initrd for new drivers injecting. This is used to improve the performance of \ **nodeset**\  command.
 


\ **-**\ **-ignorekernelchk**\ 
 
 Skip the kernel version checking when injecting drivers from osimage.driverupdatesrc. That means all drivers from osimage.driverupdatesrc will be injected to initrd for the specific target kernel.
 


\ **runimage**\ =\ *task*\ 
 
 If you would like to run a task after deployment, you can define that task with this attribute.
 


\ **stat**\ 
 
 Display the current boot loader config file description for the nodes requested
 


\ **runcmd=bmcsetup**\ 
 
 This instructs the node to boot to the xCAT nbfs environment and proceed to configure BMC
 for basic remote access.  This causes the IP, netmask, gateway, username, and password to be programmed according to the configuration table.
 


\ **shell**\ 
 
 This instructs tho node to boot to the xCAT genesis environment, and present a shell prompt on console.
 The node will also be able to be sshed into and have utilities such as wget, tftp, scp, nfs, and cifs.  It will have storage drivers available for many common systems.
 


\ **shutdown**\ 
 
 To make the node to get into power off status. This status only can be used after \ **runcmd**\  and \ **runimage**\  to power off the node after the performing of operations.
 


\ **-h | -**\ **-help**\ 
 
 Print help.
 


\ **-v | -**\ **-version**\ 
 
 Print version.
 



*************
\ **Files**\ 
*************


\ **noderes**\  table -
xCAT  node  resources  file.   See  noderes(5)|noderes.5  for  further
details.

\ **nodetype**\  table -
xCAT node installation type file.  See nodetype(5)|nodetype.5 for  fur-
ther  details.   This is used to determine the node installation
image type.

\ **site**\  table -
xCAT main  configuration  file.   See  site(5)|site.5  for  further
details.   This  is  used  to determine the location of the TFTP
root directory and the TFTP xCAT  subdirectory.   /tftpboot  and
/tftpboot/xcat is the default.


****************
\ **Examples**\ 
****************



1. To setup to install mycomputeimage on the compute node group.
 
 
 .. code-block:: perl
 
   nodeset compute osimage=mycomputeimage
 
 


2. To run http://$master/image.tgz  after deployment:
 
 
 .. code-block:: perl
 
   nodeset $node runimage=http://$MASTER/image.tgz
 
 



************************
\ **See**\  \ **Also**\ 
************************


noderange(3)|noderange.3, nodels(1)|nodels.1, nodestat(1)|nodestat.1, rinstall(8)|rinstall.8,
makedhcp(8)|makedhcp.8, osimage(7)|osimage.7

