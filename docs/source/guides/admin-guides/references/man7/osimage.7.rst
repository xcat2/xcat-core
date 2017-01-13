
#########
osimage.7
#########

.. highlight:: perl


****
NAME
****


\ **osimage**\  - a logical object definition in the xCAT database.


********
SYNOPSIS
********


\ **osimage Attributes:**\   \ *addkcmdline*\ , \ *boottarget*\ , \ *bosinst_data*\ , \ *cfmdir*\ , \ *configdump*\ , \ *crashkernelsize*\ , \ *description*\ , \ *driverupdatesrc*\ , \ *dump*\ , \ *exlist*\ , \ *fb_script*\ , \ *groups*\ , \ *home*\ , \ *image_data*\ , \ *imagename*\ , \ *imagetype*\ , \ *installp_bundle*\ , \ *installto*\ , \ *isdeletable*\ , \ *kerneldir*\ , \ *kernelver*\ , \ *kitcomponents*\ , \ *krpmver*\ , \ *lpp_source*\ , \ *mksysb*\ , \ *netdrivers*\ , \ *nimmethod*\ , \ *nimtype*\ , \ *nodebootif*\ , \ *osarch*\ , \ *osdistroname*\ , \ *osname*\ , \ *osupdatename*\ , \ *osvers*\ , \ *otherifce*\ , \ *otherpkgdir*\ , \ *otherpkglist*\ , \ *otherpkgs*\ , \ *paging*\ , \ *partitionfile*\ , \ *permission*\ , \ *pkgdir*\ , \ *pkglist*\ , \ *postbootscripts*\ , \ *postinstall*\ , \ *postscripts*\ , \ *profile*\ , \ *provmethod*\ , \ *resolv_conf*\ , \ *root*\ , \ *rootfstype*\ , \ *rootimgdir*\ , \ *script*\ , \ *serverrole*\ , \ *shared_home*\ , \ *shared_root*\ , \ *spot*\ , \ *synclists*\ , \ *template*\ , \ *tmp*\ , \ *usercomment*\ , \ *winpepath*\ 


***********
DESCRIPTION
***********


Logical objects of this type are stored in the xCAT database in one or more tables.  Use the following commands
to manipulate the objects: \ **mkdef**\ , \ **chdef**\ , \ **lsdef**\ , and \ **rmdef**\ .  These commands will take care of
knowing which tables the object attributes should be stored in.  The attribute list below shows, in
parentheses, what tables each attribute is stored in.


*******************
osimage Attributes:
*******************



\ **addkcmdline**\  (linuximage.addkcmdline)
 
 User specified arguments to be passed to the kernel.  The user arguments are appended to xCAT.s default kernel arguments. For the kernel options need to be persistent after installation, specify them with prefix "R::".  This attribute is ignored if linuximage.boottarget is set.
 


\ **boottarget**\  (linuximage.boottarget)
 
 The name of the boottarget definition.  When this attribute is set, xCAT will use the kernel, initrd and kernel params defined in the boottarget definition instead of the default.
 


\ **bosinst_data**\  (nimimage.bosinst_data)
 
 The name of a NIM bosinst_data resource.
 


\ **cfmdir**\  (osimage.cfmdir)
 
 CFM directory name for PCM. Set to /install/osimages/<osimage name>/cfmdir by PCM.
 


\ **configdump**\  (nimimage.configdump)
 
 Specifies the type of system dump to be collected. The values are selective, full, and none.  The default is selective.
 


\ **crashkernelsize**\  (linuximage.crashkernelsize)
 
 the size that assigned to the kdump kernel. If the kernel size is not set, 256M will be the default value.
 


\ **description**\  (osimage.description)
 
 OS Image Description
 


\ **driverupdatesrc**\  (linuximage.driverupdatesrc)
 
 The source of the drivers which need to be loaded during the boot. Two types of driver update source are supported: Driver update disk and Driver rpm package. The value for this attribute should be comma separated sources. Each source should be the format tab:full_path_of_source_file. The tab keyword can be: dud (for Driver update disk) and rpm (for driver rpm). If missing the tab, the rpm format is the default. e.g. dud:/install/dud/dd.img,rpm:/install/rpm/d.rpm
 


\ **dump**\  (linuximage.dump, nimimage.dump)
 
 The NFS directory to hold the Linux kernel dump file (vmcore) when the node with this image crashes, its format is "nfs://<nfs_server_ip>/<kdump_path>". If you want to use the node's "xcatmaster" (its SN or MN), <nfs_server_ip> can be left blank. For example, "nfs:///<kdump_path>" means the NFS directory to hold the kernel dump file is on the node's SN, or MN if there's no SN.
 
 or
 
 The name of the NIM dump resource.
 


