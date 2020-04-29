.. _setup_localdisk_label:

Enabling the localdisk option
-----------------------------

.. note:: You can skip this section if not using the ``localdisk`` option in your ``litefile`` table.

Define how to partition the local disk
``````````````````````````````````````

When a node is deployed, the local hard disk needs to be partitioned and formatted before it can be used. This section explains how provide a configuration file that tells xCAT to partition a local disk and make it ready to use for the directories listed in the litefile table.

The configuration file needs to be specified in the ``partitionfile`` attribute of the osimage definition. The configuration file includes several sections:

    * Global parameters to control enabling or disabling the function
    * ``[disk]`` section to control the partitioning of the disk
    * ``[localspace]`` section to control which partition will be used to store the ``localdisk`` directories listed in the ``litefile`` table
    * ``[swapspace]`` section to control the enablement of the swap space for the node.

An example ``localdisk`` configuration file: ::

    enable=yes
    enablepart=no

    [disk]
    dev=/dev/sda
    clear=yes
    parts=10,20,30

    [disk]
    dev=/dev/sdb
    clear=yes
    parts=100M-200M,1G-2G

    [disk]
    dev=/dev/sdc
    ptype=gpt
    clear=yes
    parts=10,20,30

    [localspace]
    dev=/dev/sda1
    fstype=ext4

    [swapspace]
    dev=/dev/sda2

The two global parameters ``enable`` and ``enablepart`` can be used to control the enabling/disabling of the functions:

    * enable: The ``localdisk`` feature only works when ``enable`` is set to ``yes``. If it is set to ``no``, the ``localdisk`` configuration will not be run.
    * enablepart: The partition action (refer to the ``[disk]`` section) will be run only when ``enablepart=yes``.

The ``[disk]`` section is used to configure how to partition a hard disk:

    * dev: The path of the device file.
    * clear: If set to ``yes`` it will clear all the existing partitions on this disk.
    * ptype: The partition table type of the disk. For example, ``msdos`` or ``gpt``, and ``msdos`` is the default.
    * fstype: The file system type for the new created partitions. ``ext4`` is the default.
    * parts: A comma separated list of space ranges, one for each partition that will be created on the device. The valid format for each space range is ``<startpoint>-<endpoint>`` or ``<percentage of the disk>``. For example, you could set it to ``100M-10G`` or ``50``. If set to ``50``, 50% of the disk space will be assigned to that partition.

The ``[localspace]`` section is used to specify which partition will be used as local storage for the node.

    * dev: The path of the partition.
    * fstype: The file system type on the partition.

the ``[swapspace]`` section is used to configure the swap space for the statelite node.

    * dev: The path of the partition file which will be used as the swap space.

To enable the local disk capability, create the configuration file (for example in ``/install/custom``) and set the path in the ``partitionfile`` attribute for the osimage: ::

    chdef -t osimage <osimage> partitionfile=/install/custom/cfglocaldisk

Now all nodes that use this osimage (i.e. have their ``provmethod`` attribute set to this osimage definition name), will have its local disk configured.

Configure the files in the litefile table
`````````````````````````````````````````

For the files/directories to store on the local disk, add an entry in the ``litefile`` table: ::

    "ALL","/tmp/","localdisk",,

.. note:: you do not need to specify the swap space in the litefile table. Just putting it in the ``partitionfile`` config file is enough.

Add an entry in policy table to permit the running of the ``getpartition`` command from the node ::

    chtab priority=7.1 policy.commands=getpartition policy.rule=allow

Run ``genimage`` and ``packimage`` for the osimage
