
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

Note: The xCAT support for Kits is only available for Linux operating systems.


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
 
 Allow multiple versions of kitcomponent to be installed into the osimage, instead of kitcomponent upgrade
 


\ **-**\ **-noscripts**\ 
 
 Do not add kitcomponent's postbootscripts to osimage
 


\ **kitcompname_list**\ 
 
 A comma-delimited list of valid full kit component names or kit component basenames that are to be added to the osimage.
 



************
RETURN VALUE
************


0  The command completed successfully.

1  An error has occurred.


********
EXAMPLES
********


1. To assign a kit component to osimage

addkitcomp -i rhels6.2-ppc64-netboot-compute comp-test1-1.0-1-rhels-6.2-ppc64

Output is similar to:

Assigning kit component comp-test1-1.0-1-rhels-6.2-ppc64 to osimage rhels6.2-ppc64-netboot-compute
Kit components comp-test1-1.0-1-rhels-6.2-ppc64 were added to osimage rhels6.2-ppc64-netboot-compute successfully

2. To assign a kit component to osimage with its dependency.

addkitcomp -a -i rhels6.2-ppc64-netboot-compute comp-test2-1.0-1-rhels-6.2-ppc64

Output is similar to:

Assigning kit component comp-test1-1.0-1-rhels-6.0-ppc64 to osimage rhels6.2-ppc64-netboot-compute
Assigning kit component comp-test2-1.0-1-rhels-6.2-ppc64 to osimage rhels6.2-ppc64-netboot-compute
Kit components comp-test1-1.0-1-rhels-6.0-ppc64,comp-test2-1.0-1-rhels-6.2-ppc64 were added to osimage rhels6.2-ppc64-netboot-compute successfully

3. To assign a kit component to osimage with incompatable osarch, osversion or ostype.

addkitcomp -f -i rhels6.2-ppc64-netboot-compute comp-test1-1.0-1-rhels-6.2-ppc64

Output is similar to:

Assigning kit component comp-test1-1.0-1-rhels-6.2-ppc64 to osimage rhels6.2-ppc64-netboot-compute
Kit components comp-test1-1.0-1-rhels-6.2-ppc64 were added to osimage rhels6.2-ppc64-netboot-compute successfully

4. To assign a new version of kit component to osimage without upgrade.

addkitcomp -n -i rhels6.2-ppc64-netboot-compute comp-test2-1.0-1-rhels-6.2-ppc64

Output is similar to:

Assigning kit component comp-test1-1.0-1-rhels-6.0-ppc64 to osimage rhels6.2-ppc64-netboot-compute
Assigning kit component comp-test2-1.0-1-rhels-6.2-ppc64 to osimage rhels6.2-ppc64-netboot-compute
Kit components comp-test2-1.0-1-rhels-6.2-ppc64 were added to osimage rhels6.2-ppc64-netboot-compute successfully

The result will be:
lsdef -t osimage rhels6.2-ppc64-netboot-compute -i kitcomponents
Object name: rhels6.2-ppc64-netboot-compute
kitcomponents=comp-test2-1.0-0-rhels-6.2-ppc64,comp-test2-1.0-1-rhels-6.2-ppc64


********
SEE ALSO
********


lskit(1)|lskit.1, addkit(1)|addkit.1, rmkit(1)|rmkit.1, rmkitcomp(1)|rmkitcomp.1, chkkitcomp(1)|chkkitcomp.1

