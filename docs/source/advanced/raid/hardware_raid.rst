Hardware RAID
=============

Overview
--------

In many new compute machines, disks have been formatted into RAID oriented format in manufacturer, so admin must create raid arrays using these disks manually before provisioning OS. How to configure raid arrays in unattended way for hundreds of machines turns to be a problem.

IBM has offered a tool ``iprconfig`` to configure raid for IBM power machine. To leverage this tool, xCAT enabled it in xCAT genesis.ppc64 so that admin can use genesis.ppc64 to configure RAID arrays. 

There are two commands (``diskdiscover`` and ``configraid``) shipped in ``xCAT-genesis-scripts`` package to support RAID arrays configuration using ``iprconfig``, you can use the ``runcmd`` facility to configure raid in the hardware discovery procedure using them, ``runcmd`` is a facility which will be run in xcat genesis system. You can also use separated manual steps to use ``configraid`` in xcat genesis system shell.  

* **diskdiscover** : Scan disk devices in xcat genesis system, give out disks and RAID arrays information.
* **configraid** : Delete RAID arrays, create RAID arrays in xcat genesis system.

Following sections show how to use ``diskdiscover`` and ``configraid``, we assume ``cn1`` is compute node in all examples.

Discovering disk devices
------------------------

Command ``diskdiscover`` scans disk devices, it can get the overview of disks and RAID arrays information from compute node; The outputs contain useful information for ``configraid`` to configure RAID arrays, user can get ``pci_id``, ``pci_slot_name``, ``disk names``, ``RAID arrays`` and other informations from the outputs. It should be ran in xcat genesis system. It can be executed without input parameter or with pci_id, pci_id includes PCI vendor and device ID. For example, power8 SAS adapter pci_id is ``1014:034a``, ``1014`` is vendor info, ``034a`` is PCI-E IPR SAS Adapter, more info about pci_id refer to ``http://pci-ids.ucw.cz/read/PC/1014/``.

Here are steps to use ``diskdiscover``:

#. Start xCAT genesis system in compute node, let compute node ``cn1`` enter xCAT genesis system shell: ::

    nodeset cn1 shell
    rpower cn1 reset

   ``Note``: If user modify ``diskdiscover`` or ``configraid`` scripts, he needs to run the ``mknb <arch>`` command before ``nodeset`` command to update network boot root image.

#. On xcat management node, executing ``xdsh`` to use ``diskdiscover``: ::

    xdsh cn1 diskdiscover

   Or: ::

    xdsh cn1 'diskdiscover <pci_id>'

   The outputs format is as following: ::
   
    # xdsh cn1 diskdiscover
    cn1: --------------------------------------------------------------------------
    cn1: PCI_ID     PCI_SLOT_NAME  Resource_Path  Device  Description   Status
    cn1: ------     -------------  -------------  ------  -----------   ----------------
    cn1: 1014:034a  0001:08:00.0   0:0:0:0        sg0     Function Disk Active
    cn1: 1014:034a  0001:08:00.0   0:0:1:0        sg1     0 Array Member Active
    cn1: -------------------------------------------------------------------
    cn1: Get ipr RAID arrays by PCI_SLOT_NAME: 0001:08:00.0
    cn1: -------------------------------------------------------------------
    cn1: Name   PCI/SCSI Location         Description               Status
    cn1: ------ ------------------------- ------------------------- -----------------
    cn1: sda    0001:08:00.0/0:2:0:0       RAID 0 Disk Array         Optimized


Configuring hardware RAID
-------------------------

Command configraid introduction
````````````````````````````````

We can use ``configraid`` to delete RAID arrays or create RAID arrays: ::

  configraid delete_raid=[all|"<raid_array_list>"|null]
             stripe_size=[16|64|256]
             create_raid="rl#<raidlevel>|[pci_id#<num>|pci_slot_name#<pci_slot_name>|disk_names#<sg0>#..#<sgn>]|disk_num#<number>" ...

Here are the input parameters introduction:

#. **delete_raid** : List raid arrays which should be removed.

     * If its value is all, all raid arrays detected should be deleted.
     * If its value is a list of raid array names, these raid arrays will be deleted. Raid array names should be separated by ``#``.
     * If its value is null or there is no delete_raid, no raid array will be deleted.
     * If there is no delete_raid, the default value is null.

