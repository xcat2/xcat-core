
##########
rsetboot.1
##########

.. highlight:: perl


********
SYNOPSIS
********


\ **rsetboot**\  \ *noderange*\  [\ **hd | net | cd | default | stat**\ ] [\ **-u**\ ] [\ **-p**\ ]

\ **rsetboot**\  [\ **-h | -**\ **-help | -v | -**\ **-version**\ ]


***********
DESCRIPTION
***********


\ **rsetboot**\  sets the boot media and boot mode that should be used on the next boot of the specified nodes.  After the nodes are booted with the specified device and boot mode (e.g. via rpower(1)|rpower.1), the nodes will return to using the default boot device specified in the BIOS.


*******
OPTIONS
*******



\ **hd**\ 
 
 Boot from the hard disk.
 


\ **net**\ 
 
 Boot over the network, using a PXE or BOOTP broadcast.
 


\ **cd**\ 
 
 Boot from the CD or DVD drive.
 


\ **def | default**\ 
 
 Boot using the default set in BIOS.
 


\ **stat**\ 
 
 Display the current boot setting.
 


\ **-u**\ 
 
 To specify the next boot mode to be "UEFI Mode".
 


\ **-p**\ 
 
 To make the specified boot device and boot mode settings persistent.
 



********
EXAMPLES
********



1.
 
 Set nodes 1 and 3 to boot from the network on the next boot:
 
 
 .. code-block:: perl
 
   rsetboot node1,node3 net
 
 


2.
 
 Display the next-boot value for nodes 14-56 and 70-203:
 
 
 .. code-block:: perl
 
   rsetboot node[14-56],node[70-203] stat
 
 
 Or:
 
 
 .. code-block:: perl
 
   rsetboot node[14-56],node[70-203]
 
 


3.
 
 Restore the next-boot value for these nodes back to their default set in the BIOS:
 
 
 .. code-block:: perl
 
   rsetboot node1,node3,node[14-56],node[70-203] default
 
 



********
SEE ALSO
********


rbootseq(1)|rbootseq.1

