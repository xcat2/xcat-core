
#######
rmkit.1
#######

.. highlight:: perl


****
NAME
****


\ **rmkit**\  - Remove Kits from xCAT


********
SYNOPSIS
********


\ **rmkit**\  [\ **-? | -h | -**\ **-help**\ ] [\ **-v | -**\ **-version**\ ]

\ **rmkit**\  [\ **-V | -**\ **-verbose**\ ] [\ **-f | -**\ **-force**\ ] [\ **-t | -**\ **-test**\ ] \ *kitlist*\ 


***********
DESCRIPTION
***********


The \ **rmkit**\  command removes kits on the xCAT management node from kit names.

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
 


\ **-f|-**\ **-force**\ 
 
 Remove this kit even there is any component in this kit is listed by osimage.kitcomponents.  If this option is not specified, this kit will not be removed if any kit components listed in an osimage.kitcomponents
 


\ **-t|-**\ **-test**\ 
 
 Test if kitcomponents in this kit are used by osimage
 


\ *kitlist*\ 
 
 A comma delimited list of kits that are to be removed from the xCAT cluster.  Each entry can be a kitname or kit basename. For kit basename, rmkit command will remove all the kits that have that kit basename.
 



************
RETURN VALUE
************


0  The command completed successfully.

1  An error has occurred.


********
EXAMPLES
********


1. To remove two kits from tarball files.


.. code-block:: perl

  rmkit kit-test1,kit-test2


Output is similar to:


.. code-block:: perl

  Kit kit-test1-1.0-Linux,kit-test2-1.0-Linux was successfully removed.


2. To remove two kits from tarball files even the kit components in them are still being used by osimages.


.. code-block:: perl

  rmkit kit-test1,kit-test2 --force


Output is similar to:


.. code-block:: perl

  Kit kit-test1-1.0-Linux,kit-test2-1.0-Linux was successfully removed.


3. To list kitcomponents in this kit used by osimage


.. code-block:: perl

  rmkit kit-test1,kit-test2 -t


Output is similar to:


.. code-block:: perl

  kit-test1-kitcomp-1.0-Linux is being used by osimage osimage-test
  Following kitcomponents are in use: kit-test1-kitcomp-1.0-Linux



********
SEE ALSO
********


lskit(1)|lskit.1, addkit(1)|addkit.1, addkitcomp(1)|addkitcomp.1, rmkitcomp(1)|rmkitcomp.1, chkkitcomp(1)|chkkitcomp.1

