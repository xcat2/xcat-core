
###########
packimage.1
###########

.. highlight:: perl


****
NAME
****


\ **packimage**\  - Packs the stateless image from the chroot file system.


********
SYNOPSIS
********


\ **packimage [-h| -**\ **-help]**\ 

\ **packimage  [-v| -**\ **-version]**\ 

\ **packimage**\  \ *imagename*\ 


***********
DESCRIPTION
***********


Packs the stateless image from the chroot file system into a file system to be
sent to the node for a diskless install.
The install dir is setup by using "installdir" attribute set in the site table.
The nodetype table "profile" attribute for the node should reflect the profile of the install image.

This command will get all the necessary os image definition files from the \ *osimage*\  and \ *linuximage*\  tables.


**********
PARAMETERS
**********


\ *imagename*\  specifies the name of a os image definition to be used. The specification for the image is stored in the \ *osimage*\  table and \ *linuximage*\  table.


*******
OPTIONS
*******


\ **-h**\           Display usage message.

\ **-v**\           Command Version.

\ **-o**\           Operating system (fedora8, rhel5, sles10,etc)

\ **-p**\           Profile (compute,service)

\ **-a**\           Architecture (ppc64,x86_64,etc)

\ **-m**\           Method (default cpio)


************
RETURN VALUE
************


0 The command completed successfully.

1 An error has occurred.


********
EXAMPLES
********


1. To pack the osimage rhels7.1-x86_64-netboot-compute:


.. code-block:: perl

  packimage rhels7.1-x86_64-netboot-compute



*****
FILES
*****


/opt/xcat/sbin/packimage


*****
NOTES
*****


This command is part of the xCAT software product.


********
SEE ALSO
********


genimage(1)|genimage.1