\ **exlist**\  (linuximage.exlist)
 
 The fully qualified name of the file that stores the file names and directory names that will be excluded from the image during packimage command.  It is used for diskless image only.
 


\ **fb_script**\  (nimimage.fb_script)
 
 The name of a NIM fb_script resource.
 


\ **groups**\  (osimage.groups)
 
 A comma-delimited list of image groups of which this image is a member.  Image groups can be used in the litefile and litetree table instead of a single image name. Group names are arbitrary.
 


\ **home**\  (nimimage.home)
 
 The name of the NIM home resource.
 


\ **image_data**\  (nimimage.image_data)
 
 The name of a NIM image_data resource.
 


\ **imagename**\  (osimage.imagename)
 
 The name of this xCAT OS image definition.
 


\ **imagetype**\  (osimage.imagetype)
 
 The type of operating system image this definition represents (linux,AIX).
 


\ **installp_bundle**\  (nimimage.installp_bundle)
 
 One or more comma separated NIM installp_bundle resources.
 


\ **installto**\  (winimage.installto)
 
 The disk and partition that the Windows will be deployed to. The valid format is <disk>:<partition>. If not set, default value is 0:1 for bios boot mode(legacy) and 0:3 for uefi boot mode; If setting to 1, it means 1:1 for bios boot and 1:3 for uefi boot
 


\ **isdeletable**\  (osimage.isdeletable)
 
 A flag to indicate whether this image profile can be deleted.  This attribute is only used by PCM.
 


\ **kerneldir**\  (linuximage.kerneldir)
 
 The directory name where the 3rd-party kernel is stored. It is used for diskless image only.
 


\ **kernelver**\  (linuximage.kernelver)
 
 The version of linux kernel used in the linux image. If the kernel version is not set, the default kernel in rootimgdir will be used
 


\ **kitcomponents**\  (osimage.kitcomponents)
 
 List of Kit Component IDs assigned to this OS Image definition.
 


\ **krpmver**\  (linuximage.krpmver)
 
 The rpm version of kernel packages (for SLES only). If it is not set, the default rpm version of kernel packages will be used.
 


\ **lpp_source**\  (nimimage.lpp_source)
 
 The name of the NIM lpp_source resource.
 


\ **mksysb**\  (nimimage.mksysb)
 
 The name of a NIM mksysb resource.
 


\ **netdrivers**\  (linuximage.netdrivers)
 
 The ethernet device drivers of the nodes which will use this linux image, at least the device driver for the nodes' installnic should be included
 


\ **nimmethod**\  (nimimage.nimmethod)
 
 The NIM install method to use, (ex. rte, mksysb).
 


\ **nimtype**\  (nimimage.nimtype)
 
 The NIM client type- standalone, diskless, or dataless.
 


\ **nodebootif**\  (linuximage.nodebootif)
 
 The network interface the stateless/statelite node will boot over (e.g. eth0)
 


\ **osarch**\  (osimage.osarch)
 
 The hardware architecture of this node.  Valid values: x86_64, ppc64, x86, ia64.
 


\ **osdistroname**\  (osimage.osdistroname)
 
 The name of the OS distro definition.  This attribute can be used to specify which OS distro to use, instead of using the osname,osvers,and osarch attributes. For \*kit commands,  the attribute will be used to read the osdistro table for the osname, osvers, and osarch attributes. If defined, the osname, osvers, and osarch attributes defined in the osimage table will be ignored.
 


\ **osname**\  (osimage.osname)
 
 Operating system name- AIX or Linux.
 


\ **osupdatename**\  (osimage.osupdatename)
 
 A comma-separated list of OS distro updates to apply to this osimage.
 


