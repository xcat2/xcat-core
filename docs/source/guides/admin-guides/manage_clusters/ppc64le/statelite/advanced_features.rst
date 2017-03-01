Advanced features
=================

Both directory and its child items coexist in litefile table
------------------------------------------------------------

As described in the above chapters, we can add the files/directories to litefile table. Sometimes, it is necessary to put one directory and also its child item(s) into the litefile table. Due to the implementation of the statelite on Linux, some scenarios works, but some doesn't work.

Here are some examples of both directory and its child items coexisting:

    Both the parent directory and the child file coexist: ::

     "ALL","/root/testblank/",,,
     "ALL","/root/testblank/tempfschild","tempfs",,

    One more complex example: ::

     "ALL","/root/",,,
     "ALL","/root/testblank/tempfschild","tempfs",,

    Another more complex example, but we don't intend to support such one scenario: ::

     "ALL","/root/",,,
     "ALL","/root/testblank/",,,
     "ALL","/root/testblank/tempfschild","tempfs",,

For example, in scenario 1, the parent is ``/root/testblank/``, and the child is ``/root/testblank/tempfschild``.
In scenario 2, the parent is ``/root/``, and the child is ``/root/testblank/tempfschild``.

In order to describe the hierarchy scenarios we can use , ``P`` to denote parent, and ``C`` to denote child.

+--------------+-----------------------------------------------------+-------------------------------------------------+
| Option       | Example                                             | Remarks                                         |
+==============+=====================================================+=================================================+
| P:tmpfs      | "ALL","/root/testblank/",,,                         | Both the parent and the child are mounted to    |
|              | "ALL","/root/testblanktempfschild","tempfs",,       | tmpfs on the booted node following their        |
|              |                                                     | respective options. Only the parent are mounted |
|              |                                                     | to the local file system.                       |
+--------------+-----------------------------------------------------+-------------------------------------------------+
| P:tmpfs      | "ALL","/root/testblank/",,,                         | Both parent and child are mounted to tmpfs      |
| C:persistent | "ALL","/root/testblank/testpersfile","persistent",, | on the booted node following their respective   |
|              |                                                     | options. Only the parent is mounted to the local| 
|              |                                                     | file                                            | 
+--------------+-----------------------------------------------------+-------------------------------------------------+
| P:persistent | "ALL","/root/testblank/","persistent",,             | Not permitted now. But plan to support it.      |
| C:tmpfs      | "ALL","/root/testblank/tempfschild",,,              |                                                 |
+--------------+-----------------------------------------------------+-------------------------------------------------+
| P:persistent | "ALL","/root/testblank/","persistent",,             | Both parent and child are mounted to tmpfs      |
| C:persistent | "ALL","/root/testblank/testpersfile","persistent",, | on the booted node following their respective   |
|              |                                                     | options. Only the parent is mounted to local    |
|              |                                                     | file system.                                    |
+--------------+-----------------------------------------------------+-------------------------------------------------+
| P:ro C:any   |                                                     | Not permitted                                   |
+--------------+-----------------------------------------------------+-------------------------------------------------+
| P:tmpfs C:ro |                                                     | Both parent and child are mounted to tmpfs      |
|              |                                                     | on the booted node following their respective   |
|              |                                                     | options. Only the parent is mounted to local    |
|              |                                                     | file system.                                    |
+--------------+-----------------------------------------------------+-------------------------------------------------+
| P:tmpfs      |                                                     | Both parent and child are mounted to tmpfs      |
| C:con        |                                                     | on the booted node following their respective   |
|              |                                                     | options. Only the parent is mounted to local    |
|              |                                                     | file system.                                    |
+--------------+-----------------------------------------------------+-------------------------------------------------+
| P:link       | "ALL","/root/testlink/","link",,                    | Both parent and child are created in tmpfs      |
| C:link       | "ALL","/root/testlink/testlinkchild","link",,       | on the booted node following their respective   |
|              |                                                     | options; there's only one symbolic link of      |
|              |                                                     | the parent is created in the local file system. |
+--------------+-----------------------------------------------------+-------------------------------------------------+
| P: link C:   | "ALL","/root/testlinkpers/","link",,                | Both parent and child are created in tmpfs      |
| link,        | "ALL","/root/testlink/testlinkchild",,              | on the booted node following their respective   |
| persistent   | "link,persistent"                                   | options; there's only one symbolic link of      |
|              |                                                     | the parent is created in the local file system. |
+--------------+-----------------------------------------------------+-------------------------------------------------+
| P:link,      | "ALL","/root/testlinkpers/","link,persistent",,     | NOT permitted                                   |
|   persistent |                                                     |                                                 |
| C: link      | "ALL","/root/testlink/testlinkchild","link"         |                                                 |
+--------------+-----------------------------------------------------+-------------------------------------------------+
| P:link,      | "ALL","/root/testlinkpers/","link,persistent",,     | Both parent and child are created in tmpfs      |
|   persistent | "ALL","/root/testlink                               | on the booted node following "link,persistent"  |
| C:link,      |                                                     | way; there's only one symbolic link of the      |
|   persistent |                                                     | parent is created in the local file system.     |
+--------------+-----------------------------------------------------+-------------------------------------------------+
| P:link       | "ALL","/root/testlink/","link",,                    | Both parent and child are created in tmpfs      |
| C:link,ro    | "ALL","/root/testlink/testlinkro","link,ro",,       | on the booted node, there's only one symbolic   |
|              |                                                     | link of the parent is created in the local      |
|              |                                                     | file system.                                    | 
+--------------+-----------------------------------------------------+-------------------------------------------------+
| P:link       | "ALL","/root/testlink/","link",,                    | Both parent and child are created in tmpfs      |
| C:link,con   | "ALL","/root/testlink/testlinkconchild","link,con",,| on the booted node, there's only one symbolic   |
|              |                                                     | link of the parent in the local file system.    |
+--------------+-----------------------------------------------------+-------------------------------------------------+
| P:link,      |                                                     | NOT Permitted                                   |
|   persistent |                                                     |                                                 |
| C:link,ro    |                                                     |                                                 |
+--------------+-----------------------------------------------------+-------------------------------------------------+
| P:link,      |                                                     | NOT Permitted                                   |
|   persistent |                                                     |                                                 |
| C:link,con   |                                                     |                                                 |
+--------------+-----------------------------------------------------+-------------------------------------------------+
| P:tmpfs      |                                                     | NOT Permitted                                   |
| C:link       |                                                     |                                                 |
+--------------+-----------------------------------------------------+-------------------------------------------------+
| P:link       |                                                     | NOT Permitted                                   |
| C:persistent |                                                     |                                                 |
+--------------+-----------------------------------------------------+-------------------------------------------------+ 

