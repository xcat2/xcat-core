
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

\ **packimage**\  [\ **-m | -**\ **-method**\  \ *cpio|tar*\ ] [\ **-c | -**\ **-compress**\  \ *gzip|pigz|xz*\ ]  \ *imagename*\ 


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

\ **-m| -**\ **-method**\           Archive Method (cpio,tar,squashfs, default is cpio)

\ **-c| -**\ **-compress**\           Compress Method (pigz,gzip,xz, default is pigz/gzip)


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


2. To pack the osimage rhels7.1-x86_64-netboot-compute with "tar" to archive and "pigz" to compress:


.. code-block:: perl

  packimage -m tar -c pigz rhels7.1-x86_64-netboot-compute



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

