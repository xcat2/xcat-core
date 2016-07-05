
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


The \ **mknb**\  command is run by xCAT automatically when xCAT is installed on the management node.
It creates a network boot root image (used for node discovery, BMC programming, and flashing)
for the same architecture that the management node is.  So you normally do not need to run the 
\ **mknb**\  command yourself.

If you make custom changes to the network boot root image, you will need to run \ **mknb**\  again to regenerate the diskless image to include your changes.  If you have an xCAT Hierarchical Cluster with Service Nodes having local /tftpboot directories (site.sharedtftp=0), you will need to copy the generated root image to each Service Node.

Presently, the architectures x86_64 and ppc64 are supported. For ppc64le, use the ppc64 architecture.


*******
OPTIONS
*******



\ *arch*\ 
 
 The hardware architecture for which to build the boot image.
 



************
RETURN VALUE
************



0.  The command completed successfully.



1.  An error has occurred.




********
SEE ALSO
********


makedhcp(8)|makedhcp.8

