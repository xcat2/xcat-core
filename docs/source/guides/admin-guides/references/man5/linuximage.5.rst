
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
 
 The name of the directory where the distro packages are stored. It could be set multiple paths.The multiple paths must be seperated by ",". The first path in the value of osimage.pkgdir must be the OS base pkg dir path, such as pkgdir=/install/rhels6.2/x86_64,/install/updates . In the os base pkg path, there are default repository data. And in the other pkg path(s), the users should make sure there are repository data. If not, use "createrepo" command to create them. For ubuntu, multiple mirrors can be specified in the pkgdir attribute, the mirrors must be prefixed by the protocol(http/ssh) and delimited with "," between each other.
 


\ **otherpkglist**\ 
 
 The fully qualified name of the file that stores non-distro package lists that will be included in the image. It could be set multiple paths.The multiple paths must be seperated by ",".
 


\ **otherpkgdir**\ 
 
 The base directory where the non-distro packages are stored. Only 1 local directory supported at present.
 


\ **exlist**\ 
 
 The fully qualified name of the file that stores the file names and directory names that will be excluded from the image during packimage command.  It is used for diskless image only.
 


\ **postinstall**\ 
 
 The fully qualified name of the script file that will be run at the end of the genimage command. It could be set multiple paths.The multiple paths must be seperated by ",". It is used for diskless image only.
 


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
 
 The path of the configuration file which will be used to partition the disk for the node. For stateful osimages,two types of files are supported: "<partition file absolute path>" which contains a partitioning definition that will be inserted directly into the generated autoinst configuration file and must be formatted for the corresponding OS installer (e.g. kickstart for RedHat, autoyast for SLES, pressed for Ubuntu).  "s:<partitioning script absolute path>" which specifies a shell script that will be run from the OS installer configuration file %pre section;  the script must write the correct partitioning definition into the file /tmp/partitionfile on the node which will be included into the configuration file during the install process. For statelite osimages, partitionfile should specify "<partition file absolute path>";  see the xCAT Statelite documentation for the xCAT defined format of this configuration file.For Ubuntu, besides  "<partition file absolute path>" or "s:<partitioning script absolute path>", the disk name(s) to partition must be specified in traditional, non-devfs format, delimited with space,  it can be specified in 2 forms: "d:<the absolute path of the disk name file>" which contains the disk name(s) to partition and "s:d:<the absolute path of the disk script>" which runs in pressed/early_command and writes the disk names into the "/tmp/install_disk" . To support other specific partition methods such as RAID or LVM in Ubuntu, some additional preseed values should be specified, these values can be specified with "c:<the absolute path of the additional pressed config file>" which contains the additional pressed entries in "d-i ..." form and "s:c:<the absolute path of the additional pressed config script>" which runs in pressed/early_command and set the preseed values with "debconf-set". The multiple values should be delimited with comma ","
 


\ **driverupdatesrc**\ 
 
 The source of the drivers which need to be loaded during the boot. Two types of driver update source are supported: Driver update disk and Driver rpm package. The value for this attribute should be comma separated sources. Each source should be the format tab:full_path_of_srouce_file. The tab keyword can be: dud (for Driver update disk) and rpm (for driver rpm). If missing the tab, the rpm format is the default. e.g. dud:/install/dud/dd.img,rpm:/install/rpm/d.rpm
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

