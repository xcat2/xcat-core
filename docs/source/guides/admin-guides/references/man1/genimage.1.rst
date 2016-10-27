
##########
genimage.1
##########

.. highlight:: perl


****
NAME
****


\ **genimage**\  - Generates a stateless image to be used for a diskless install.


********
SYNOPSIS
********


\ **genimage**\ 

\ **genimage**\  [\ **-o**\  \ *osver*\ ] [\ **-a**\  \ *arch*\ ] [\ **-p**\  \ *profile*\ ] [\ **-i**\  \ *nodebootif*\ ] [\ **-n**\  \ *nodenetdrivers*\ ] [\ **-**\ **-onlyinitrd**\ ] [\ **-r**\  \ *otherifaces*\ ] [\ **-k**\  \ *kernelver*\ ] [\ **-g**\  \ *krpmver*\ ] [\ **-m**\  \ *statelite*\ ] [\ **-l**\  \ *rootlimitsize*\ ] [\ **-**\ **-permission**\  \ *permission*\ ] [\ **-**\ **-interactive**\ ] [\ **-**\ **-dryrun**\ ] [\ **-**\ **-ignorekernelchk**\ ] [\ **-**\ **-noupdate**\ ] \ *imagename*\ 

\ **genimage**\  [\ **-h**\  | \ **-**\ **-help**\  | \ **-v**\  | \ **-**\ **-version**\ ]


***********
DESCRIPTION
***********


Generates a stateless and a statelite image that can be used to boot xCAT nodes in a diskless mode.

genimage will use the osimage definition for information to generate this image.  Additional options specified on the command line will override any corresponding previous osimage settings, and will be written back to the osimage definition.

If \ **genimage**\  runs on the management node, both the \ *osimage*\  table and \ *linuximage*\  table will be updated with the given values from the options.

The \ **genimage**\  command will generate two initial ramdisks for \ **stateless**\  and \ **statelite**\ , one is \ **initrd-stateless.gz**\ , the other one is \ **initrd-statelite.gz**\ .

After your image is generated, you can chroot to the
image, install any additional software you would like, or make modifications to files, and then run the following command to prepare the image for deployment.

for stateless: \ **packimage**\ 

for statelite: \ **liteimg**\ 

Besides prompting for some paramter values, the \ **genimage**\  command takes default guesses for the parameters not specified or not defined in the \ *osimage*\  and \ *linuximage*\  tables. It also assumes default answers for questions from the yum/zypper command when installing rpms into the image. Use \ **-**\ **-interactive**\  flag if you want the yum/zypper command to prompt you for the answers.

If \ **-**\ **-onlyinitrd**\  is specified, genimage only regenerates the initrd for a stateless image to be used for a diskless install.

The \ **genimage**\  command must be run on a system that is the same architecture and same distro with same major release version as the nodes it will be
used on.  If the management node is not the same architecture or same distro level, copy the contents of
/opt/xcat/share/xcat/netboot/<os> to a system that is the proper architecture, and mount /install from
the management node to that system. Then change directory to /opt/xcat/share/xcat/netboot/<os> and run ./genimage.


**********
Parameters
**********


\ *imagename*\  specifies the name of an os image definition to be used. The specification for the image is stored in the \ *osimage*\  table and \ *linuximage*\  table.


*******
OPTIONS
*******



\ **-a**\  \ *arch*\ 
 
 The hardware architecture of this node: x86_64, ppc64, x86, ia64, etc. If omitted, the current hardware architecture will be used.
 


\ **-o**\  \ *osver*\ 
 
 The operating system for the image:  fedora8, rhel5, sles10, etc.  The OS packages must be in
 /install/<osver>/<arch> (use copycds(8)|copycds.8).
 


\ **-p**\  \ *profile*\ 
 
 The profile (e.g. compute, service) to use to create the image.  This determines what package lists are
 used from /opt/xcat/share/xcat/netboot/<os> to create the image with.  When deploying nodes with this image,
 the nodes' nodetype.profile attribute must be set to this same value.
 


\ **-i**\  \ *nodebootif*\ 
 
 This argument is now optional, and allows you to specify the network boot interface to be configured in the image (e.g. eth0). If not specified, the interface will be determined and configured during the network boot process.
 


