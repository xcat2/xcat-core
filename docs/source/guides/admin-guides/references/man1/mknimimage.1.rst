
############
mknimimage.1
############

.. highlight:: perl


****
NAME
****


\ **mknimimage**\  - Use this xCAT command to create xCAT osimage definitions and related AIX/NIM resources. The command can also be used to update an existing AIX diskless image(SPOT).


********
SYNOPSIS
********


\ **mknimimage [-h | -**\ **-help ]**\ 

\ **mknimimage [-V] -u**\  \ *osimage_name [attr=val [attr=val ...]*\ ]

\ **mknimimage [-V] [-f|-**\ **-force] [-r|-**\ **-sharedroot] [-D|-**\ **-mkdumpres] [-l**\  \ *location*\ ] [\ **-c | -**\ **-completeosimage**\ ] [\ **-s**\  \ *image_source*\ ] [\ **-i**\  \ *current_image*\ ] [\ **-p | -**\ **-cplpp**\ ] [\ **-t**\  \ *nimtype*\ ] [\ **-m**\  \ *nimmethod*\ ] [\ **-n**\  \ *mksysbnode*\ ] [\ **-b**\  \ *mksysbfile*\ ] \ *osimage_name*\  [\ *attr=val [attr=val ...]*\ ]


***********
DESCRIPTION
***********


This command will create both an xCAT osimage definition and the corresponding NIM resource definitions. The command can also be used to update an existing AIX diskless image(SPOT).

The command will also install the NIM master software and configure NIM if needed.

The naming convention for the NIM SPOT resource definition is to use the same name as the xCAT osimage.  The naming convention for any other NIM resources that are created is "<osimage_name>_<resource_type>". (ex. "61image_lpp_source" )

When creating a mksysb image definition you must specify either the "-n" or the "-b" option. The "-n" option can be used to create a mksysb image from an existing NIM client machine.  The "-b" option can be used to specify an existing mksysb backup file.

\ **Adding software and configuration files to the osimage.**\ 

When creating a diskless osimage definition you also have the option of automatically updating the NIM SPOT resource.  You can have additional software installed or you can have configuration files added or updated.  To have software installed you must provide either the names of NIM installp_bundle resources or fileset names on the command line using the "attr=val" option. You may also supply the installp flags, RPM flags, emgr flags to use when installing the software.

To have configuration files updated you must provide the full path name of a "synclists" file which contains the the list of actual files to update.  The xCAT osimage definition that is created will contain the installp_bundle, otherpkgs, and synclists files that are provided on the command line.

\ **Updating an existing xCAT osimage**\ 

If you wish to update an existing diskless image after it has already been created you can use the "-u" (update) option.  In this case the xCAT osimage definition will not be updated.

There are two ways to use the update feature.

You can update the osimage definition and run the \ **mknimimage**\  command with no "installp_bundle", "otherpkgs", or "synclists" command line values. The information for updating the SPOT will come from the osimage definition only.  This has the advantage of keeping a record of any changes that were made to the SPOT.

Or, you could do a more ad hoc update by providing one or more of the "installp_bundle", "otherpkgs", or "synclists" values on the command line. If any of these values are provided the \ **mknimimage**\  command will use those values only. The osimage definition will not be used or updated.

WARNING: Installing random RPM packages in a SPOT may have unpredictable consequences.  The SPOT is a very restricted environment and some RPM packages may corrupt the SPOT or even hang your management system.  Try to be very careful about the packages you install. When installing RPMs, if the mknimimage command hangs or if there are file systems left mounted after the command completes you may need to reboot your management node to recover.  This is a limitation of the current AIX support for diskless systems

\ **Copying an xCAT osimage.**\ 

You can use the "-i" and "-p" options to copy an existing diskless osimage.   To do this you must supply the name of an existing xCAT osimage definition and the name of the new osimage you wish to create. The \ **mknimimage**\  command will do the following:

- create a new xCAT osimage definition using the new name that was specified.

- copy the NIM SPOT resource to a new location and define it to NIM using a new name.

- if the original osimage included a NIM "shared_root" resource then a new shared_root resource will be created for the new SPOT.

- any other resources (or attributes) included in the original osimage will be included in the new osimage definition.