\ **osvers**\  (osimage.osvers)
 
 The Linux operating system deployed on this node.  Valid values:  rhels\*,rhelc\*, rhas\*,centos\*,SL\*, fedora\*, sles\* (where \* is the version #).
 


\ **otherifce**\  (linuximage.otherifce)
 
 Other network interfaces (e.g. eth1) in the image that should be configured via DHCP
 


\ **otherpkgdir**\  (linuximage.otherpkgdir)
 
 The base directory where the non-distro packages are stored. Only 1 local directory supported at present.
 


\ **otherpkglist**\  (linuximage.otherpkglist)
 
 The fully qualified name of the file that stores non-distro package lists that will be included in the image. It could be set to multiple paths. The multiple paths must be separated by ",".
 


\ **otherpkgs**\  (nimimage.otherpkgs)
 
 One or more comma separated installp or rpm packages.  The rpm packages must have a prefix of 'R:', (ex. R:foo.rpm)
 


\ **paging**\  (nimimage.paging)
 
 The name of the NIM paging resource.
 


\ **partitionfile**\  (linuximage.partitionfile, winimage.partitionfile)
 
 Only available for diskful osimages and statelite osimages(localdisk enabled). The full path of the partition file or the script to generate the partition file. The valid value includes:
                 "<the absolute path of the parititon file>": For diskful osimages, the partition file contains the partition definition that will be inserted directly into the template file for os installation. The syntax and format of the partition file should confirm to the corresponding OS installer of the Linux distributions(e.g. kickstart for RedHat, autoyast for SLES, pressed for Ubuntu). For statelite osimages, when the localdisk is enabled, the partition file with specific syntax and format includes the partition scheme of the local disk, please refer to the statelite documentation for details.
                 "s:<the absolute path of the partition script>": a shell script to generate the partition file "/tmp/partitionfile" inside the installer before the installation start.
                 "d:<the absolute path of the disk name file>": only available for ubuntu osimages, includes the name(s) of the disks to partition in traditional, non-devfs format(e.g, /dev/sdx, not e.g. /dev/discs/disc0/disc), and be delimited with space. All the disks involved in the partition file should be specified.
                 "s:d:<the absolute path of the disk script>": only available for ubuntu osimages, a script to generate the disk name file "/tmp/xcat.install_disk" inside the debian installer. This script is run in the "pressed/early_command" section.
                 "c:<the absolute path of the additional pressed config file>": only availbe for ubuntu osimages, contains the additional pressed entries in "d-i ..." form. This can be used to specify some additional preseed options to support RAID or LVM in Ubuntu.
                 "s:c:<the absolute path of the additional pressed config script>": only available for ubuntu osimages, runs in pressed/early_command and set the preseed values with "debconf-set". The multiple values should be delimited with comma ","
 
 or
 
 The path of partition configuration file. Since the partition configuration for bios boot mode and uefi boot mode are different, this configuration file can include both configurations if you need to support both bios and uefi mode. Either way, you must specify the boot mode in the configuration. Example of partition configuration file: [BIOS]xxxxxxx[UEFI]yyyyyyy. To simplify the setting, you also can set installto in partitionfile with section like [INSTALLTO]0:1
 


\ **permission**\  (linuximage.permission)
 
 The mount permission of /.statelite directory is used, its default value is 755
 


\ **pkgdir**\  (linuximage.pkgdir)
 
 The name of the directory where the distro packages are stored. It could be set to multiple paths. The multiple paths must be separated by ",". The first path in the value of osimage.pkgdir must be the OS base pkg dir path, such as pkgdir=/install/rhels6.2/x86_64,/install/updates . In the os base pkg path, there are default repository data. And in the other pkg path(s), the users should make sure there are repository data. If not, use "createrepo" command to create them. For ubuntu, multiple mirrors can be specified in the pkgdir attribute, the mirrors must be prefixed by the protocol(http/ssh) and delimited with "," between each other.
 


\ **pkglist**\  (linuximage.pkglist)
 
 The fully qualified name of the file that stores the distro  packages list that will be included in the image. Make sure that if the pkgs in the pkglist have dependency pkgs, the dependency pkgs should be found in one of the pkgdir
 


\ **postbootscripts**\  (osimage.postbootscripts)
 
 Comma separated list of scripts that should be run on this after diskful installation or diskless boot. On AIX these scripts are run during the processing of /etc/inittab.  On Linux they are run at the init.d time. xCAT automatically adds the scripts in the xcatdefaults.postbootscripts attribute to run first in the list. See the site table runbootscripts attribute.
 


\ **postinstall**\  (linuximage.postinstall)
 
 Supported in diskless image only. The fully qualified name of the scripts running in non-chroot mode after the package installation but before initrd generation during genimage. If multiple scripts are specified, they should be seperated with comma ",". A set of osimage attributes are exported as the environment variables to be used in the postinstall scripts:
 
 
 .. code-block:: perl
 
        IMG_ARCH(The architecture of the osimage, such as "ppc64le","x86_64"), 
        IMG_NAME(The name of the osimage, such as "rhels7.3-ppc64le-netboot-compute"), 
        IMG_OSVER(The os release of the osimage, such as "rhels7.3","sles11.4"), 
        IMG_KERNELVERSION(the "kernelver" attribute of the osimage),
        IMG_PROFILE(the profile of the osimage, such as "service","compute"), 
        IMG_PKGLIST(the "pkglist" attribute of the osimage), 
        IMG_PKGDIR(the "pkgdir" attribute of the osimage), 
        IMG_OTHERPKGLIST(the "otherpkglist" attribute of the osimage), 
        IMG_OTHERPKGDIR(the "otherpkgdir" attribute of the osimage), 
        IMG_ROOTIMGDIR(the "rootimgdir" attribute of the osimage)
 
 


\ **postscripts**\  (osimage.postscripts)
 
 Comma separated list of scripts that should be run on this image after diskful installation or diskless boot. For installation of RedHat, CentOS, Fedora, the scripts will be run before the reboot. For installation of SLES, the scripts will be run after the reboot but before the init.d process. For diskless deployment, the scripts will be run at the init.d time, and xCAT will automatically add the list of scripts from the postbootscripts attribute to run after postscripts list. For installation of AIX, the scripts will run after the reboot and acts the same as the postbootscripts attribute.  For AIX, use the postbootscripts attribute. See the site table runbootscripts attribute.
 


\ **profile**\  (osimage.profile)
 
 The node usage category. For example compute, service.
 


\ **provmethod**\  (osimage.provmethod)
 
 The provisioning method for node deployment. The valid values are install, netboot,statelite,boottarget,dualboot,sysclone. If boottarget is set, you must set linuximage.boottarget to the name of the boottarget definition. It is not used by AIX.
 


\ **resolv_conf**\  (nimimage.resolv_conf)
 
 The name of the NIM resolv_conf resource.
 


\ **root**\  (nimimage.root)
 
 The name of the NIM root resource.
 


\ **rootfstype**\  (osimage.rootfstype)
 
 The filesystem type for the rootfs is used when the provmethod is statelite. The valid values are nfs or ramdisk. The default value is nfs
 


\ **rootimgdir**\  (linuximage.rootimgdir)
 
 The directory name where the image is stored.  It is generally used for diskless image. it also can be used in sysclone environment to specify where the image captured from golden client is stored. in sysclone environment, rootimgdir is generally assigned to some default value by xcat, but you can specify your own store directory. just one thing need to be noticed, wherever you save the image, the name of last level directory must be the name of image. for example, if your image name is testimage and you want to save this image under home directoy, rootimgdir should be assigned to value /home/testimage/
 


\ **script**\  (nimimage.script)
 
 The name of a NIM script resource.
 


\ **serverrole**\  (osimage.serverrole)
 
 The role of the server created by this osimage.  Default roles: mgtnode, servicenode, compute, login, storage, utility.
 


\ **shared_home**\  (nimimage.shared_home)
 
 The name of the NIM shared_home resource.
 


\ **shared_root**\  (nimimage.shared_root)
 
 A shared_root resource represents a directory that can be used as a / (root) directory by one or more diskless clients.
 


\ **spot**\  (nimimage.spot)
 
 The name of the NIM SPOT resource.
 


\ **synclists**\  (osimage.synclists)
 
 The fully qualified name of a file containing a list of files to synchronize on the nodes. Can be a comma separated list of multiple synclist files. The synclist generated by PCM named /install/osimages/<imagename>/synclist.cfm is reserved for use only by PCM and should not be edited by the admin.
 


\ **template**\  (linuximage.template, winimage.template)
 
 The fully qualified name of the template file that will be used to create the OS installer configuration file for stateful installations (e.g.  kickstart for RedHat, autoyast for SLES).
 
 or
 
 The fully qualified name of the template file that is used to create the windows unattend.xml file for diskful installation.
 


\ **tmp**\  (nimimage.tmp)
 
 The name of the NIM tmp resource.
 


\ **usercomment**\  (linuximage.comments, nimimage.comments)
 
 Any user-written notes.
 
 or
 
 Any user-provided notes.
 


\ **winpepath**\  (winimage.winpepath)
 
 The path of winpe which will be used to boot this image. If the real path is /tftpboot/winboot/winpe1/, the value for winpepath should be set to winboot/winpe1
 



********
SEE ALSO
********


\ **mkdef(1)**\ , \ **chdef(1)**\ , \ **lsdef(1)**\ , \ **rmdef(1)**\ 