\ **-n**\  \ *nodenetdrivers*\ 
 
 This argument is now optional, and allows you to specify the driver
 modules needed for the network interface(s) on your stateless nodes.  If
 you do not specify this option, the default is to include all recent IBM
 xSeries network drivers.
 
 If specified, \ *nodenetdrivers*\  should be a comma separated list of
 network drivers to be used by the stateless nodes (Ie.: -n tg3,e1000).
 Note that the drivers will be loaded in the order that you list them,
 which may prove important in some cases.
 


\ **-l**\  \ *rootlimit*\ 
 
 The maximum size allowed for the root file system in the image.  Specify in bytes, or can append k, m, or g.
 


\ **-**\ **-onlyinitrd**\ 
 
 Regenerates the initrd for a stateless image to be used for a diskless install.
 
 Regenerates the initrd that is part of a stateless/statelite image that is used to boot xCAT nodes in a stateless/stateli
 te mode.
 
 The \ **genimage -**\ **-onlyinitrd**\  command will generate two initial ramdisks, one is \ **initrd-statelite.gz**\  for \ **statelite**\  mode, the other one is \ **initrd-stateless.gz**\  for \ **stateless**\  mode.
 


\ **-**\ **-permission**\  \ *permission*\ 
 
 The mount permission of \ **/.statelite**\  directory for \ **statelite**\  mode, which is only used for \ **statelite**\  mode, and the default permission is 755.
 


\ **-r**\  \ *otherifaces*\ 
 
 Other network interfaces (e.g. eth1) in the image that should be configured via DHCP.
 


\ **-k**\  \ *kernelver*\ 
 
 Use this flag if you want to use a specific version of the kernel in the image.  Defaults to the first kernel found
 in the install image.
 


\ **-g**\  \ *krpmver*\ 
 
 Use this flag to specify the rpm version for kernel packages in the image. It must be present if -k flag is specified in the command for SLES. Generally, the value of -g is the part after \ **linux-**\  and before \ **.rpm**\  in a kernel rpm name.
 


\ **-m**\  statelite
 
 This flag is for Ubuntu, Debian and Fedora12 only. Use this flag to specify if you want to generate statelite image. The default is to generate stateless image for these three operating systems. For others, this flag is invalid because both stateless and statelite images will be generated with this command.
 


\ **-**\ **-interactive**\ 
 
 This flag allows the user to answer questions from yum/zypper command when installing rpms into the image. If it is not specified, '-y' will be passed to the yum command and '--non-interactive --no-gpg-checks' will be passed to the zypper command as default answers.
 


\ **-**\ **-dryrun**\ 
 
 This flag shows the underlying call to the os specific genimage function. The user can copy and the paste the output to run the command on another machine that does not have xCAT installed.
 


\ **-t**\  \ *tmplimit*\ 
 
 (Deprecated) This flag allows the user to setup the /tmp and the /var/tmp file system sizes. This flag is no longer supported. You can overwrite any file system size using the .postinstall script where you can create a new /etc/fstab file.
 


\ **-**\ **-ignorekernelchk**\ 
 
 Skip the kernel version checking when injecting drivers from osimage.driverupdatesrc. That means all drivers from osimage.driverupdatesrc will be injected to initrd for the specific target kernel.
 


\ **-**\ **-noupdate**\ 
 
 This flag allows the user to bypass automatic package updating when installing other packages.
 


\ **-v|-**\ **-version**\ 
 
 Display version.
 


\ **-h|-**\ **-help**\ 
 
 Display usage message.
 



************
RETURN VALUE
************


0 The command completed successfully.

1 An error has occurred.


********
EXAMPLES
********



1 To prompt the user for inputs:
 
 
 .. code-block:: perl
 
    genimage
 
 


2 To generate an image using information from an osimage definition:
 
 
 .. code-block:: perl
 
    genimage myimagename
 
 


3 To run genimage in test mode without actually generating an image:
 
 
 .. code-block:: perl
 
    genimage --dryrun  myimagename
 
 


4 To generate an image and have yum/zypper prompt for responses:
 
 
 .. code-block:: perl
 
    genimage myimagename --interactive
 
 


5 To generate an image, replacing some values in the osimage definition:
 
 
 .. code-block:: perl
 
    genimage -i eth0 -n tg3 myimagename
 
 



*****
FILES
*****


/opt/xcat/bin/genimage

/opt/xcat/share/xcat/netboot/<OS>/genimage


********
SEE ALSO
********


packimage(1)|packimage.1, liteimg(1)|liteimg.1