litetree table
--------------

The litetree table controls where the initial content of the files in the litefile table come from, and the long term content of the ``ro`` files. When a node boots up in statelite mode, it will by default copy all of its tmpfs files from the ``/.default`` directory of the root image, so there is not requirement to setup a litetree table. If you decide that you want some of the files pulled from different locations that are different per node, you can use this table.

See litetree man page for description of attributes.

For example, a user may have two directories with a different ``/etc/motd`` that should be used for nodes in two locations: ::

    10.0.0.1:/syncdirs/newyork-590Madison/rhels5.4/x86_64/compute/etc/motd
    10.0.0.1:/syncdirs/shanghai-11foo/rhels5.4/x86_64/compute/etc/motd

You can specify this in one row in the litetree table: ::

    1,,10.0.0.1:/syncdirs/$nodepos.room/$nodetype.os/$nodetype.arch/$nodetype.profile

When each statelite node boots, the variables in the litetree table will be substituted with the values for that node to locate the correct directory to use. Assuming that ``/etc/motd`` was specified in the litefile table, it will be searched for in all of the directories specified in the litetree table and found in this one.

You may also want to look by default into directories containing the node name first: ::

    $noderes.nfsserver:/syncdirs/$node

The litetree prioritizes where node files are found. The first field is the priority. The second field is the image name (ALL for all images) and the final field is the mount point.

Our example is as follows: ::

    1,,$noderes.nfsserver:/statelite/$node
    2,,cnfs:/gpfs/dallas/

The two directories ``/statelite/$node`` on the node's $noderes.nfsserver and the ``/gpfs/dallas`` on the node cnfs contain root tree structures that are sparsely populated with files that we want to place in those nodes. If files are not found in the first directory, it goes to the next directory. If none of the files can be found in the litetree hierarchy, then they are searched for in ``/.default`` on the local image.

Installing a new Kernel in the statelite image 
----------------------------------------------

Obtain you new kernel and kernel modules on the MN, for example here we have a new SLES kernel.

#. Copy the kernel into /boot : ::

    cp **vmlinux-2.6.32.10-0.5-ppc64**/boot

#. Copy the kernel modules into ``/lib/modules/<new kernel directory>`` ::

    /lib/modules # ls -al
    total 16
    drwxr-xr-x 4 root root 4096 Apr 19 10:39 .
    drwxr-xr-x 17 root root 4096 Apr 13 08:39 ..
    drwxr-xr-x 3 root root 4096 Apr 13 08:51 2.6.32.10-0.4-ppc64
    **drwxr-xr-x 4 root root 4096 Apr 19 10:12 2.6.32.10-0.5-ppc64**

