Configure RAID before Deploy OS
===============================

Overview
--------

This section describes how to use xCAT to deploy diskful nodes with RAID1 setup, and the procedure for RAID1 maintainence activities such as replacing a failed disk.

All the examples in this section are based on three configuration scenarios:

#. RHEL6 on a system p machine with two SCSI disks sda and sdb

#. RHEL6 on a system p machine with two SAS disks and multipath configuration.

#. SLES 11 SP1 on a system p machine with two SCSI disks sda and sdb

If you are not using the configuration scenarios listed above, you may need to modify some of the steps in this documentation to make it work in your environment.

Deploy Diskful Nodes with RAID1 Setup on RedHat
-----------------------------------------------

xCAT provides two sample kickstart template files with the RAID1 settings, ``/opt/xcat/share/xcat/install/rh/service.raid1.rhel6.ppc64.tmpl`` is for the configuration scenario **1** listed above and ``/opt/xcat/share/xcat/install/rh/service.raid1.multipath.rhel6.ppc64.tmpl`` is for the configuration scenario **2** listed above. You can customize the template file and put it under ``/install/custom/install/<platform>/`` if the default one does not match your requirements.

Here is the RAID1 partitioning section in ``service.raid1.rhel6.ppc64.tmpl``: ::

     #Full RAID 1 Sample
     part None --fstype "PPC PReP Boot" --size 8 --ondisk sda --asprimary
     part None --fstype "PPC PReP Boot" --size 8 --ondisk sdb --asprimary

     part raid.01 --size 200 --fstype ext4 --ondisk sda
     part raid.02 --size 200 --fstype ext4 --ondisk sdb
     raid /boot --level 1 --device md0 raid.01 raid.02

     part raid.11 --size 1024 --ondisk sda
     part raid.12 --size 1024 --ondisk sdb
     raid swap --level 1 --device md1 raid.11 raid.12

     part raid.21 --size 1 --fstype ext4 --grow --ondisk sda
     part raid.22 --size 1 --fstype ext4 --grow --ondisk sdb
     raid / --level 1 --device md2 raid.21 raid.22

Here is the RAID1 partitioning section in ``service.raid1.multipath.rhel6.ppc64.tmpl``: ::

     #Full RAID 1 Sample
     part None --fstype "PPC PReP Boot" --size 8 --ondisk mpatha --asprimary
     part None --fstype "PPC PReP Boot" --size 8 --ondisk mpathb --asprimary

     part raid.01 --size 200 --fstype ext4 --ondisk mpatha
     part raid.02 --size 200 --fstype ext4 --ondisk mpathb
     raid /boot --level 1 --device md0 raid.01 raid.02

     part raid.11 --size 1024 --ondisk mpatha
     part raid.12 --size 1024 --ondisk mpathb
     raid swap --level 1 --device md1 raid.11 raid.12

     part raid.21 --size 1 --fstype ext4 --grow --ondisk mpatha
     part raid.22 --size 1 --fstype ext4 --grow --ondisk mpathb
     raid / --level 1 --device md2 raid.21 raid.22

The samples above created one PReP partition, one 200MB ``/boot`` partition and one ``/`` partition on ``sda/sdb`` and ``mpatha/mpathb``. If you want to use different partitioning scheme in your cluster, modify this RAID1 section in the kickstart template file accordingly.

After the diskful nodes are up and running, you can check the RAID1 settings with the following commands:

Mount command shows the ``/dev/mdx`` devices are mounted to various file systems, the ``/dev/mdx`` indicates that the RAID is being used on this node. ::

     # mount
     /dev/md2 on / type ext4 (rw)
     proc on /proc type proc (rw)
     sysfs on /sys type sysfs (rw)
     devpts on /dev/pts type devpts (rw,gid=5,mode=620)
     tmpfs on /dev/shm type tmpfs (rw)
     /dev/md0 on /boot type ext4 (rw)
     none on /proc/sys/fs/binfmt_misc type binfmt_misc (rw)

The file ``/proc/mdstat`` includes the RAID devices status on the system, here is an example of ``/proc/mdstat`` in the non-multipath environment: ::

     # cat /proc/mdstat
     Personalities : [raid1]
     md2 : active raid1 sda5[0] sdb5[1]
           19706812 blocks super 1.1 [2/2] [UU]
           bitmap: 1/1 pages [64KB], 65536KB chunk

     md1 : active raid1 sda2[0] sdb2[1]
           1048568 blocks super 1.1 [2/2] [UU]

     md0 : active raid1 sda3[0] sdb3[1]
           204788 blocks super 1.0 [2/2] [UU]

     unused devices: <none>