- if the "-p" option is specified then the original NIM lpp_source resource will be copied to a new location and redfined to NIM. (The default would be to use the original lpp_source - to save file system space.)

\ **Additional information**\ 

IMPORTANT:  The NIM lpp_source and SPOT resources can get quite large. Always make sure that you have sufficient file system space available before running the \ **mknimimage**\  command.

To list the contents of the xCAT osimage definition use the xCAT \ **lsdef**\  command ("lsdef -t osimage -l -o <osimage_name>").

To check the validity of a SPOT or lpp_source resource

To remove an xCAT osimage definition along with the associated NIM resource definitions use the \ **rmnimimage**\  command. Be careful not to accidently remove NIM resources if they are still needed.

To list a NIM resource definition use the AIX \ **lsnim**\  command ("lsnim -l <resource_name>").

To check the validity of a SPOT or lpp_source resource use the AIX \ **nim**\  command ("nim -o check <resourec-name>").

To remove specific NIM resource definitons use the AIX \ **nim**\  command. ("nim -o remove <resource-name>").


*******
OPTIONS
*******



\ *attr=val [attr=val ...]*\ 
 
 Specifies one or more "attribute equals value" pairs, separated by spaces. Attr=val pairs must be specified last on the command line.
 
 Currently supported attributes:
 
 
 \ **bosinst_data**\ 
  
  The name of a NIM bosinst_data resource.
  
 
 
 \ **dump**\ 
  
  The name of the NIM dump resource.
  
 
 
 \ **fb_script**\ 
  
  The name of a NIM fb_script resource.
  
 
 
 \ **home**\ 
  
  The name of the NIM home resource.
  
 
 
 \ **installp_bundle**\ 
  
  One or more comma separated NIM installp_bundle resources.
  
 
 
 \ **lpp_source**\ 
  
  The name of the NIM lpp_source resource.
  
 
 
 \ **mksysb**\ 
  
  The name of a NIM mksysb resource.
  
 
 
 \ **otherpkgs**\ 
  
  One or more comma separated installp, emgr, or rpm packages.  The packages must
  have prefixes of 'I:', 'E:', or 'R:', respectively. (ex. R:foo.rpm)
  
 
 
 \ **paging**\ 
  
  The name of the NIM paging resource.
  
 
 
 \ **resolv_conf**\ 
  
  The name of the NIM resolv_conf resource.
  
 
 
 \ **root**\ 
  
  The name of the NIM root resource.
  
 
 
 \ **script**\ 
  
  The name of a NIM script resource.
  
 
 
 \ **shared_home**\ 
  
  The name of the NIM shared_home resource.
  
 
 
 \ **shared_root**\ 
  
  A shared_root resource represents a directory that can be used as a / (root) directory by one or more diskless clients.
  
 
 
 \ **spot**\ 
  
  The name of the NIM SPOT resource.
  
 
 
 \ **synclists**\ 
  
  The fully qualified name of a file containing a list of files to synchronize on the nodes.
  
 
 
 \ **tmp**\ 
  
  The name of the NIM tmp resource.
  
 
 
 \ **installp_flags**\ 
  
  The alternate flags to be passed along to the AIX installp command. (The default for installp_flags is "-abgQXY".)
  
 
 
 \ **rpm_flags**\ 
  
  The alternate flags to be passed along to the AIX rpm command. (The default for
  rpm_flags is "-Uvh ".) The mknimimage command will check each rpm to see if 
  it is installed.  It will not be reinstalled unless you specify the appropriate
  rpm option, such as '--replacepkgs'.
  
 
 
 \ **emgr_flags**\ 
  
  The alternate flags to be passed along to the AIX emgr command. (There is no default flags for the emgr command.)
  
 
 
 \ **dumpsize**\ 
  
  The maximum size for a single dump image the dump resource will accept. Space is not allocated until a client starts to dump. The default size is 50GB. The dump resource should be large enough to hold the expected AIX dump and snap data.
  
 
 
 \ **max_dumps**\ 
  
  The maximum number of archived dumps for an individual client. The default is one.
  
 
 
 \ **snapcollect**\ 
  
  Indicates that after a dump is collected then snap data should be collected. The snap data will be collected in the clients dump resource directory.  Values are "yes" or "no". The default is "no".
  
 
 
 \ **nfs_vers**\ 
  
  Value Specifies the NFS protocol version required for NFS access.
  
 
 
 \ **nfs_sec**\ 
  
  Value Specifies the security method required for NFS access.
  
 
 
 Note that you may specify multiple "script", "otherpkgs", and "installp_bundle" resources by using a comma seperated list. (ex. "script=ascript,bscript"). RPM names may be included in the "otherpkgs" list by using a "R:" prefix(ex. "R:whatever.rpm"). epkg (AIX interim fix package) file names may be included in the "otherpkgs" using the 'E:' prefix. (ex. "otherpkgs=E:IZ38930TL0.120304.epkg.Z").
 


