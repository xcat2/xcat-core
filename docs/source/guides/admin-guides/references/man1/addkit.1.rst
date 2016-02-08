
########
addkit.1
########

.. highlight:: perl


****
NAME
****


\ **addkit**\  - Install a kit on the xCAT management node


********
SYNOPSIS
********


\ **addkit**\  [\ **-?**\ |\ **-h**\ |\ **--help**\ ] [\ **-v**\ |\ **--version**\ ]

\ **addkit**\  [\ **-i**\ |\ **--inspection**\ ] \ *kitlist*\ 

\ **addkit**\  [\ **-V**\ |\ **--verbose**\ ] [\ **-p**\ |\ **--path**\  \ *path*\ ] \ *kitlist*\ 


***********
DESCRIPTION
***********


The \ **addkit**\  command install a kit on the xCAT management node from a kit tarfile or directory, creating xCAT database definitions for kit, kitrepo, kitcomponent.

\ **Note:**\  xCAT Kit support is ONLY available for Linux operating systems.


*******
OPTIONS
*******



\ **-h|--help**\ 
 
 Display usage message.
 


\ **-V|--verbose**\ 
 
 Verbose mode.
 


\ **-v|--version**\ 
 
 Command version.
 


\ **-i|--inspection**\ 
 
 Show the summary of the given kits
 


\ **-p|--path <path**\ >
 
 The destination directory to which the contents of the kit tarfiles and/or kit deploy directories will be copied.  When this option is not specified, the default destination directory will be formed from the installdir site attribute with ./kits subdirectory.
 


\ **kitlist**\ 
 
 A comma delimited list of kit_tarball_files and kit_deploy_dirs that are to be added to the xCAT cluster.  Each entry can be an absolute or relative path.  For kit_tarball_files, these must be valid kits tarfiles added.  For kit_deploy_dirs, these must be fully populated directory structures that are identical to the contents of an expanded kit_tarball_file.
 



************
RETURN VALUE
************


0  The command completed successfully.

1  An error has occurred.


********
EXAMPLES
********


1. To add two kits from tarball files.


.. code-block:: perl

  addkit kit-test1.tar.bz2,kit-test2.tar.bz2


2. To add two kits from directories.


.. code-block:: perl

  addkit kit-test1,kit-test2


3. To add a kit from tarball file to /install/test directory.


.. code-block:: perl

  addkit -p /install/test kit-test1.tar.bz2


4. To read the general information of the kit, without adding the kits to xCAT DB


.. code-block:: perl

  addkit -i kit-test1.tar.bz2



********
SEE ALSO
********


lskit(1)|lskit.1, rmkit(1)|rmkit.1, addkitcomp(1)|addkitcomp.1, rmkitcomp(1)|rmkitcomp.1, chkkitcomp(1)|chkkitcomp.1

