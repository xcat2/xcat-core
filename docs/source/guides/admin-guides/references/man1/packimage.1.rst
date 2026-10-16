
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

\ **packimage**\  [\ **-m | -**\ **-method**\  \ **cpio|tar|squashfs**\ ] [\ **-c | -**\ **-compress**\  \ **gzip|pigz|xz**\ ] [\ **-**\ **-nosyncfiles**\ ] \ *imagename*\ 


***********
DESCRIPTION
***********


Packs the stateless image from the chroot file system into a file to be sent to the node for a diskless boot.

Note: \ **packimage**\  writes the new file next to the existing one and replaces it only when the new file is complete. Compute nodes can download the existing file while \ **packimage**\  runs, and the existing file stays if \ **packimage**\  fails. The image directory needs space for both files while \ **packimage**\  runs.

\ **packimage**\  also writes the SHA-256 checksum of the file to a file with the same name and the suffix \ *.sha256*\ . When the \ *rootimgchecksum*\  attribute of the osimage or of the site table is \ *yes*\ , the default, \ **nodeset**\  tells the compute nodes to check the downloaded file against this checksum. When the check fails, for example because the checksum file is missing, the node downloads the file again. To turn the check off, set the attribute to \ *no*\ , then run \ **nodeset**\  again. The first upgrade to a release with the check sets the attribute of the osimage to \ *no*\  for the images that exist then. \ **packimage**\  writes the checksum also when the check is off. \ **nodeset**\  warns when the check is on but cannot tell whether the initial ramdisk of the image checks the file. Run \ **genimage**\  to rebuild such an initial ramdisk. For a file that \ **packimage**\  wrote before this release, \ **genimage**\  and \ **nodeset**\  write the checksum.


**********
PARAMETERS
**********


\ *imagename*\  specifies the name of a OS image definition to be used. The specification for the image is stored in the \ *osimage*\  table and \ *linuximage*\  table.


*******
OPTIONS
*******



\ **-h**\ 
 
 Display usage message.
 


\ **-v**\ 
 
 Command Version.
 


\ **-m| -**\ **-method**\ 
 
 Archive Method (cpio, tar, squashfs (requires overlayFS or aufs modules during provisioning), default is cpio)
 


\ **-c| -**\ **-compress**\ 
 
 Compress Method (pigz, gzip, xz, default is pigz/gzip)
 


\ **-**\ **-nosyncfiles**\ 
 
 Bypass of syncfiles requested, will not sync files to root image directory
 



************
RETURN VALUE
************


0 The command completed successfully.

1 An error has occurred.


********
EXAMPLES
********


1. To pack the osimage 'rhels7.1-x86_64-netboot-compute':


.. code-block:: perl

  packimage rhels7.1-x86_64-netboot-compute


2. To pack the osimage 'rhels7.1-x86_64-netboot-compute' with "tar" to archive and "pigz" to compress:


.. code-block:: perl

  packimage -m tar -c pigz rhels7.1-x86_64-netboot-compute


3. To pack the osimage 'rhels7.1-x86_64-netboot-compute' without syncing files:


.. code-block:: perl

  packimage --nosyncfiles rhels7.1-x86_64-netboot-compute



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

