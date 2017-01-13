
#########
copycds.8
#########

.. highlight:: perl


****
NAME
****


\ **copycds**\  - Copies Linux distributions and service levels from DVDs/ISOs to the xCAT /install directory.


********
SYNOPSIS
********


\ **copycds**\  [{\ **-n|-**\ **-name|-**\ **-osver**\ }=\ *distroname*\ ] [{\ **-a|-**\ **-arch**\ }=\ *architecture*\ ] [{\ **-p|-**\ **-path**\ }=\ *ospkgpath*\ ] [\ **-o | -**\ **-noosimage**\ ] [\ **-w | -**\ **-nonoverwrite**\ ] {\ *iso | device-path*\ } ...

\ **copycds**\  [\ **-i | -**\ **-inspection**\ ] {\ *iso | device-path*\ }

\ **copycds**\  [\ **-h | -**\ **-help**\ ]


***********
DESCRIPTION
***********


The \ **copycds**\  command copies all contents of Distribution DVDs/ISOs or Service Pack DVDs/ISOs to a destination directory. The destination directory can be specified by the \ **-p**\  option. If no path is specified, the default destination directory will be formed from the \ **installdir**\  site table attribute, distro name and architecture, for example: /install/rhels6.3/x86_64. The \ **copycds**\  command can copy from one or more ISO files, or the CD/DVD device path.

You can specify \ **-i**\  or \ **-**\ **-inspection**\  option to check whether the DVDs/ISOs can be recognized by xCAT. If recognized, the distribution name, architecture and the disc no (the disc sequence number of DVDs/ISOs in multi-disk distribution) of the DVD/ISO is displayed. If xCAT doesn't recognize the DVD/ISO, you must manually specify the distro name and architecture using the \ **-n**\  and \ **-a**\  options. This is sometimes the case for distros that have very recently been released, and the xCAT code hasn't been updated for it yet.

You can get xCAT to recognize new DVDs/ISOs by adding them to /opt/xcat/lib/perl/xCAT/data/discinfo.pm (the key of the hash is the first line of .discinfo) and reloading xcatd (\ **service xcatd reload**\ ).


*******
OPTIONS
*******



\ **-n|-**\ **-name|-**\ **-osver**\ =\ *distroname*\ 
 
 The linux distro name and version that the ISO/DVD contains.  Examples:  rhels6.3, sles11.2, fedora9.  Note the 's' in rhels6.3 which denotes the Server version of RHEL, which is typically used.
 


\ **-a|-**\ **-arch**\ =\ *architecture*\ 
 
 The architecture of the linux distro on the ISO/DVD.  Examples: x86, x86_64, ppc64, s390x.
 


\ **-p|-**\ **-path**\ =\ *ospkgpath*\ 
 
 The destination directory to which the contents of ISO/DVD will be copied. When this option is not specified, the default destination directory will be formed from the \ **installdir**\  site table attribute and the distro name and architecture, for example: /install/rhel6.3/x86_64. This option is only supported for distributions of sles, redhat and windows.
 


\ **-i|-**\ **-inspection**\ 
 
 Check whether xCAT can recognize the DVDs/ISOs in the argument list, but do not copy the disc. Displays the os distribution name, architecture and disc no of each recognized DVD/ISO. This option is only supported for distributions of sles, redhat and windows.
 


\ **-o|-**\ **-noosimage**\ 
 
 Do not create the default osimages based on the osdistro copied in. By default, \ **copycds**\  will create a set of osimages based on the osdistro.
 


\ **-w|-**\ **-nonoverwrite**\ 
 
 Complain and exit if the os disc has already been copied in. By default, \ **copycds**\  will overwrite the os disc already copied in.
 



************
RETURN VALUE
************


0: The command completed successfully. For the \ **-**\ **-inspection**\  option, the ISO/DVD have been recognized successfully

Nonzero: An Error has occurred. For the \ **-**\ **-inspection**\  option, the ISO/DVD cannot be recognized


********
EXAMPLES
********



1. To copy the RPMs from a set of ISOs that represent the DVDs of a distro:
 
 
 .. code-block:: perl
 
   copycds dvd1.iso dvd2.iso
 
 


2. To copy the RPMs from a physical DVD to /depot/kits/3 directory:
 
 
 .. code-block:: perl
 
   copycds -p /depot/kits/3 /dev/dvd
 
 


3. To copy the RPMs from a DVD ISO of a very recently released distro:
 
 
 .. code-block:: perl
 
   copycds -n rhels6.4 -a x86_64 dvd.iso
 
 


4. To check whether a DVD ISO can be recognized by xCAT and display the recognized disc info:
 
 
 .. code-block:: perl
 
   copycds -i /media/RHEL/6.2/RHEL6.2-20111117.0-Server-ppc64-DVD1.iso
 
 
 Output will be similar to:
 
 
 .. code-block:: perl
 
    OS Image:/media/RHEL/6.2/RHEL6.2-20111117.0-Server-ppc64-DVD1.iso
    DISTNAME:rhels6.2
    ARCH:ppc64
    DISCNO:1
 
 
 For the attributes that are not recognized, the value will be blank.
 


5. To copy the packages from a supplemental DVD ISO file:
 
 
 .. code-block:: perl
 
   copycds /isodir/RHEL6.5/RHEL6.5-Supplementary-20131114.2-Server-ppc64-DVD1.iso -n rhels6.5-supp
 
 
 Also, remember to add the new directory to your osimage definition:
 
 
 .. code-block:: perl
 
   chdef -t osimage myosimage -p pkgdir=/install/rhels6.5-supp/ppc64
 
 



********
SEE ALSO
********


nodeset(8)|nodeset.8, site(5)|site.5, nodetype(5)|nodetype.5

