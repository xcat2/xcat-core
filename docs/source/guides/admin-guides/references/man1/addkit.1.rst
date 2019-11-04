
########
addkit.1
########

.. highlight:: perl


****
NAME
****


\ **addkit**\  - Adds product software Kits to an xCAT cluster environmnet.


********
SYNOPSIS
********


\ **addkit**\  [\ **-? | -h | -**\ **-help**\ ] [\ **-v | -**\ **-version**\ ]

\ **addkit**\  [\ **-i | -**\ **-inspection**\ ] \ *kitlist*\ 

\ **addkit**\  [\ **-V | -**\ **-verbose**\ ] [\ **-p | -**\ **-path**\  \ *path*\ ] \ *kitlist*\ 


***********
DESCRIPTION
***********


The \ **addkit**\  command installs a kit on the xCAT management node from a kit tarfile or directory.
It creates xCAT database definitions for the kit, kitrepo, and kitcomponent.

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
 


\ **-i|-**\ **-inspection**\ 
 
 Show the summary of the given kits
 


\ **-p|-**\ **-path**\  \ *path*\ 
 
 The destination directory to which the contents of the kit tarfiles and/or kit deploy directories will be copied.  When this option is not specified, the default destination directory will be formed from the installdir site attribute with ./kits subdirectory.
 


\ *kitlist*\ 
 
 A comma delimited list of kit_tarball_files or kit_deploy_directories to be added to the xCAT environment. Each entry can be an absolute or relative path.  See xCAT documentation for more information on building kits.
 



************
RETURN VALUE
************


0  The command completed successfully.

1  An error has occurred.


********
EXAMPLES
********


1. To add kits from tarball files:


.. code-block:: perl

  addkit kit-test1.tar.bz2,kit-test2.tar.bz2


2. To add kits from directories:


.. code-block:: perl

  addkit kit-test1,kit-test2


3. To add kits from tarball \ *kit-test1.tar.bz2*\  to target path \ */install/test*\ :


.. code-block:: perl

  addkit -p /install/test kit-test1.tar.bz2


4. To see general information about kit \ *kit-test1.tar.bz2*\  without adding the kit to xCAT:


.. code-block:: perl

  addkit -i kit-test1.tar.bz2



********
SEE ALSO
********


lskit(1)|lskit.1, rmkit(1)|rmkit.1, addkitcomp(1)|addkitcomp.1, rmkitcomp(1)|rmkitcomp.1, chkkitcomp(1)|chkkitcomp.1