\ **-b**\  \ *mksysbfile*\ 
 
 Used to specify the path name of a mksysb file to use when defining a NIM mksysb resource.
 


\ **-c|-**\ **-completeosimage**\ 
 
 Complete the creation of the osimage definition passed in on the command line. This option will use any additonal values passed in on the command line and/or it will attempt to create required resources in order to complete the definition of the xCAT osimage.  For example, if the osimage definition is missing a spot or shared_root resource the command will create those resources and add them to the osimage definition.
 


\ **-f|-**\ **-force**\ 
 
 Use the force option to re-create xCAT osimage definition. This option removes the old definition before creating the new one. It does not remove any of the NIM resource definitions named in the osimage definition.  Use the \ **rmnimimage**\  command to remove the NIM resources associated with an xCAT osimage definition.
 


\ **-h |-**\ **-help**\ 
 
 Display usage message.
 


\ *osimage_name*\ 
 
 The name of the xCAT osimage definition.  This will be used as the name of the xCAT osimage definition as well as the name of the NIM SPOT resource.
 


\ **-D|-**\ **-mkdumpres**\ 
 
 Create a diskless dump resource.
 


\ **-i**\  \ *current_image*\ 
 
 The name of an existing xCAT osimage that should be copied to make a new xCAT osimage definition. Only valid when defining a "diskless" or "dataless" type image.
 


\ **-l**\  \ *location*\ 
 
 The directory location to use when creating new NIM resources. The default location is /install/nim.
 


\ **-m**\  \ *nimmethod*\ 
 
 Used to specify the NIM installation method to use. The possible values are "rte" and "mksysb". The default is "rte".
 


\ **-n**\  \ *mksysbnode*\ 
 
 The xCAT node to use to create a mksysb image.  The node must be a defined as a NIM client machine.
 


\ **-p|-**\ **-cplpp**\ 
 
 Use this option when copying existing diskless osimages to indicate that you also wish to have the lpp_resource copied.  This option is only valid when using the "-i" option.
 


\ **-r|-**\ **-sharedroot**\ 
 
 Use this option to specify that a NIM "shared_root" resource be created for the AIX diskless nodes.  The default is to create a NIM "root" resource.  This feature is only available when using AIX version 6.1.4 or beyond. See the AIX/NIM documentation for a description of the "root" and "shared_root" resources.
 


\ **-s**\  \ *image_source*\ 
 
 The source of software to use when creating the new NIM lpp_source resource. This could be a source directory or a previously defined NIM lpp_source resource name.
 


\ **-t nimtype**\ 
 
 Used to specify the NIM machine type. The possible values are "standalone", "diskless" or "dataless".  The default is "standalone".
 


\ **-u**\ 
 
 Used to update an AIX/NIM SPOT resource with additional software and configuration files.  This option is only valid for xCAT diskless osimage objects. The SPOT resource associated with the xCAT osimage definition will be updated. This option can also be used to update the nfs_vers attribute from NFSv3 to NFSv4 for the NIM resources associated with diskful or diskless image.
 


\ **-V |-**\ **-verbose**\ 
 
 Verbose mode.
 



************
RETURN VALUE
************



0. The command completed successfully.



1. An error has occurred.




********
EXAMPLES
********


1) Create an osimage definition and the basic NIM resources needed to do a NIM "standalone" "rte" installation of node "node01".  Assume the software contained on the AIX product media has been copied to the /AIX/instimages directory.


.. code-block:: perl

  mknimimage -s /AIX/instimages  61image


