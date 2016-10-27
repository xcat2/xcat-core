xCAT Cluster OS Running Type
============================

Whether a node is a physical server or a virtual machine, it needs to run an Operating System to support user applications. Generally, the OS is installed in the hard disk of the compute node. But xCAT also support the type that running OS in the RAM.

This section gives the pros and cons of each OS running type, and describes the cluster characteristics that will impact from each.

Stateful (diskful)
------------------

Traditional cluster with OS on each node's local disk.

* Main advantage

  This approach is familiar to most admins, and they typically have many years of experience with it.
        
* Main disadvantage

  Admin has to manage all of the individual OS copies, has to face the failure of hard disk. For certain application which requires all the compute nodes have exactly same state, this is also changeable for admin.
    

Stateless (diskless)
--------------------

Nodes boot from a RAMdisk OS image downloaded from the xCAT mgmt node or service node at boot time.

* Main advantage 

  Central management of OS image, but nodes are not tethered to the mgmt node or service node it booted from. Whenever you need a new OS for the node, just reboot the node.
        
* Main disadvantage

  You can't use a large image with many different applications in the image for varied users, because it uses too much of the node's memory to store the ramdisk.  (To mitigate this disadvantage, you can put your large application binaries and libraries in shared storage to reduce the ramdisk size. This requires some manual configuration of the image). 

   Each node can also have a local "scratch" disk for ``swap``, ``/tmp``, ``/var``, ``log`` files, dumps, etc.  The purpose of the scratch disk is to provide a location for files that are written to by the node that can become quite large or for files that you don't want to disappear when the node reboots.  There should be nothing put on the scratch disk that represents the node's "state", so that if the disk fails you can simply replace it and reboot the node. A scratch disk would typically be used for situations like: job scheduling preemption is required (which needs a lot of swap space), the applications write large temp files, or you want to keep gpfs log or trace files persistently. (As a partial alternative to using the scratch disk, customers can choose to put ``/tmp`` ``/var/tmp``, and log files (except GPFS logs files) in GPFS, but must be willing to accept the dependency on GPFS). This can be done by enabling the 'localdisk' support. For the details, refer to the section [TODO Enabling the localdisk Option].


OSimage Definition
------------------

The attribute **provmethod** is used to identify that the osimage is diskful or diskless: ::

    $ lsdef -t osimage rhels7.1-x86_64-install-compute -i provmethod
    Object name: rhels7.1-x86_64-install-compute
        provmethod=install

install:
    Diskful

netboot:
    Diskless

