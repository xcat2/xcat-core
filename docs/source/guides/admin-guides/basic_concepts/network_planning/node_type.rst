xCAT Cluster Node Types
=======================

This section describes 2 standard node types xCAT supports, gives the pros and cons of each, and describes the cluster characteristics that will result from each.

Stateful (diskfull)
-------------------

traditional cluster with OS on each node's local disk.

Main advantage
``````````````
this approach is familiar to most admins, and they typically have many years of experience with it
        
Main disadvantage
`````````````````
you have to manage all of the individual OS copies
    

Stateless(diskless)
-------------------

nodes boot from a RAMdisk OS image downloaded from the xCAT mgmt node or service node at boot time. (This option is not available on AIX).

Main advantage 
``````````````
central management of OS image, but nodes are not tethered to the mgmt node or service node it booted from
        
Main disadvantage
`````````````````
you can't use a large image with many different applications all in the image for varied users, because it uses too much of the node's memory to store the ramdisk.  (To mitigate this disadvantage, you can put your large application binaries and libraries in gpfs to reduce the ramdisk size. This requires some manual configuration of the image).

* Scratch disk:  
Each node can also have a local "scratch" disk for ``swap``, ``/tmp``, ``/var``, ``log`` files, dumps, etc.  The purpose of the scratch disk is to provide a location for files that are written to by the node that can become quite large or for files that you don't want to have disappear when the node reboots.  There should be nothing put on the scratch disk that represents the node's "state", so that if the disk fails you can simply replace it and reboot the node. A scratch disk would typically be used for situations like: job scheduling preemption is required (which needs a lot of swap space), the applications write large temp files, or you want to keep gpfs log or trace files persistently. (As a partial alternative to using the scratch disk, customers can choose to put ``/tmp`` ``/var/tmp``, and log files (except GPFS logs files) in GPFS, but must be willing to accept the dependency on GPFS).

* Statelite persistent files:  
xCAT supports layering some statelite persistent files/dirs on top of a ramdisk node.  The statelite persistent files are nfs mounted.  In this case, as little as possible should be in statelite persistent files, at least nothing that will cause the node to hang if the nfs mount goes away.

