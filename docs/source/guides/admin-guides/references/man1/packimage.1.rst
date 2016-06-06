
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


\ *packimage [-h| --help]*\ 

\ *packimage  [-v| --version]*\ 

\ *packimage [-o OS] [ -p profile] [-a architecture] [-m method]*\ 

\ *packimage imagename*\ 


***********
DESCRIPTION
***********


Packs the stateless image from the chroot file system into a file system to be
sent to the node for a diskless install.
The install dir is setup by using "installdir" attribute set in the site table.
The nodetype table "profile" attribute for the node should reflect the profile of the install image.

If no \ *imagename*\  is specified, this command uses the os image definition files from /install/custom/netboot/[os] directory first. If not found, it falls back to the default directory  /opt/xcat/share/xcat/netboot/[os]. 
If a \ *imagename*\  is specified, this command will get all the necessary os image definition files from the \ *osimage*\  and \ *linuximage*\  tables.


**********
Parameters
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


1. To pack a fedora8 image for a compute node architecture x86_64 and place it in the  /install/netboot/fedora8/x86_64/compute/rootimg.gz file enter:

\ *packimage  -o fedora8 -p compute -a x86_64*\ 

This would use the package information from the /install/custom/netboot/fedora/compute\* files first. If not found it uses /opt/xcat/share/xcat/netboot/fedora/compute\* files.


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

