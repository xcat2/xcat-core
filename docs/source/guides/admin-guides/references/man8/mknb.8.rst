
######
mknb.8
######

.. highlight:: perl


****
NAME
****


\ **mknb**\  - creates a network boot root image for node discovery and flashing


********
SYNOPSIS
********


\ **mknb**\  \ *arch*\ 


***********
DESCRIPTION
***********


The \ **mknb**\  command is run by xCAT automatically, when xCAT is installed on the management node.
It creates a network boot root image (used for node discovery, BMC programming, and flashing)
for the same architecture that the management node is.  So you normally do not need to run the \ **mknb**\ 
command yourself.

If you do run \ **mknb**\  to add custom utilities to your boot root image, and you have an xCAT Hierarchical Cluster with service nodes that each have a local /tftpboot directory (site sharedtftp=0), you will also need to copy the generated root image to each service node.

Presently, only the arch x86_64 is supported.


*******
OPTIONS
*******



\ *arch*\ 
 
 The hardware architecture for which to build the boot image: x86_64
 



************
RETURN VALUE
************



0.  The command completed successfully.



1.  An error has occurred.




********
SEE ALSO
********


makedhcp(8)|makedhcp.8