On the system with multipath configuration, the ``/proc/mdstat`` looks like: ::

     # cat /proc/mdstat
     Personalities : [raid1]
     md2 : active raid1 dm-11[0] dm-6[1]
           291703676 blocks super 1.1 [2/2] [UU]
           bitmap: 1/1 pages [64KB], 65536KB chunk

     md1 : active raid1 dm-8[0] dm-3[1]
           1048568 blocks super 1.1 [2/2] [UU]

     md0 : active raid1 dm-9[0] dm-4[1]
           204788 blocks super 1.0 [2/2] [UU]

     unused devices: <none>

	
The command ``mdadm`` can query the detailed configuration for the RAID partitions: ::

    mdadm --detail /dev/md2


Deploy Diskful Nodes with RAID1 Setup on SLES
---------------------------------------------

xCAT provides one sample autoyast template files with the RAID1 settings ``/opt/xcat/share/xcat/install/sles/service.raid1.sles11.tmpl``. You can customize the template file and put it under ``/install/custom/install/<platform>/`` if the default one does not match your requirements.

Here is the RAID1 partitioning section in service.raid1.sles11.tmpl: :: 

     <partitioning config:type="list">
        <drive>
          <device>/dev/sda</device>
          <partitions config:type="list">
            <partition>
              <format config:type="boolean">false</format>
              <partition_id config:type="integer">65</partition_id>
              <partition_nr config:type="integer">1</partition_nr>
              <partition_type>primary</partition_type>
              <size>24M</size>
            </partition>
            <partition>
              <format config:type="boolean">false</format>
              <partition_id config:type="integer">253</partition_id>
              <partition_nr config:type="integer">2</partition_nr>
              <raid_name>/dev/md0</raid_name>
              <raid_type>raid</raid_type>
              <size>2G</size>
            </partition>
            <partition>
              <format config:type="boolean">false</format>
              <partition_id config:type="integer">253</partition_id>
              <partition_nr config:type="integer">3</partition_nr>
              <raid_name>/dev/md1</raid_name>
              <raid_type>raid</raid_type>
              <size>max</size>
            </partition>
          </partitions>
          <use>all</use>
        </drive>
        <drive>
          <device>/dev/sdb</device>
          <partitions config:type="list">
            <partition>
              <format config:type="boolean">false</format>
              <partition_id config:type="integer">131</partition_id>
              <partition_nr config:type="integer">1</partition_nr>
              <partition_type>primary</partition_type>
              <size>24M</size>
            </partition>
            <partition>
              <format config:type="boolean">false</format>
              <partition_id config:type="integer">253</partition_id>
              <partition_nr config:type="integer">2</partition_nr>
              <raid_name>/dev/md0</raid_name>
              <raid_type>raid</raid_type>
              <size>2G</size>
            </partition>
            <partition>
              <format config:type="boolean">false</format>
              <partition_id config:type="integer">253</partition_id>
              <partition_nr config:type="integer">3</partition_nr>
              <raid_name>/dev/md1</raid_name>
              <raid_type>raid</raid_type>
              <size>max</size>
            </partition>
          </partitions>
          <use>all</use>
        </drive>
       <drive>
         <device>/dev/md</device>
         <partitions config:type="list">
           <partition>
             <filesystem config:type="symbol">reiser</filesystem>
             <format config:type="boolean">true</format>
             <mount>swap</mount>
             <partition_id config:type="integer">131</partition_id>
             <partition_nr config:type="integer">0</partition_nr>
             <raid_options>
               <chunk_size>4</chunk_size>
               <parity_algorithm>left-asymmetric</parity_algorithm>
               <raid_type>raid1</raid_type>
             </raid_options>
           </partition>
           <partition>
             <filesystem config:type="symbol">reiser</filesystem>
             <format config:type="boolean">true</format>
             <mount>/</mount>
             <partition_id config:type="integer">131</partition_id>
             <partition_nr config:type="integer">1</partition_nr>
             <raid_options>
               <chunk_size>4</chunk_size>
               <parity_algorithm>left-asymmetric</parity_algorithm>
               <raid_type>raid1</raid_type>
             </raid_options>
           </partition>
         </partitions>
         <use>all</use>
       </drive>
     </partitioning>

The samples above created one 24MB PReP partition on each disk, one 2GB mirrored swap partition and one mirrored ``/`` partition uses all the disk space. If you want to use different partitioning scheme in your cluster, modify this RAID1 section in the autoyast template file accordingly.

Since the PReP partition can not be mirrored between the two disks, some additional postinstall commands should be run to make the second disk bootable, here the the commands needed to make the second disk bootable: ::

     # Set the second disk to be bootable for RAID1 setup
     parted -s /dev/sdb mkfs 1 fat16
     parted /dev/sdb set 1 type 6
     parted /dev/sdb set 1 boot on
     dd if=/dev/sda1 of=/dev/sdb1
     bootlist -m normal sda sdb