2) Create an osimage definition that includes some additional NIM resources.


.. code-block:: perl

  mknimimage -s /AIX/instimages 61image installp_bundle=mybndlres,addswbnd


This command will create lpp_source, spot, and bosinst_data resources using the source specified by the "-s" option.  The installp_bundle information will also be included in the osimage definition.  The mybndlres and addswbnd resources must be created before using this osimage definition to install a node.

3) Create an osimage definition that includes a mksysb image and related resources.


.. code-block:: perl

  mknimimage -m mksysb -n node27 newsysb spot=myspot bosinst_data=mybdata


This command will use node27 to create a mksysb backup image and use that to define a NIM mksysb resource. The osimage definition will contain the name of the mksysb resource as well as the spot and bosinst_data resource.

4) Create an osimage definition using a mksysb image provided on the command line.


.. code-block:: perl

  mknimimage -m mksysb -b /tmp/backups/mysysbimage newsysb spot=myspot bosinst_data=mybdata


This command defines a NIM mksysb resource using mysysbimage.

5) Create an osimage definition and create the required spot definition using the mksysb backup file provided on the command line.


.. code-block:: perl

  mknimimage -m mksysb -b /tmp/backups/mysysbimage newsysb bosinst_data=mybdata


This command defines a NIM mksysb resource and a spot definition using mysysbimage.

6) Create a diskless image called 61dskls using the AIX source files provided in the /AIX/instimages directory.


.. code-block:: perl

  mknimimage -t diskless -s /AIX/instimages 61dskls


7) Create a diskless image called "614dskls" that includes a NIM "shared_root" and a "dump" resource.  Use the existing NIM lpp_resource called "614_lpp_source". Also specify verbose output.


.. code-block:: perl

  mknimimage -V -r -D -t diskless -s 614_lpp_source 614dskls snapcollect=yes


The "snapcollect" attribute specifies that AIX "snap" data should be include when a system dump is initiated.

8) Create a new diskless image by copying an existing image.


.. code-block:: perl

  mknimimage -t diskless -i 61cosi 61cosi_updt1


Note:  If you also wish to have the original lpp_source copied and defined use the -p option.


.. code-block:: perl

  mknimimage -t diskless -i 61cosi -p 61cosi_updt1


9) Create a diskless image using an existing lpp_source resource named "61cosi_lpp_source" and include NIM tmp and home resources.  This assumes that the "mytmp" and "myhome" NIM resources have already been created by using NIM commands.


.. code-block:: perl

  mknimimage -t diskless -s 61cosi_lpp_source 611cosi tmp=mytmp home=myhome


10) Create a diskless image and update it with additional software using rpm flags and configuration files.


.. code-block:: perl

  mknimimage -t diskless -s 61cosi_lpp_source 61dskls otherpkgs=I:fset1,R:foo.rpm,E:IZ38930TL0.120304.epkg.Z synclists=/install/mysyncfile rpm_flags="-i --nodeps"


The xCAT osimage definition created by this command will include the "otherpkgs" and "synclists" values.  The NIM SPOT resource associated with this osimage will be updated with the additional software using rpm flags "-i --nodeps" and configuration files.

11) Update an existing diskless image (AIX/NIM SPOT) using the information saved in the xCAT "61dskls" osimage definition. Also specify verbose messages.


.. code-block:: perl

  mknimimage -V -u 61dskls


12) Update an existing diskless image called "61dskls".  Install the additional software specified in the NIM "bndres1" and "bndres2" installp_bundle resources using the installp flags "-agcQX".  (The NIM "bndres1" and "bndres2" definitions must be created before using them in this command.)


.. code-block:: perl

  mknimimage -u 61dskls installp_bundle=bndres1,bndres2 installp_flags="-agcQX"


Note that when "installp_bundle", "otherpkgs", or "synclists" values are specified with the "-u" option then the xCAT osimage definiton is not used or updated.

13) Update an existing image to support NFSv4. Also specify verbose messages.


.. code-block:: perl

  mknimimage -V -u 61dskls nfs_vers=4



*****
FILES
*****


/opt/xcat/bin/mknimimage


*****
NOTES
*****


This command is part of the xCAT software product.


********
SEE ALSO
********


rmnimimage(1)|rmnimimage.1

