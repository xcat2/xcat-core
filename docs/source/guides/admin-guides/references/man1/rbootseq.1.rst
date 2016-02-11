
##########
rbootseq.1
##########

.. highlight:: perl


********
SYNOPSIS
********


\ **rbootseq**\  [\ **-h | -**\ **-help | -v | -**\ **-version**\ ]

Blade specific:
===============


\ **rbootseq**\  \ *noderange*\  {\ **hd0 | hd1 | hd2 | hd3 | net | iscsi | iscsicrit | cdrom | usbflash | floppy | none | list | stat**\ }\ **,**\ \ *...*\ 


HP Blade specific:
==================


\ **rbootseq**\  \ *noderange*\  {\ **hd | net1 | net2 | net3 | net4 | cdrom | usbflash | floppy | none**\ }\ **,**\ \ *...*\ 


PPC (using Direct FSP Management) specific:
===========================================


\ **rbootseq**\  \ *noderange*\  \ **[hfi|net]**\ 



***********
DESCRIPTION
***********


For Blade specific:

\ **rbootseq**\  sets the boot sequence (the order in which boot devices should be tried) for the specified blades.
Up to four different medium/devices can be listed, separated by commas.  The boot sequence will remain
in effect for these blades until set differently.

For PPC (using Direct FSP Management) specific:

\ **rbootseq**\  sets the ethernet (net) or hfi device as the first boot device for the specified PPC LPARs.
The \ **rbootseq**\  command requires that the ethernet or hfi mac address is stored in the mac table, and that the network information is correct in the networks table.


*******
OPTIONS
*******



\ **hd0 | harddisk0 | hd | harddisk**\ 
 
 The first hard disk.
 


\ **hd1 | harddisk1**\ 
 
 The second hard disk.
 


\ **hd2 | harddisk2**\ 
 
 The third hard disk.
 


\ **hd3 | harddisk3**\ 
 
 The fourth hard disk.
 


\ **n | net | network**\ 
 
 Boot over the ethernet network, using a PXE or BOOTP broadcast.
 


\ **n | net | network | net1 | nic1**\  (HP Blade Only)
 
 Boot over the first ethernet network, using a PXE or BOOTP broadcast.
 


\ **net2 | nic2**\  (HP Blade Only)
 
 Boot over the second ethernet network, using a PXE or BOOTP broadcast.
 


\ **net3 | nic3**\  (HP Blade Only)
 
 Boot over the third ethernet network, using a PXE or BOOTP broadcast.
 


\ **net3 | nic3**\  (HP Blade Only)
 
 Boot over the fourth ethernet network, using a PXE or BOOTP broadcast.
 


\ **hfi**\ 
 
 Boot p775 nodes over the HFI network, using BOOTP broadcast.
 


\ **iscsi**\ 
 
 Boot to an iSCSI disk over the network.
 


\ **iscsicrit**\ 
 
 ??
 


\ **cd | cdrom**\ 
 
 The CD or DVD drive.
 


\ **usbflash | usb | flash**\ 
 
 A USB flash drive.
 


\ **floppy**\ 
 
 The floppy drive.
 


\ **none**\ 
 
 If it gets to this part of the sequence, do not boot.  Can not be specified 1st, or before any real boot devices.
 


\ **list | stat**\ 
 
 Display the current boot sequence.
 



********
EXAMPLES
********



1.
 
 Set blades 14-56 and 70-203 to try to boot first from the CD drive, then the floppy drive, then
 the network, and finally from the 1st hard disk:
 
 
 .. code-block:: perl
 
   rbootseq blade[14-56],blade[70-203] c,f,n,hd0
 
 



********
SEE ALSO
********


rsetboot(1)|rsetboot.1