#. **stripe_size** : It is optional used when creating RAID arrays. If stripe size is not specified, it will default to the recommended stripe size for the selected RAID level.

#. **create_raid** : To create a raid array, add a line beginning with create_raid, all attributes keys and values are separated by ``#``. The formats are as followings: 

     * ``rl`` means RAID level, RAID level can be any supported RAID level for the given adapter, such as 0, 10,  5,  6. ``rl`` is a mandatory attribute for every create_raid. Supported RAID level is depend on physical server's RAID adapter.

     * User can select disks based on following attributes value. User can find these value based on ``diskdiscover`` outputs as above section described.
 
         a. ``pci_id`` is PCI vendor and device ID.
         b. ``pci_slot_name`` is the specified PCI location. If using ``pci_slot_name``, this RAID array will be created using disks from it.
         c. ``disk_names`` is a list of advanced format disk names. If using ``disk_names``, this RAID array will be created using these disks.

     * ``disk_num`` is the number of disks this RAID array will contain, default value is all unused disks in its pci slot.

More examples of input parameters:

    #. Delete all original RAID arrays, create one RAID 10 array from pci_id ``1014:034a``, it uses the first two available disks: ::

        delete_raid=all create_raid="rl#10|pci_id#1014:034a|disk_num#2"

    #. Delete original RAID arrays sda and sdb on compute node, create one RAID 0 array from pci slot 0001:08:00.0, its RAID level is 0, it uses first two disks: ::

        delete_raid="sda#sdb" create_raid="rl#0|pci_slot_name#0001:08:00.0|disk_num#2"

    #. Create one RAID array from pci_id ``1014:034a``, RAID level is 0, stripe_size is 256kb, using first two available disks: ::

        stripe_size=256 create_raid="rl#0|pci_id#1014:034a|disk_num#2"

    #. Create two RAID arrays, RAID level is 0, one array uses one disks from pci_id 1014:034a, the other array uses two disks from pci_slot_name ``0001:08:00.0``: ::

        create_raid="rl#0|pci_id#1014:034a|disk_num#1" create_raid="rl#0|pci_slot_name#0001:08:00.0|disk_num#2" 

    #. Create two RAID arrays, RAID level is 0, one array uses disks sg0 and sg1, the other array uses disks sg2 and sg3: ::

        create_raid="rl#0|disk_names#sg0#sg1" create_raid="rl#0|disk_names#sg2#sg3"

Configuring RAID arrays process
````````````````````````````````

Command ``configraid`` is running in xcat genesis system, its log is saved under ``/tmp`` on compute node genesis system.

Configuring RAID in hardware discovery procedure
'''''''''''''''''''''''''''''''''''''''''''''''''

#. Using ``runcmd`` facility to configure raid in the hardware discovery procedure, after configuring RAID, compute node enter xcat genesis system shell. In the following example, ``configraid`` deletes all original RAID arrays, it creates one RAID 0 array with first two disks from pci_id ``1014:034a``: ::
    
    nodeset cn1 runcmd="configraid delete_raid=all create_raid=rl#0|pci_id#1014:034a|disk_num#2",shell
    rpower cn1 reset

#. Using ``rcons`` to monitor the process: ::

    rcons cn1

Configuring RAID manually in xcat genesis system shell
''''''''''''''''''''''''''''''''''''''''''''''''''''''

#. Starting xCAT genesis system in compute node, let compute node ``cn1`` enter xCAT genesis system shell: ::

    nodeset cn1 shell
    rpower cn1 reset

#. On xcat management node, executing ``xdsh`` to use ``configraid`` to configure RAID: ::

    xdsh cn1 'configraid delete_raid=all create_raid="rl#0|pci_id#1014:034a|disk_num#2"'

Monitoring and debuging RAID configuration process
''''''''''''''''''''''''''''''''''''''''''''''''''

#. Creating some RAID level arrays take very long time, for example, If user creates RAID 10, it will cost tens of minutes or hours. During this period, you can use xCAT xdsh command to monitor the progress of raid configuration. ::

    xdsh cn1 iprconfig -c show-config

#. Logs for ``configraid`` is saved under ``tmp`` in compute node genesis system. User can login compute node and check ``configraid`` logs to debug.

#. When configuring RAID in hardware discovery procedure, user can use ``rcons`` command to monitor or debug the process: ::
 
    rcons cn1