The procedure listed above has been added to the file ``/opt/xcat/share/xcat/install/scripts/post.sles11.raid1`` to make it be automated. The autoyast template file service.raid1.sles11.tmpl will include the content of post.sles11.raid1, so no manual steps are needed here.	

After the diskful nodes are up and running, you can check the RAID1 settings with the following commands:

Mount command shows the ``/dev/mdx`` devices are mounted to various file systems, the ``/dev/mdx`` indicates that the RAID is being used on this node. ::

     server:~ # mount
     /dev/md1 on / type reiserfs (rw)
     proc on /proc type proc (rw)
     sysfs on /sys type sysfs (rw)
     debugfs on /sys/kernel/debug type debugfs (rw)
     devtmpfs on /dev type devtmpfs (rw,mode=0755)
     tmpfs on /dev/shm type tmpfs (rw,mode=1777)
     devpts on /dev/pts type devpts (rw,mode=0620,gid=5)

The file ``/proc/mdstat`` includes the RAID devices status on the system, here is an example of ``/proc/mdstat``: ::

     server:~ # cat /proc/mdstat
     Personalities : [raid1] [raid0] [raid10] [raid6] [raid5] [raid4]
     md0 : active (auto-read-only) raid1 sda2[0] sdb2[1]
           2104500 blocks super 1.0 [2/2] [UU]
           bitmap: 0/1 pages [0KB], 128KB chunk

     md1 : active raid1 sda3[0] sdb3[1]
           18828108 blocks super 1.0 [2/2] [UU]
           bitmap: 0/9 pages [0KB], 64KB chunk

     unused devices: <none>

The command mdadm can query the detailed configuration for the RAID partitions: ::

    mdadm --detail /dev/md1

Disk Replacement Procedure
--------------------------

If any one disk fails in the RAID1 arrary, do not panic. Follow the procedure listed below to replace the failed disk and you will be fine.

Faulty disks should appear marked with an (F) if you look at ``/proc/mdstat``: ::

     # cat /proc/mdstat
     Personalities : [raid1]
     md2 : active raid1 dm-11[0](F) dm-6[1]
           291703676 blocks super 1.1 [2/1] [_U]
           bitmap: 1/1 pages [64KB], 65536KB chunk

     md1 : active raid1 dm-8[0](F) dm-3[1]
           1048568 blocks super 1.1 [2/1] [_U]

     md0 : active raid1 dm-9[0](F) dm-4[1]
           204788 blocks super 1.0 [2/1] [_U]

     unused devices: <none>

We can see that the first disk is broken because all the RAID partitions on this disk are marked as (F).

Remove the failed disk from RAID arrary
---------------------------------------

``mdadm`` is the command that can be used to query and manage the RAID arrays on Linux. To remove the failed disk from RAID array, use the command: ::

     mdadm --manage /dev/mdx --remove /dev/xxx

Where the ``/dev/mdx`` are the RAID partitions listed in ``/proc/mdstat`` file, such as md0, md1 and md2; the ``/dev/xxx`` are the backend devices like dm-11, dm-8 and dm-9 in the multipath configuration and sda5, sda3 and sda2 in the non-multipath configuration.

Here is the example of removing failed disk from the RAID1 array in the non-multipath configuration: ::

     mdadm --manage /dev/md0 --remove /dev/sda3
     mdadm --manage /dev/md1 --remove /dev/sda2
     mdadm --manage /dev/md2 --remove /dev/sda5

Here is the example of removing failed disk from the RAID1 array in the multipath configuration: ::

     mdadm --manage /dev/md0 --remove /dev/dm-9
     mdadm --manage /dev/md1 --remove /dev/dm-8
     mdadm --manage /dev/md2 --remove /dev/dm-11

After the failed disk is removed from the RAID1 array, the partitions on the failed disk will be removed from ``/proc/mdstat`` and the "mdadm --detail" output also. ::

     # cat /proc/mdstat
     Personalities : [raid1]
     md2 : active raid1 dm-6[1]
           291703676 blocks super 1.1 [2/1] [_U]
           bitmap: 1/1 pages [64KB], 65536KB chunk

     md1 : active raid1 dm-3[1]
           1048568 blocks super 1.1 [2/1] [_U]

     md0 : active raid1 dm-4[1]
           204788 blocks super 1.0 [2/1] [_U]

     unused devices: <none>

     # mdadm --detail /dev/md0
     /dev/md0:
             Version : 1.0
       Creation Time : Tue Jul 19 02:39:03 2011
          Raid Level : raid1
          Array Size : 204788 (200.02 MiB 209.70 MB)
       Used Dev Size : 204788 (200.02 MiB 209.70 MB)
        Raid Devices : 2
       Total Devices : 1
         Persistence : Superblock is persistent

         Update Time : Wed Jul 20 02:00:04 2011
               State : clean, degraded
      Active Devices : 1
     Working Devices : 1
      Failed Devices : 0
       Spare Devices : 0

                Name : c250f17c01ap01:0  (local to host c250f17c01ap01)
                UUID : eba4d8ad:8f08f231:3c60e20f:1f929144
              Events : 26

         Number   Major   Minor   RaidDevice State
            0       0        0        0      removed
            1     253        4        1      active sync   /dev/dm-4
			

