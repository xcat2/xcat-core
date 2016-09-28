
###########
imgexport.1
###########

.. highlight:: perl


****
NAME
****


\ **imgexport**\  - Exports an xCAT image.


********
SYNOPSIS
********


\ **imgexport [-h| -**\ **-help]**\ 

\ **imgexport**\  \ *image_name*\  [\ *destination*\ ] [[\ **-e | -**\ **-extra**\  \ *file:dir*\ ] ... ] [\ **-p | -**\ **-postscripts**\  \ *node_name*\ ] [\ **-v | -**\ **-verbose**\ ]


***********
DESCRIPTION
***********


The imgexport command will export an image that is being used by xCAT.  To export images, you must have the images defined in the \ *osimage*\  table. All the columns in the \ *osimage*\  and \ *linuximage*\  tables will be exported. If kits are used in stateful or stateless images, \ *kit*\ , \ *kitcomponent*\  and \ *kitrepo*\  tables will be exported. In addition, the following files will also be exported.

For stateful:
  x.pkglist
  x.otherpkgs.pkglist
  x.tmpl
  x.synclist
  kits related files

For stateless:
  kernel
  initrd.gz
  rootimg.cpio.xz or rootimg.cpio.gz or rootimg.tar.xz or rootimg.tar.gz or rootimg.gz(for backward-compatibility)
  x.pkglist
  x.otherpkgs.pkglist
  x.synclist
  x.postinstall
  x.exlist
  kits related files

For statelite:
  kernel
  initrd.gz
  root image tree
  x.pkglist
  x.synclist
  x.otherpkgs.pkglist
  x.postinstall
  x.exlist

where x is the name of the profile.

Any files specified by the -e flag will also be exported. If -p flag is specified, the names of the postscripts and the postbootscripts for the given node will be exported. The postscripts themsleves need to be manualy exported using -e flag.

For statelite, the litefile table settings for the image will also be exported. The litetree and statelite tables are not exported.


*******
OPTIONS
*******


\ **-e|-**\ **-extra**\  \ *srcfile:destdir*\     Pack up extra files. If \ *destdir*\  is omitted, the destination directory will be the same as the source directory.

\ **-h|-**\ **-help**\                          Display usage message.

\ **-p|-**\ **-postscripts**\  \ *node_name*\   Get the names of the postscripts and postbootscripts for the given node and pack them into the image.

\ **-v|-**\ **-verbose**\                       Verbose output.

\ *image_name*\                         The name of the image. Use \ *lsdef -t*\  osimage to find out all the image names.

\ *destination*\                        The output bundle file name.


************
RETURN VALUE
************


0 The command completed successfully.

1 An error has occurred.


********
EXAMPLES
********


1. Simplest way to export an image.  If there is an image in the osimage table named 'foo', then run:


.. code-block:: perl

  imgexport foo


foo.tgz will be built in the current working directory.  Make sure that you have enough space in the directory that you are in to run imgexport if you have a big image to tar up.

2. To include extra files with your image:


.. code-block:: perl

  imgexport Default_Stateless_1265981465 foo.tgz -e /install/postscripts/myscript1 -e /tmp/mydir:/usr/mydir


In addition to all the default files, this will export \ */install/postscripts/myscript1*\  and the whole directory \ */tmp/dir*\  into the file called foo.tgz.  And when imgimport is called  \ */install/postscripts/myscript1*\  will be copied into the same directory and \ */tmp/mydir*\  will be copied to \ */usr/mydir*\ .

3. To include postscript with your image:


.. code-block:: perl

  imgexport Default_Stateless_1265981465 foo.tgz -p node1 -e /install/postscripts/myscript1


The \ *postscripts*\  and the \ *postbootscripts*\  names specified in the \ *postscripts*\  table for node1 will be exported into the image. The postscript \ *myscript1*\  will also be exported.


*****
FILES
*****


/opt/xcat/bin/imgexport


********
SEE ALSO
********


imgimport(1)|imgimport.1

