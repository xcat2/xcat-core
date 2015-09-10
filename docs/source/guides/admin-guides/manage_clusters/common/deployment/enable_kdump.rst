Enable Kdump Over Ethernet
==========================

Overview
--------

kdump is an advanced crash dumping mechanism. When enabled, the system is booted from the context of another kernel. This second kernel reserves a small amount of memory, and its only purpose is to capture the core dump image in case the system crashes. Being able to analyze the core dump helps significantly to determine the exact cause of the system failure.


xCAT Interface
--------------

The pkglist, exclude and postinstall files location and name can be obtained by running the following command: ::

    lsdef -t osimage <osimage name>

Here is an example: ::

    lsdef -t osimage rhels7.1-ppc64le-netboot-compute
    Object name: rhels7.1-ppc64le-netboot-compute
    exlist=/opt/xcat/share/xcat/netboot/rh/compute.rhels7.ppc64le.exlist
    imagetype=linux
    osarch=ppc64le
    osdistroname=rhels7.1-ppc64le
    osname=Linux
    osvers=rhels7.1
    otherpkgdir=/install/post/otherpkgs/rhels7.1/ppc64le
    permission=755
    pkgdir=/install/rhels7.1/ppc64le
    pkglist=/opt/xcat/share/xcat/netboot/rh/compute.rhels7.ppc64le.pkglist
    postinstall=/opt/xcat/share/xcat/netboot/rh/compute.rhels7.ppc64le.postinstall
    profile=compute
    provmethod=netboot
    rootimgdir=/install/netboot/rhels7.1/ppc64le/compute

In above example, pkglist file is /opt/xcat/share/xcat/netboot/rh/compute.rhels7.ppc64le.pkglist, exclude files is in /opt/xcat/share/xcat/netboot/rh/compute.rhels7.ppc64le.exlist, and postinstall file is /opt/xcat/share/xcat/netboot/rh/compute.rhels7.ppc64le.postinstall.

Setup pkglist
-------------

Before setting up kdump,the approprite rpms should be added to the pkglist file.Here is the rpm packages list which needs to be added to pkglist file for kdump for different OS. 

* **[RHEL]** ::
    
    kexec-tools
    crash

* **[SLES11]** ::

    kdump
    kexec-tools
    makedumpfile

* **[SLES10]** ::

    kernel-kdump
    kexec-tools
    kdump
    makedumpfile

* **[Ubuntu]** ::

    <TODO>

The exclude file
----------------

The base diskless image excludes the /boot directory, but it is required for kdump. Update the exlist file and remove the entry for /boot. Then run the packimage or liteimg command to update your image with the changes.

<TODO exclude files list>

The postinstall file
--------------------

The kdump will create a new initrd which used in the dumping stage. The /tmp or /var/tmp directory will be used as the temporary directory. These 2 directory only are allocated 10M space by default. You need to enlarge it to 200M. Modify the postinstall file to increase /tmp space.

* **[RHELS]** ::

    tmpfs   /var/tmp    tmpfs   defaults,size=200m   0 2

* **[SLES10]** ::
 
    tmpfs   /var/tmp    tmpfs   defaults,size=200m   0 2

* **[SLES11]** ::

    tmpfs   /tmp    tmpfs   defaults,size=200m       0 2

* **[Ubuntu]** ::

    <TODO>

The dump attribute
------------------

In order to support kdump, the dump attribute was added into linuximage table, which is used to define the remote path where the crash information should be dumped to. Use the chdef command to change the image's dump attribute using the URI format. ::

    chdef -t osimage <image name> dump=nfs://<nfs_server_ip>/<kdump_path>

The <nfs_server_ip> can be excluded if the destination NFS server is the service or management node. ::

    chdef -t osimage <image name> dump=nfs:///<kdump_path>

The crashkernelsize attribute
-----------------------------

For system x machine, on sles10 set the crashkernelsize attribute like this: ::

    chdef -t osimage <image name> crashkernelsize=<size>M@16M

On sles11 and rhels6 set the crashkernelsize attribute like this: ::

    chdef -t osimage <image name> crashkernelsize=<size>M

Where <size> recommended value is 256. For more information about the size can refer to the following information:
    `<https://access.redhat.com/knowledge/docs/en-US/Red_Hat_Enterprise_Linux/5/html/Deployment_Guide/ch-kdump.html#s2-kdump-configuration-cli>`_.  
    
    `<http://www.novell.com/support/kb/doc.php?id=3374462>`_.  
    
    `<https://access.redhat.com/knowledge/docs/en-US/Red_Hat_Enterprise_Linux/6/html/Deployment_Guide/s2-kdump-configuration-cli.html>`_.  
    
For system p machine, set the crashkernelsize attribute to this: ::

    chdef -t osimage <image name> crashkernelsize=<size>@32M

Where <size> recommended value is 256, more information can refer the kdump document for the system x.

When your node starts, and you get a kdump start error like this: ::

    Your running kernel is using more than 70% of the amount of space you reserved for kdump, you should consider increasing your crashkernel

You should modify this attribute using this chdef command: ::

    chdef -t osimage <image name> crashkernelsize=512M@32M

If 512M@32M is not large enough, you should change the crashkernelsize larger like 1024M until the error message disappear.

The enablekdump postscript
--------------------------

This postscript enablekdump is used to start the kdump service when the node is booting up. Add it to your nodes list of postscripts by running this command: ::

    chdef -t node <node range> -p postscripts=enablekdump


Notes
-----

Currently, only NFS is supported for the setup of kdump. 

If the dump attribute is not set, the kdump service will not be enabled. 

Please make sure the NFS remote path(nfs://<nfs_server_ip>/<kdump_path>) is exported and it is read-writeable to the node where kdump service is enabled.

How to trigger kernel panic on Linux
------------------------------------

Normally, kernel panic() will trigger booting into capture kernel. Once the kernel panic is triggered, the node will reboot into the capture kernel, and a kernel dump (vmcore) will be automatically saved to the directory on the specified NFS server (<nfs_server_ip>).

#. For RHESL6 the directory is <kdump_path>/var/crash/<node_ip>-<time>/ 
	
#. For SLES11 the directory is <kdump_path>/<node hostname>/<date>

#. For SLES10 the directory is <kdump_path>/<node hostname>
	
For RHELS6 testing purposes, you can simulate the trigger through /proc interface: ::
	
    echo c > /proc/sysrq-trigger
	
For SLES11.1 testing, you can use the following commands: ::

    echo 1 > /proc/sys/kernel/sysrq
    echo c > /proc/sysrq-trigger

This will force the Linux kernel to crash, and the address-YYYY-MM-DD-HH:MM:SS/vmcore file will be copied to the location you have selected on the specified NFS server directory. 
	
Dump Analysis
-------------

Once the system has returned from recovering the crash, you may wish to analyze the kernel dump file using the crash tool. 

  1.Locate the recent vmcore dump file.

  2.Locate the kernel file for the crash server(the kernel is under /tftpboot/xcat/netboot/<OS name="">/<ARCH>/<profile>/kernel on management node).

  3.Once you have located a vmcore dump file and kernel file, call crash: ::

    crash <vmcore_dump_file> <kernel_file>

If crash cannot find any files under /usr/lib/debug? Make sure you have the kernel-debuginfo package installed.

For more information about the dump analysis you can refer the following documents:

`<http://docs.redhat.com/docs/en-US/Red_Hat_Enterprise_Linux/5/html/Deployment_Guide/s1-kdump-crash.html RHEL document>`_

`<http://www.novell.com/support/kb/doc.php?id=3374462 SLES document>`_


