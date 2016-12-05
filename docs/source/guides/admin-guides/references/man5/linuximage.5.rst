
############
linuximage.5
############

.. highlight:: perl


****
NAME
****


\ **linuximage**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **linuximage Attributes:**\   \ *imagename*\ , \ *template*\ , \ *boottarget*\ , \ *addkcmdline*\ , \ *pkglist*\ , \ *pkgdir*\ , \ *otherpkglist*\ , \ *otherpkgdir*\ , \ *exlist*\ , \ *postinstall*\ , \ *rootimgdir*\ , \ *kerneldir*\ , \ *nodebootif*\ , \ *otherifce*\ , \ *netdrivers*\ , \ *kernelver*\ , \ *krpmver*\ , \ *permission*\ , \ *dump*\ , \ *crashkernelsize*\ , \ *partitionfile*\ , \ *driverupdatesrc*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


Information about a Linux operating system image that can be used to deploy cluster nodes.


**********************
linuximage Attributes:
**********************



\ **imagename**\ 
 
 The name of this xCAT OS image definition.
 


\ **template**\ 
 
 The fully qualified name of the template file that will be used to create the OS installer configuration file for stateful installations (e.g.  kickstart for RedHat, autoyast for SLES).
 


\ **boottarget**\ 
 
 The name of the boottarget definition.  When this attribute is set, xCAT will use the kernel, initrd and kernel params defined in the boottarget definition instead of the default.
 


\ **addkcmdline**\ 
 
 User specified arguments to be passed to the kernel.  The user arguments are appended to xCAT.s default kernel arguments. For the kernel options need to be persistent after installation, specify them with prefix "R::".  This attribute is ignored if linuximage.boottarget is set.
 


\ **pkglist**\ 
 
 The fully qualified name of the file that stores the distro  packages list that will be included in the image. Make sure that if the pkgs in the pkglist have dependency pkgs, the dependency pkgs should be found in one of the pkgdir
 


\ **pkgdir**\ 
 
 The name of the directory where the distro packages are stored. It could be set to multiple paths. The multiple paths must be separated by ",". The first path in the value of osimage.pkgdir must be the OS base pkg dir path, such as pkgdir=/install/rhels6.2/x86_64,/install/updates . In the os base pkg path, there are default repository data. And in the other pkg path(s), the users should make sure there are repository data. If not, use "createrepo" command to create them. For ubuntu, multiple mirrors can be specified in the pkgdir attribute, the mirrors must be prefixed by the protocol(http/ssh) and delimited with "," between each other.
 


\ **otherpkglist**\ 
 
 The fully qualified name of the file that stores non-distro package lists that will be included in the image. It could be set to multiple paths. The multiple paths must be separated by ",".
 


\ **otherpkgdir**\ 
 
 The base directory where the non-distro packages are stored. Only 1 local directory supported at present.
 


\ **exlist**\ 
 
 The fully qualified name of the file that stores the file names and directory names that will be excluded from the image during packimage command.  It is used for diskless image only.
 


\ **postinstall**\ 
 
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
 
 


\ **rootimgdir**\ 
 
 The directory name where the image is stored.  It is generally used for diskless image. it also can be used in sysclone environment to specify where the image captured from golden client is stored. in sysclone environment, rootimgdir is generally assigned to some default value by xcat, but you can specify your own store directory. just one thing need to be noticed, wherever you save the image, the name of last level directory must be the name of image. for example, if your image name is testimage and you want to save this image under home directoy, rootimgdir should be assigned to value /home/testimage/
 


\ **kerneldir**\ 
 
 The directory name where the 3rd-party kernel is stored. It is used for diskless image only.
 


\ **nodebootif**\ 
 
 The network interface the stateless/statelite node will boot over (e.g. eth0)
 


\ **otherifce**\ 
 
 Other network interfaces (e.g. eth1) in the image that should be configured via DHCP
 


\ **netdrivers**\ 
 
 The ethernet device drivers of the nodes which will use this linux image, at least the device driver for the nodes' installnic should be included
 


\ **kernelver**\ 
 
 The version of linux kernel used in the linux image. If the kernel version is not set, the default kernel in rootimgdir will be used
 


\ **krpmver**\ 
 
 The rpm version of kernel packages (for SLES only). If it is not set, the default rpm version of kernel packages will be used.
 


\ **permission**\ 
 
 The mount permission of /.statelite directory is used, its default value is 755
 


\ **dump**\ 
 
 The NFS directory to hold the Linux kernel dump file (vmcore) when the node with this image crashes, its format is "nfs://<nfs_server_ip>/<kdump_path>". If you want to use the node's "xcatmaster" (its SN or MN), <nfs_server_ip> can be left blank. For example, "nfs:///<kdump_path>" means the NFS directory to hold the kernel dump file is on the node's SN, or MN if there's no SN.
 


\ **crashkernelsize**\ 
 
 the size that assigned to the kdump kernel. If the kernel size is not set, 256M will be the default value.
 


\ **partitionfile**\ 
 
 Only available for diskful osimages and statelite osimages(localdisk enabled). The full path of the partition file or the script to generate the partition file. The valid value includes:
                 "<the absolute path of the parititon file>": For diskful osimages, the partition file contains the partition definition that will be inserted directly into the template file for os installation. The syntax and format of the partition file should confirm to the corresponding OS installer of the Linux distributions(e.g. kickstart for RedHat, autoyast for SLES, pressed for Ubuntu). For statelite osimages, when the localdisk is enabled, the partition file with specific syntax and format includes the partition scheme of the local disk, please refer to the statelite documentation for details.
                 "s:<the absolute path of the partition script>": a shell script to generate the partition file "/tmp/partitionfile" inside the installer before the installation start.
                 "d:<the absolute path of the disk name file>": only available for ubuntu osimages, includes the name(s) of the disks to partition in traditional, non-devfs format(e.g, /dev/sdx, not e.g. /dev/discs/disc0/disc), and be delimited with space. All the disks involved in the partition file should be specified.
                 "s:d:<the absolute path of the disk script>": only available for ubuntu osimages, a script to generate the disk name file "/tmp/xcat.install_disk" inside the debian installer. This script is run in the "pressed/early_command" section.
                 "c:<the absolute path of the additional pressed config file>": only availbe for ubuntu osimages, contains the additional pressed entries in "d-i ..." form. This can be used to specify some additional preseed options to support RAID or LVM in Ubuntu.
                 "s:c:<the absolute path of the additional pressed config script>": only available for ubuntu osimages, runs in pressed/early_command and set the preseed values with "debconf-set". The multiple values should be delimited with comma ","
 


\ **driverupdatesrc**\ 
 
 The source of the drivers which need to be loaded during the boot. Two types of driver update source are supported: Driver update disk and Driver rpm package. The value for this attribute should be comma separated sources. Each source should be the format tab:full_path_of_source_file. The tab keyword can be: dud (for Driver update disk) and rpm (for driver rpm). If missing the tab, the rpm format is the default. e.g. dud:/install/dud/dd.img,rpm:/install/rpm/d.rpm
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

