
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

This command will ignore the current osimage.kitcomponents setting and check if the kitcompname_list is compatible with the osimage and kit component dependencies.

\ **Note:**\  xCAT Kit support is ONLY available for Linux operating systems.


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
 
 The name of the osimage to check against.
 


\ *kitcompname_list*\ 
 
 A comma-delimited list of valid full kit component names or kit component basenames that are to be checked against the osimage.
 



************
RETURN VALUE
************


0  The command completed successfully.

1  An error has occurred.


********
EXAMPLES
********


1. To check if a kit component, \ *comp-test1-1.0-1-rhels-6.2-ppc64*\  can be added to osimage \ *rhels6.2-ppc64-netboot-compute*\ :


.. code-block:: perl

    chkkitcomp -i rhels6.2-ppc64-netboot-compute comp-test1-1.0-1-rhels-6.2-ppc64



********
SEE ALSO
********


lskit(1)|lskit.1, addkit(1)|addkit.1, rmkit(1)|rmkit.1, addkitcomp(1)|addkitcomp.1, rmkitcomp(1)|rmkitcomp.1

