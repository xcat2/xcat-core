
############
chkkitcomp.1
############

.. highlight:: perl


****
NAME
****


\ **chkkitcomp**\  - Check if Kit components are compatible with an xCAT osimage.


********
SYNOPSIS
********


\ **chkkitcomp**\  [\ **-? | -h | -**\ **-help**\ ] [\ **-v | -**\ **-version**\ ]

\ **chkkitcomp**\  [\ **-V | -**\ **-verbose**\ ] \ **-i**\  \ *osimage*\   \ *kitcompname_list*\ 


***********
DESCRIPTION
***********


The \ **chkkitcomp**\  command will check if the kit components are compatible with the xCAT osimage.

This command will ignore the current osimage.kitcomponents setting, and just to check if the kitcompname list in the cmdline are compatible with the osimage by osversion/ostype/osarch/ and kit component dependencies.

Note: The xCAT support for Kits is only available for Linux operating systems.


*******
OPTIONS
*******



\ **-h|-**\ **-help**\ 
 
 Display usage message.
 


\ **-V|-**\ **-verbose**\ 
 
 Verbose mode.
 


\ **-v|-**\ **-version**\ 
 
 Command version.
 


\ **-i**\  \ *osimage*\ 
 
 The name of the osimage is used for check.
 


\ **kitcompname_list**\ 
 
 A comma-delimited list of valid full kit component names or kit component basenames that are to be checking to the osimage.
 



************
RETURN VALUE
************


0  The command completed successfully.

1  An error has occurred.


********
EXAMPLES
********


1. To check if a kit component is fitting to an osimage

chkkitcomp -i rhels6.2-ppc64-netboot-compute comp-test1-1.0-1-rhels-6.2-ppc64

Output is similar to:

Kit components comp-test1-1.0-1-rhels-6.2-ppc64 fit to osimage rhels6.2-ppc64-netboot-compute


********
SEE ALSO
********


lskit(1)|lskit.1, addkit(1)|addkit.1, rmkit(1)|rmkit.1, addkitcomp(1)|addkitcomp.1, rmkitcomp(1)|rmkitcomp.1

