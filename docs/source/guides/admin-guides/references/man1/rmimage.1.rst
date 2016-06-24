
#########
rmimage.1
#########

.. highlight:: perl


****
NAME
****


\ **rmimage**\  - Removes the Linux stateless or statelite image from the file system.


********
SYNOPSIS
********


\ **rmimage [-h | -**\ **-help]**\ 

\ **rmimage [-V | -**\ **-verbose]**\  \ *imagename*\  \ **[-**\ **-xcatdef]**\ 


***********
DESCRIPTION
***********


Removes the Linux stateless or statelite image from the file system.
The install dir is setup by using "installdir" attribute set in the site table.

If \ *imagename*\  is specified, this command uses the information in the \ *imagename*\ 
to calculate the image root directory; otherwise, this command uses the operating system name,
architecture and profile name to calculate the image root directory.

The osimage definition will not be removed from the xCAT tables by default,
specifying the flag \ **-**\ **-xcatdef**\  will remove the osimage definition,
or you can use rmdef -t osimage to remove the osimage definition.

The statelite image files on the diskful service nodes will not be removed,
remove the image files on the service nodes manually if necessary, 
for example, use command "rsync -az --delete /install <sn>:/" to remove the image files on the service nodes,
where the <sn> is the hostname of the service node.


**********
Parameters
**********


\ *imagename*\  specifies the name of an os image definition to be used. The specification for the image is stored in the \ *osimage*\  table and \ *linuximage*\  table.


*******
OPTIONS
*******


\ **-h | -**\ **-help**\      Display usage message.

\ **-V | -**\ **-verbose**\   Verbose mode.

\ **-**\ **-xcatdef**\        Remove the xCAT osimage definition


************
RETURN VALUE
************


0 The command completed successfully.

1 An error has occurred.


********
EXAMPLES
********


1. To remove a RHEL 7.1 stateless image for a compute node architecture x86_64, enter:


.. code-block:: perl

  rmimage rhels7.1-x86_64-netboot-compute


2. To remove a rhels5.5 statelite image for a compute node architecture ppc64 and the osimage definition, enter:


.. code-block:: perl

  rmimage rhels5.5-ppc64-statelite-compute --xcatdef



*****
FILES
*****


/opt/xcat/sbin/rmimage


*****
NOTES
*****


This command is part of the xCAT software product.


********
SEE ALSO
********


genimage(1)|genimage.1, packimage(1)|packimage.1

