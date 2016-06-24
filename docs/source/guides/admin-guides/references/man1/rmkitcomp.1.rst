
###########
rmkitcomp.1
###########

.. highlight:: perl


****
NAME
****


\ **rmkitcomp**\  - Remove Kit components from an xCAT osimage.


********
SYNOPSIS
********


\ **rmkitcomp**\  [\ **-? | -h | -**\ **-help**\ ] [\ **-v | -**\ **-version**\ ]

\ **rmkitcomp**\  [\ **-V | -**\ **-verbose**\ ] [\ **-u | -**\ **-uninstall**\ ] [\ **-f | -**\ **-force**\ ] [\ **-**\ **-noscripts**\ ] \ **-i**\  \ *osimage*\   \ *kitcompname_list*\ 


***********
DESCRIPTION
***********


The \ **rmkitcomp**\  command removes kit components from an xCAT osimage.  All the kit component attribute values that are contained in the osimage will be removed, and the kit comoponent meta rpm and package rpm could be uninstalled by \ **-u|-**\ **-uninstall**\  option.

Note: The xCAT support for Kits is only available for Linux operating systems.


*******
OPTIONS
*******



\ **-u|-**\ **-uninstall**\ 
 
 All the kit component meta rpms and package rpms in otherpkglist will be uninstalled during genimage for stateless image and updatenode for stateful nodes.
 


\ **-h|-**\ **-help**\ 
 
 Display usage message.
 


\ **-V|-**\ **-verbose**\ 
 
 Verbose mode.
 


\ **-v|-**\ **-version**\ 
 
 Command version.
 


\ **-f|-**\ **-force**\ 
 
 Remove this kit component from osimage no matter it is a dependency of other kit components.
 


\ **-**\ **-noscripts**\ 
 
 Do not remove kitcomponent's postbootscripts from osimage
 


\ **-i**\  \ *osimage*\ 
 
 osimage name that include this kit component.
 


\ *kitcompname_list*\ 
 
 A comma-delimited list of valid full kit component names or kit component basenames that are to be removed from the osimage. If a basename is specified, all kitcomponents matching that basename will be removed from the osimage.
 



************
RETURN VALUE
************


0  The command completed successfully.

1  An error has occurred.


********
EXAMPLES
********


1. To remove a kit component from osimage


.. code-block:: perl

  rmkitcomp -i rhels6.2-ppc64-netboot-compute comp-test1-1.0-1-rhels-6.2-ppc64


Output is similar to:


.. code-block:: perl

  kitcomponents comp-test1-1.0-1-rhels-6.2-ppc64 were removed from osimage rhels6.2-ppc64-netboot-compute successfully


2. To remove a kit component even it is still used as a dependency of other kit component.


.. code-block:: perl

  rmkitcomp -f -i rhels6.2-ppc64-netboot-compute comp-test1-1.0-1-rhels-6.2-ppc64


Output is similar to:


.. code-block:: perl

  kitcomponents comp-test1-1.0-1-rhels-6.2-ppc64 were removed from osimage rhels6.2-ppc64-netboot-compute successfully


3. To remove a kit component from osimage and also remove the kit component meta RPM and package RPM.  So in next genimage for statelss image and updatenode for stateful nodes, the kit component meta RPM and package RPM will be uninstalled.


.. code-block:: perl

  rmkitcomp -u -i rhels6.2-ppc64-netboot-compute comp-test1-1.0-1-rhels-6.2-ppc64


Output is similar to:


.. code-block:: perl

  kitcomponents comp-test1-1.0-1-rhels-6.2-ppc64 were removed from osimage rhels6.2-ppc64-netboot-compute successfully



********
SEE ALSO
********


lskit(1)|lskit.1, addkit(1)|addkit.1, rmkit(1)|rmkit.1, addkitcomp(1)|addkitcomp.1, chkkitcomp(1)|chkkitcomp.1