Replace the disk
----------------

Depends on the hot swap capability, you may simply unplug the disk and replace with a new one if the hot swap is supported; otherwise, you will need to power off the machine and replace the disk and the power on the machine.
Create partitions on the new disk

The first thing we must do now is to create the exact same partitioning as on the new disk. We can do this with one simple command: ::

     sfdisk -d /dev/<good_disk> | sfdisk /dev/<new_disk>

For the non-mulipath configuration, here is an example: ::

     sfdisk -d /dev/sdb | sfdisk /dev/sda

For the multipath configuration, here is an example: ::

     sfdisk -d /dev/dm-1 | sfdisk /dev/dm-0

If you got error message "sfdisk: I don't like these partitions - nothing changed.", you can add "--force" option to the sfdisk command: ::

     sfdisk -d /dev/sdb | sfdisk /dev/sda --force

You can run: ::

     fdisk -l

To check if both hard drives have the same partitioning now.

Add the new disk into the RAID1 array
-------------------------------------

After the partitions are created on the new disk, you can use command: ::

     mdadm --manage /dev/mdx --add /dev/xxx

To add the new disk to the RAID1 array. Where the ``/dev/mdx`` are the RAID partitions like md0, md1 and md2; the ``/dev/xxx`` are the backend devices like dm-11, dm-8 and dm-9 in the multipath configuration and sda5, sda3 and sda2 in the non-multipath configuration.

Here is an example for the non-multipath configuration: ::

     mdadm --manage /dev/md0 --add /dev/sda3
     mdadm --manage /dev/md1 --add /dev/sda2
     mdadm --manage /dev/md2 --add /dev/sda5

Here is an example for the multipath configuration: ::

     mdadm --manage /dev/md0 --add /dev/dm-9
     mdadm --manage /dev/md1 --add /dev/dm-8
     mdadm --manage /dev/md2 --add /dev/dm-11

All done! You can have a cup of coffee to watch the fully automatic reconstruction running...

While the RAID1 array is reconstructing, you will see some progress information in ``/proc/mdstat``: ::

     # cat /proc/mdstat
     Personalities : [raid1]
     md2 : active raid1 dm-11[0] dm-6[1]
           291703676 blocks super 1.1 [2/1] [_U]
           [>....................]  recovery =  0.7% (2103744/291703676) finish=86.2min speed=55960K/sec
           bitmap: 1/1 pages [64KB], 65536KB chunk

     md1 : active raid1 dm-8[0] dm-3[1]
           1048568 blocks super 1.1 [2/1] [_U]
           [=============>.......]  recovery = 65.1% (683904/1048568) finish=0.1min speed=48850K/sec

     md0 : active raid1 dm-9[0] dm-4[1]
           204788 blocks super 1.0 [2/1] [_U]
           [===================>.]  recovery = 96.5% (198016/204788) finish=0.0min speed=14144K/sec

     unused devices: <none>

After the reconstruction is done, the ``/proc/mdstat`` becomes like: ::

     # cat /proc/mdstat
     Personalities : [raid1]
     md2 : active raid1 dm-11[0] dm-6[1]
           291703676 blocks super 1.1 [2/2] [UU]
           bitmap: 1/1 pages [64KB], 65536KB chunk

     md1 : active raid1 dm-8[0] dm-3[1]
           1048568 blocks super 1.1 [2/2] [UU]

     md0 : active raid1 dm-9[0] dm-4[1]
           204788 blocks super 1.0 [2/2] [UU]

     unused devices: <none>

Make the new disk bootable
--------------------------

If the new disk does not have a PReP partition or the PReP partition has some problem, it will not be bootable, here is an example on how to make the new disk bootable, you may need to substitute the device name with your own values.

* **[RHEL]**::

     mkofboot .b /dev/sda
     bootlist -m normal sda sdb

* **[SLES]**::

     parted -s /dev/sda mkfs 1 fat16
     parted /dev/sda set 1 type 6
     parted /dev/sda set 1 boot on
     dd if=/dev/sdb1 of=/dev/sda1
     bootlist -m normal sda sdb


