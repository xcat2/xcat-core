
###########
imgimport.1
###########

.. highlight:: perl


****
NAME
****


\ **imgimport**\  - Imports an xCAT image or configuration file into the xCAT tables so that you can immediately begin deploying with it.


********
SYNOPSIS
********


\ **imgimport [-h|-**\ **-help]**\ 

\ **imgimport**\  \ *bundle_file_name*\  [\ **-p | -**\ **-postscripts**\  \ *nodelist*\ ] [\ **-f | -**\ **-profile**\  \ *new_profile*\ ] [\ **-v | -**\ **-verbose**\ ]


***********
DESCRIPTION
***********


The imgimport command will import an image that has been exported by \ *imgexport*\  from xCAT.  This is the easiest way to transfer/backup/, change or share images created by xCAT whether they be stateless or stateful. The bundle file will be unpacked in the current working directory. The xCAT configuration such as \ *osimage*\  and \ *linuximage*\  tables will then be updated.

For stateful, the following files will be copied to the appropriate directories.
  x.pkglist
  x.otherpkgs.pkglist
  x.tmpl
  x.synclist
  kits related files

For stateless, the following files will be copied to the appropriate directories.
  kernel
  initrd.gz
  rootimg.cpio.xz or rootimg.cpio.gz or rootimg.tar.xz or rootimg.tar.gz or rootimg.gz(for backward-compatibility)
  x.pkglist
  x.otherpkgs.pkglist
  x.synclist
  x.postinstall
  x.exlist
  kits related files

For statelite, the following files will be copied to the appropriate directories.
  kernel
  initrd.gz
  root image tree
  x.pkglist
  x.synclist
  x.otherpkgs.pkglist
  x.postinstall
  x.exlist

where x is the profile name.

Any extra files, included by --extra flag in the imgexport command, will also be copied to the appropriate directories.

For statelite, the litefile table will be updated for the image. The litetree and statelite tables are not imported.

If -p flag is specified, the \ *postscripts*\  table will be updated with the postscripts and the postbootscripts names from the image for the nodes given by this flag.

If -f flag is not specified, all the files will be copied to the same directories as the source. If it is specified, the old profile name x will be changed to the new and the files will be copied to the appropriate directores for the new profiles. For example, \ */opt/xcat/share/xcat/netboot/sles/x.pkglist*\  will be copied to \ */install/custom/netboot/sles/compute_new.pkglist*\  and \ */install/netboot/sles11/ppc64/x/kernel*\  will be copied to \ */install/netboot/sles11/ppc64/compute_new/kernel*\ . This flag is commonly used when you want to copy the image on the same xCAT mn so you can make modification on the new one.

After this command, you can run the \ *nodeset*\  command and then start deploying the nodes. You can also choose to modify the files and run the following commands before the node depolyment.

For stateful:
  nodeset

For stateless: 
  genimage
  packimage
  nodeset

For statelite
  genimage
  liteimg
  nodeset


*******
OPTIONS
*******


\ **-f|-**\ **-profile**\  \ *new_prof*\       Import the image with a new profile name.

\ **-h|-**\ **-help**\                      Display usage message.

\ **-p|-**\ **-postscripts**\  \ *nodelist*\   Import the postscripts. The postscripts contained in the image will be set in the postscripts table for \ *nodelist*\ .

\ **-v|-**\ **-verbose**\                   Verbose output.


************
RETURN VALUE
************


0 The command completed successfully.

1 An error has occurred.


********
EXAMPLES
********


1. Simplest way to import an image. If there is a bundle file named 'foo.gz', then run:


.. code-block:: perl

  imgimport foo.gz


2. Import the image with postscript names.


.. code-block:: perl

  imgimport foo.gz -p node1,node2


The \ *postscripts*\  table will be updated with the name of the \ *postscripts*\  and the \ *postbootscripts*\  for node1 and node2.

3. Import the image with a new profile name


.. code-block:: perl

  imgimport foo.gz -f compute_test



*****
FILES
*****


/opt/xcat/bin/imgimport


********
SEE ALSO
********


imgexport(1)|imgexport.1

