Enable kdump Over Ethernet
==========================

Overview
--------

kdump is an feature of the Linux kernel that allows the system to be booted from the context of another kernel.  This second kernel reserves a small amount of memory and its only purpose is to capture the core dump in the event of a kernel crash.  The ability to analyze the core dump helps to determine causes of system failures.


xCAT Interface
--------------

The following attributes of an osimage should be modified to enable ``kdump``:

* pkglist
* exlist
* dump
* crashkernel
* crashkernelsize

Configure the ``pkglist`` file
------------------------------

The ``pkglist`` for the osimage needs to include the appropriate RPMs.  The following list of RPMs are provided as a sample, always refer to the Operating System specific documentataion to ensure the required packages are there for ``kdump`` support. 

* **For RHEL** ::
    
    kexec-tools
    crash

* **For SLES** ::

    kdump
    kexec-tools
    makedumpfile

* **For Ubuntu** ::

    <TODO>

Modify the ``exlist`` file
--------------------------

The default diskless image created by ``copycds`` excludes the ``/boot`` directory in the exclude list file, but this is required for ``kdump``.  

Update the ``exlist`` for the target osimage and remove the line ``/boot``: ::

   ./boot*  # <-- remove this line

Run ``packimage`` to update the diskless image with the changes.


The ``dump`` attribute 
----------------------

To support kernel dumps, the ``dump`` attribute **must** be set on the osimage definition.  If not set, kdump service will not be enabled.  The ``dump`` attribute defines the NFS remote oath where the crash information is to be stored. 

Use the ``chdef`` command to set a value of the ``dump`` attribute: ::

    chdef -t osimage <image name> dump=nfs://<nfs_server_ip>/<kdump_path>

If the NFS server is the Service Node or Management Node, the server can be left out: ::

    chdef -t osimage <image name> dump=nfs:///<kdump_path>

**Note:** Only NFS is currently supported as a storage location.

Notes
-----

Currently, only NFS is supported for the setup of kdump.

If the dump attribute is not set, the kdump service will not be enabled.

Make sure the NFS remote path(nfs://<nfs_server_ip>/<kdump_path>) is exported and it is read-writeable to the node where kdump service is enabled.


The ``crashkernelsize`` attribute
---------------------------------

To allow the Operating System to automatically reserve the appropriate amount of memory for the ``kdump`` kernel, set ``crashkernelsize=auto``. 

For setting specific sizes, use the following example: 

* For System X machines, set the ``crashkernelsize`` using this format: ::

    chdef -t osimage <image name> crashkernelsize=<size>M


* For System P machines, set the ``crashkernelsize`` using this format: :: 

    chdef -t osimage <image name> crashkernelsize=<size>@32M


* For OpenPower Systems (i.e. IBM Power System AC922), set the ``crashkernelsize`` using this format: ::
    
    chdef -t osimage <image name> crashkernelsize=<size>M

*where <size> is recommended to be at least 256.  For more about size, refer to the Operating System specific documentation describing kdump.*


The ``enablekdump`` postscript
------------------------------

xCAT provides a postscript ``enablekdump`` that can be added to the Nodes to automatically start the ``kdump`` service when the node boots.  Add to the nodes using the following command: :: 

    chdef -t node <node range> -p postscripts=enablekdump



Manually trigger a kernel panic on Linux
----------------------------------------

Normally, kernel panic() will trigger booting into capture kernel. Once the kernel panic is triggered, the node will reboot into the capture kernel, and a kernel dump (vmcore) will be automatically saved to the directory on the specified NFS server (``<nfs_server_ip>``).

Check your Operating System specific documentation for the path where the kernel dump is saved.  For example: 

    * For RHELS 6, check ``<kdump_path>/var/crash/<node_ip>-<time>/``
	
    * For SLES 11, check ``<kdump_path>/<node hostname>/<date>``

To trigger a dump, use the following commands: :: 	

    echo 1 > /proc/sys/kernel/sysrq
    echo c > /proc/sysrq-trigger

This will force the Linux kernel to crash, and the ``address-YYYY-MM-DD-HH:MM:SS/vmcore`` file should be copied to the location you set on the NFS server.
	
Dump Analysis
-------------

Once the system has returned from recovering the crash, you can analyze the kernel dump using the ``crash`` tool. 

  #. Locate the recent vmcore dump file.

  #. Locate the kernel file for the crash server.  
     The kernel is under ``/tftpboot/xcat/netboot/<OS name="">/<ARCH>/<profile>/kernel`` on the managenent node.

  #. Once you have located a vmcore dump file and kernel file, call ``crash``: :: 

        crash <vmcore_dump_file> <kernel_file>

**Note:** If ``crash`` cannot find any files, make sure you have the ``kernel-debuginfo`` package installed.

