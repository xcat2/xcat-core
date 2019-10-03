
############
addkitcomp.1
############

.. highlight:: perl


****
NAME
****


\ **addkitcomp**\  - Assign Kit components to an xCAT osimage.


********
SYNOPSIS
********


\ **addkitcomp**\  [\ **-? | -h | -**\ **-help**\ ] [\ **-v | -**\ **-version**\ ]

\ **addkitcomp**\  [\ **-V | -**\ **-verbose**\ ] [\ **-a | -**\ **-adddeps**\ ] [\ **-f | -**\ **-force**\ ] [\ **-n | -**\ **-noupgrade**\ ] [\ **-**\ **-noscripts**\ ] \ **-i**\  \ *osimage*\   \ *kitcompname_list*\ 


***********
DESCRIPTION
***********


The \ **addkitcomp**\  command will assign kit components to an xCAT osimage. The kit component meta rpm, package rpm and deploy parameters will be added to osimage's otherpkg.pkglist and postbootscripts will be added to osimages's postbootscripts attribute.

\ **Note:**\  xCAT Kit support is ONLY available for Linux operating systems.


*******
OPTIONS
*******



\ **-a|-**\ **-adddeps**\ 
 
 Assign kitcomponent dependencies to the osimage.
 


\ **-h|-**\ **-help**\ 
 
 Display usage message.
 


\ **-V|-**\ **-verbose**\ 
 
 Verbose mode.
 


\ **-v|-**\ **-version**\ 
 
 Command version.
 


\ **-f|-**\ **-force**\ 
 
 Add kit component to osimage even if there is a mismatch in OS, version, arch, serverrole, or kitcompdeps
 


\ **-i**\  \ *osimage*\ 
 
 The osimage name that the kit component is assigning to.
 


\ **-n|-**\ **-noupgrade**\ 
 
 1. Allow multiple versions of kitcomponent to be installed into the osimage, instead of kitcomponent upgrade.
 
 2. Kit components added by addkitcomp -n will be installed separately behind all other ones which have been added.
 


\ **-**\ **-noscripts**\ 
 
 Do not add kitcomponent's postbootscripts to osimage
 


\ *kitcompname_list*\ 
 
 A comma-delimited list of valid full kit component names or kit component basenames that are to be added to the osimage.
 



************
RETURN VALUE
************


0  The command completed successfully.

1  An error has occurred.


********
EXAMPLES
********


1. To add a single kit component to osimage "rhels6.2-ppc64-netboot-compute":


.. code-block:: perl

  addkitcomp -i rhels6.2-ppc64-netboot-compute comp-test1-1.0-1-rhels-6.2-ppc64


2. To add a kit component to osimage with dependencies, use the -a (addeps) option:


.. code-block:: perl

  addkitcomp -a -i rhels6.2-ppc64-netboot-compute comp-test2-1.0-1-rhels-6.2-ppc64


3. To add a kit component to osimage with incompatable osarch, osversion or ostype, use the -f (force) option:


.. code-block:: perl

  addkitcomp -f -i rhels6.2-ppc64-netboot-compute comp-test1-1.0-1-rhels-6.2-ppc64


4. To add a new version of kit component to osimage without upgrade, use the -n (noupgrade) option:


.. code-block:: perl

  addkitcomp -n -i rhels6.2-ppc64-netboot-compute comp-test2-1.0-1-rhels-6.2-ppc64



********
SEE ALSO
********


lskit(1)|lskit.1, addkit(1)|addkit.1, rmkit(1)|rmkit.1, rmkitcomp(1)|rmkitcomp.1, chkkitcomp(1)|chkkitcomp.1