#. Run genimage to update the statelite image with the new kernel ::

     genimage -k 2.6.32.10-0.5-ppc64 <osimage_name>

#. Then after a nodeset command and netbooti, shows the new kernel::

    uname -a

Enabling the localdisk Option
-----------------------------

``Note``: You can skip this section if not using the ``localdisk`` option in your litefile table.

Several things need to be done to enable the 'localdisk' support:

Define how to partition the local disk
``````````````````````````````````````

When a node is deployed, the local hard disk needs to be partitioned and formatted before it can be used. This section explains how provide a configuration file that tells xCAT to partition a local disk and make it ready to use for the directories listed in the litefile table with the ``localdisk`` option.

The configuration file needs to be specified in the ``partitionfile`` attribute of the osimage definition. The configuration file includes several parts:

    * Global parameters to control enabling or disabling the function
    * [disk] part to control the partitioning of the disk
    * [localspace] part to control which partition will be used to store the localdisk directories listed in the litefile table
    * [swapspace] part to control the enablement of the swap space for the node.

An example localdisk configuration file: ::

    enable=yes
    enablepart=no

    [disk]
    dev=/dev/sdb
    clear=yes
    parts=100M-200M,1G-2G

    [disk]
    dev=/dev/sda
    clear=yes
    parts=10,20,30

    [disk]
    dev=/dev/sdc
    clear=yes
    parts=10,20,30

    [localspace]
    dev=/dev/sda1
    fstype=ext3

    [swapspace]
    dev=/dev/sda2

The two global parameters ``enable`` and ``enablepart`` can be used to control the enabling/disabling of the functions:

    * enable: The localdisk feature only works when ``enable`` is set to *yes*. If it is set to *no*, the localdisk configuration will not be run.
    * enablepart: The partition action (refer to the ``[disk]`` section) will be run only when ``enablepart=yes``.

The ``[disk]`` section is used to configure how to partition a hard disk:

    * dev: The path of the device file.
    * clear: If set to ``yes`` it will clear all the existing partitions on this disk.
    * fstype: The file system type for the new created partitions. ``ext3`` is the default value if not set.
    * parts: A comma separated list of space ranges, one for each partition that will be created on the device. The valid format for each space range is ``<startpoint>-<endpoint>`` or ``<percentage of the disk>``. For example, you could set it to ``100M-10G`` or ``50``. If you set it to ``50``, that means 50% of the disk space will be assigned to that partition.

The ``[localspace]`` section is used to specify which partition will be used as local storage for the node.

    * dev: The path of the partition.
    * fstype: The file system type on the partition.

the ``[swapspace]`` section is used to configure the swap space for the statelite node.

    * dev: The path of the partition file which will be used as the swap space.

To enable the local disk capability, create the configuration file (for example in ``/install/custom``) and set the path in the partitionfile attribute for the osimage: ::

    chdef -t osimage partitionfile=/install/custom/cfglocaldisk

Now all nodes that use this osimage (i.e. have their provmethod attribute set to this osimage definition name), will have its local disk configured.

Configure the files in the litefile table
`````````````````````````````````````````

For the files/directories that you would like xCAT to store on the local disk, add an entry in the litefile table like this: ::

    "ALL","/tmp/","localdisk",,

``Note``: you do not need to specify the swap space in the litefile table. Just putting it in the partitionfile config file is enough.

Add an entry in policy table to permit the running of the ``getpartitioin`` command from the node ::

    chtab priority=7.1 policy.commands=getpartition policy.rule=allow

If Using the RAMdisk-based Image
````````````````````````````````

If you want to use the local disk option with a RAMdisk-based image, remember to follow the instructions in :doc:`Switch to the RAMdisk based solution <./provision_statelite>`.

If your reason for using a RAMdisk image is to avoid compute node runtime dependencies on the service node or management node, then the only entries you should have in the litefile table should be files/dirs that use the localdisk option.

Debugging techniques
--------------------

    When a node boots up in statelite mode, there is a script that runs called statelite that is in the root directory of ``$imageroot/etc/init.d/statelite``. This script is not run as part of the rc scripts, but as part of the pre-switch root environment. Thus, all the linking is done in this script. There is a ``set x`` near the top of the file. You can uncomment it and see what the script runs. You will then see lots of mkdirs and links on the console.

    You can also set the machine to shell. Just add the word ``shell`` on the end of the pxeboot file of the node in the append line. This will make the init script in the initramfs pause 3 times before doing a switch_root.

    When all the files are linked they are logged in ``/.statelite/statelite.log`` on the node. You can get into the node after it has booted and look in the ``/.statelite`` directory.

