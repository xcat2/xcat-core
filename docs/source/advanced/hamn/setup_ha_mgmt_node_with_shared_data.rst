.. _setup_ha_mgmt_node_with_shared_data:

Setup HA Mgmt Node With Shared Data
===================================

This documentation illustrates how to setup a second management node, or standby management node, in your cluster to provide high availability management capability, using shared data between the two management nodes.

When the primary xCAT management node fails, the administrator can easily have the standby management node take over role of the management node, and thus avoid long periods of time during which your cluster does not have active cluster management function available.

The xCAT high availability management node(``HAMN``) through shared data is not designed for automatic setup or automatic failover, this documentation describes how to use shared data between the primary management node and standby management node, and describes how to perform some manual steps to have the standby management node takeover the management node role when the primary management node fails. However, high availability applications such as ``IBM Tivoli System Automation(TSA)`` and Linux ``Pacemaker`` could be used to achieve automatic failover, how to configure the high availability applications is beyond the scope of this documentation, you could refer to the applications documentation for instructions.

The nfs service on the primary management node or the primary management node itself will be shutdown during the failover process, so any NFS mount or other network connections from the compute nodes to the management node should be temporarily disconnected during the failover process. If the network connectivity is required for compute node run-time operations, you should consider some other way to provide high availability for the network services unless the compute nodes can also be taken down during the failover process. This also implies:

#. This HAMN approach is primarily intended for clusters in which the management node manages linux diskful nodes or stateless nodes. This also includes hierarchical clusters in which the management node only directly manages the linux diskful or linux stateless service nodes, and the compute nodes managed by the service nodes can be of any type.

#. If the nodes use only readonly nfs mounts from the MN management node, then you can use this doc as long as you recognize that your nodes will go down while you are failing over to the standby management node.

What is Shared Data
====================

The term ``Shared Data`` means that the two management nodes use a single copy of xCAT data, no matter which management node is the primary MN, the cluster management capability is running on top of the single data copy. The acess to the data could be done through various ways like shared storage, NAS, NFS, samba etc. Based on the protocol being used, the data might be accessable only on one management node at a time or be accessable on both management nodes in parellel. If the data could only be accessed from one management node, the failover process need to take care of the data access transition; if the data could be accessed on both management nodes, the failover does not need to consider the data access transition, it usually means the failover process could be faster.

``Warning``: Running database through network file system has a lot of potential problems and is not practical, however, most of the database system provides database replication feature that can be used to synronize the database between the two management nodes

Configuration Requirements
==========================

#. xCAT HAMN requires that the operating system version, xCAT version and database version be identical on the two management nodes.

#. The hardware type/model are not required to be the same on the two management nodes, but it is recommended to have similar hardware capability on the two management nodes to support the same operating system and have similar management capability.

#. Since the management node needs to provide IP services through broadcast such as DHCP to the compute nodes, the primary management node and standby management node should be in the same subnet to ensure the network services will work correctly after failover.

#. Setting up HAMN can be done at any time during the life of the cluster, in this documentation we assume the HAMN setup is done from the very beginning of the xCAT cluster setup, there will be some minor differences if the HAMN setup is done from the middle of the xCAT cluster setup.

The example given in this document is for RHEL 6. The same approach can be applied to SLES, but the specific commands might be slightly different. The examples in this documentation are based on the following cluster environment:

Virtual IP Alias Address: 9.114.47.97

Primary Management Node: rhmn1(9.114.47.103), netmask is 255.255.255.192, hostname is rhmn1, running RHEL 6.

Standby Management Node: rhmn2(9.114.47.104), netmask is 255.255.255.192, hostname is rhmn2. Running RHEL 6.

You need to substitute the hostnames and ip address with your own values when setting up your HAMN environment.

Configuring Shared Data
=======================

``Note``: Shared data itself needs high availability also, the shared data should not become a single point of failure.

The configuration procedure will be quite different based on the shared data mechanism that will be used. Configuring these shared data mechanisms is beyond the scope of this documentation. After the shared data mechanism is configured, the following xCAT directory structure should be on the shared data, if this is done before xCAT is installed, you need to create the directories manually; if this is done after xCAT is installed, the directories need to be copied to the shared data. ::

    /etc/xcat
    /install
    ~/.xcat
    /<dbdirectory> 


``Note``:For MySQL, the database directory is ``/var/lib/mysql``; for PostGreSQL, the database directory is ``/var/lib/pgsql``; for DB2, the database directory is specified with the site attribute databaseloc; for sqlite, the database directory is /etc/xcat, already listed above. 

Here is an example of how to make directories be shared data through NFS: ::

    mount -o rw <nfssvr>:/dir1 /etc/xcat
    mount -o rw <nfssvr>:/dir2 /install
    mount -o rw <nfssvr>:/dir3 ~/.xcat
    mount -o rw <nfssvr>:/dir4 /<dbdirectory>

``Note``: if you need to setup high availability for some other applications, like the HPC software stack, between the two xCAT management nodes, the applications data should be on the shared data.

Setup xCAT on the Primary Management Node
=========================================

#. Make the shared data be available on the primary management node.

#. Set up a ``Virtual IP address``. The xcatd daemon should be addressable with the same ``Virtual IP address``, regardless of which management node it runs on. The same ``Virtual IP address`` will be configured as an alias IP address on the management node (primary and standby) that the xcatd runs on. The Virtual IP address can be any unused ip address that all the compute nodes and service nodes could reach. Here is an example on how to configure Virtual IP address: ::

    ifconfig eth0:0 9.114.47.97 netmask 255.255.255.192

   The option ``firstalias`` will configure the Virtual IP ahead of the interface ip address, since ifconfig will not make the ip address configuration be persistent through reboots, so the Virtual IP address needs to be re-configured right after the management node is rebooted. This non-persistent Virtual IP address is designed to avoid ip address conflict when the crashed previous primary management is recovered with the Virtual IP address configured.

#. Add the alias ip address into the ``/etc/resolv.conf`` as the nameserver. Change the hostname resolution order to be using ``/etc/hosts`` before using name server, change to "hosts: files dns" in ``/etc/nsswitch.conf``.

#. Change hostname to the hostname that resolves to the Virtual IP address. This is required for xCAT and database to be setup properly.

#. Install xCAT. The procedure described in :doc:`xCAT Install Guide <../../guides/install-guides/index>` could be used for the xCAT setup on the primary management node.

#. Check the site table master and nameservers and network tftpserver attribute is the Virtual ip: ::

    lsdef -t site

   If not correct: ::

    chdef -t site master=9.114.47.97
    chdef -t site nameservers=9.114.47.97
    chdef -t network tftpserver=9.114.47.97

   Add the two management nodes into policy table: ::

    tabdump policy  
    "1.2","rhmn1",,,,,,"trusted",,
    "1.3","rhmn2",,,,,,"trusted",,

#. (Optional) DB2 only, change the databaseloc in site table: ::

    chdef -t site databaseloc=/dbdirectory

#. Install and configure database. Refer to the doc [**doto:** choosing_the_Database] to configure the database on the xCAT management node.

   Verify xcat is running on correct database by running: ::

    lsxcatd -a

#. Backup the xCAT database tables for the current configuration on standby management node, using command : ::

    dumpxCATdb -p <your_backup_dir>.

#. Setup a crontab to backup the database each night by running ``dumpxCATdb`` and storing the backup to some filesystem not on the shared data.

#. Stop the xcatd daemon and some related network services from starting on reboot: ::

    service xcatd stop
    chkconfig --level 345 xcatd off  
    service conserver off
    chkconfig --level 2345 conserver off
    service dhcpd stop
    chkconfig --level 2345 dhcpd off

#. Stop Database and prevent the database from auto starting at boot time, use MySQL as an example: ::

    service mysqld stop
    chkconfig mysqld off

#. (Optional) If DFM is being used for hardware control capabilities, install DFM package, setup xCAT to communicate directly to the System P server's service processor.::

     xCAT-dfm RPM 
     ISNM-hdwr_svr RPM  

#. If there is any node that is already managed by the Management Node,change the noderes table tftpserver & xcatmaster & nfsserver attributes to the Virtual ip

#. Set the hostname back to original non-alias hostname.

#. After installing xCAT and database, you could setup service node or compute node.

Setup xCAT on the Standby Management Node
=========================================

#. Make sure the standby management node is NOT using the shared data.

#. Add the alias ip address into the ``/etc/resolv.conf`` as the nameserver. Change the hostname resolution order to be using ``/etc/hosts`` before using name server. Change "hosts: files dns" in /etc/nsswitch.conf.

#. Temporarily change the hostname to the hostname that resolves to the Virtual IP address. This is required for xCAT and database to be setup properly. This only needs to be done one time.

   Also configure the Virtual IP address during this setup. ::

    ifconfig eth0:0 9.114.47.97 netmask 255.255.255.192

#. Install xCAT. The procedure described in :doc:`xCAT Install Guide <../../guides/install-guides/index>` can be used for the xCAT setup on the standby management node. The database system on the standby management node must be the same as the one running on the primary management node.

#. (Optional) DFM only, Install DFM package: ::

    xCAT-dfm RPM 
    ISNM-hdwr_svr RPM 

#. Setup hostname resolution between the primary management node and standby management node. Make sure the primary management node can resolve the hostname of the standby management node, and vice versa.

#. Setup ssh authentication between the primary management node and standby management node. It should be setup as "passwordless ssh authentication" and it should work in both directions. The summary of this procedure is:

   a. cat keys from ``/.ssh/id_rsa.pub`` on the primary management node and add them to ``/.ssh/authorized_keys`` on the standby management node. Remove the standby management node entry from ``/.ssh/known_hosts`` on the primary management node prior to issuing ssh to the standby management node.

   b. cat keys from ``/.ssh/id_rsa.pub`` on the standby management node and add them to ``/.ssh/authorized_keys`` on the primary management node. Remove the primary management node entry from ``/.ssh/known_hosts`` on the standby management node prior to issuing ssh to the primary management node.

#. Make sure the time on the primary management node and standby management node is synchronized.

#. Stop the xcatd daemon and related network services from starting on reboot: ::

    service xcatd stop
    chkconfig --level 345 xcatd off  
    service conserver off
    chkconfig --level 2345 conserver off
    service dhcpd stop
    chkconfig --level 2345 dhcpd off

#. Stop Database and prevent the database from auto starting at boot time. Use MySQL as an example: ::

    service mysqld stop
    chkconfig mysqld off

#. Backup the xCAT database tables for the current configuration on standby management node, using command: ::

    dumpxCATdb -p <yourbackupdir>.

#. Change the hostname back to the original hostname.

#. Remove the Virtual Alias IP. ::

    ifconfig eth0:0 0.0.0.0 0.0.0.0

File Synchronization
====================

For the files that are changed constantly such as xcat database, ``/etc/xcat/*``, we have to put the files on the shared data; but for the files that are not changed frequently or unlikely to be changed at all, we can simply copy the the files from the primary management node to the standby management node or use crontab and rsync to keep the files synchronized between primary management node and standby management node. Here are some files we recommend to keep synchronization between the primary management node and standby management node:

SSL Credentials and SSH Keys
--------------------------------

To enable both the primary and the standby management nodes to ssh to the service nodes and compute nodes, the ssh keys should be kept synchronized between the primary management node and standby management node. To allow xcatd on both the primary and the standby management nodes to communicate with xcatd on the services nodes, the xCAT SSL credentials should be kept synchronized between the primary management node and standby management node.

The xCAT SSL credentials reside in the directories ``/etc/xcat/ca``, ``/etc/xcat/cert`` and ``$HOME/.xcat/``. The ssh host keys that xCAT generates to be placed on the compute nodes are in the directory ``/etc/xcat/hostkeys``. These directories are on the shared data.

In addition the ssh root keys in the management node's root home directory (in ~/.ssh) must be kept in sync between the primary management node and standby management node. Only sync the key files and not the authorized_key file. These keys will seldom change, so you can just do it manually when they do, or setup a cron entry like this sample: ::

    0 1 * * * /usr/bin/rsync -Lprgotz $HOME/.ssh/id*  rhmn2:$HOME/.ssh/

Now go to the Standby node and add the Primary's id_rsa.pub to the Standby's authorized_keys file.

Network Services Configuration Files
------------------------------------

A lot of network services are configured on the management node, such as DNS, DHCP and HTTP. The network services are mainly controlled by configuration files. However, some of the network services configuration files contain the local hostname/ipaddresses related information, so simply copying these network services configuration files to the standby management node may not work. Generating these network services configuration files is very easy and quick by running xCAT commands such as makedhcp, makedns or nimnodeset, as long as the xCAT database contains the correct information.

While it is easier to configure the network services on the standby management node by running xCAT commands when failing over to the standby management node, an exception is the ``/etc/hosts``; the ``/etc/hosts`` may be modified on your primary management node as ongoing cluster maintenance occurs. Since the ``/etc/hosts`` is very important for xCAT commands, the ``/etc/hosts`` will be synchronized between the primary management node and standby management node. Here is an example of the crontab entries for synchronizing the ``/etc/hosts``: ::

    0 2 * * * /usr/bin/rsync -Lprogtz /etc/hosts rhmn2:/etc/

Additional Customization Files and Production files
----------------------------------------------------

Besides the files mentioned above, there may be some additional customization files and production files that need to be copied over to the standby management node, depending on your local unique requirements. You should always try to keep the standby management node as an identical clone of the primary management node. Here are some example files that can be considered: ::

    /.profile
    /.rhosts
    /etc/auto_master
    /etc/auto/maps/auto.u
    /etc/motd
    /etc/security/limits
    /etc/netscvc.conf
    /etc/ntp.conf
    /etc/inetd.conf
    /etc/passwd
    /etc/security/passwd
    /etc/group
    /etc/security/group
    /etc/exports
    /etc/dhcpsd.cnf
    /etc/services
    /etc/inittab
    (and more)

``Note``:
If the IBM HPC software stack is configured in your environment, execute additional steps required to copy additional data or configuration files for HAMN setup.
The dhcpsd.cnf should be syncronized between the primary management node and standby management node only when the DHCP configuration on the two management nodes are exactly the same.

Cluster Maintenance Considerations
==================================

The standby management node should be taken into account when doing any maintenance work in the xCAT cluster with HAMN setup.

#. Software Maintenance - Any software updates on the primary management node should also be done on the standby management node.

#.  File Synchronization - Although we have setup crontab to synchronize the related files between the primary management node and standby management node, the crontab entries are only run in specific time slots. The synchronization delay may cause potential problems with HAMN, so it is recommended to manually synchronize the files mentioned in the section above whenever the files are modified.

#.  Reboot management nodes - In the primary management node needs to be rebooted, since the daemons are set to not auto start at boot time, and the shared data will not be mounted automatically, you should mount the shared data and start the daemons manually.

``Note``: after software upgrade, some services that were set to not autostart on boot might be started by the software upgrade process, or even set to autostart on boot, the admin should check the services on both primary and standby management node, if any of the services are set to autostart on boot, turn it off; if any of the services are started on the backup management node, stop the service.

At this point, the HA MN Setup is complete, and customer workloads and system administration can continue on the primary management node until a failure occurs. The xcatdb and files on the standby management node will continue to be synchronized until such a failure occurs.

Failover
========

There are two kinds of failover, planned failover and unplanned failover. The planned failover can be useful for updating the management nodes or any scheduled maintainance activities; the unplanned failover covers the unexpected hardware or software failures.

In a planned failover, you can do necessary cleanup work on the previous primary management node before failover to the previous standby management node. In a unplanned failover, the previous management node probably is not functioning at all, you can simply shutdown the system.

Take down the Current Primary Management Node
---------------------------------------------

xCAT ships a sample script ``/opt/xcat/share/xcat/hamn/deactivate-mn`` to make the machine be a standby management node. Before using this script, you need to review the script carefully and make updates accordingly, here is an example of how to use this script: ::

    /opt/xcat/share/xcat/hamn/deactivate-mn -i eth1:2 -v 9.114.47.97

On the current primary management node:

If the management node is still available and running the cluster, perform the following steps to shutdown.

#. (DFM only) Remove connections from CEC and Frame. ::

    rmhwconn cec,frame
    rmhwconn cec,frame -T fnm

#. Stop the xCAT daemon.

   ``Note``: xCAT must be stopped on all Service Nodes also, and LL if using the database. ::

    service xcatd stop
    service dhcpd stop

#. unexport the xCAT NFS directories

   The exported xCAT NFS directories will prevent the shared data partitions from being unmounted, so the exported xCAT NFS directories should be unmounted before failover: ::

    exportfs -ua

#. Stop database

   Use MySQL as an example: ::

    service mysqld stop

#. Unmount shared data

   All the file systems on the shared data need to be unmounted to make the previous standby management be able to mount the file systems on the shared data. Here is an example: ::

    umount /etc/xcat
    umount /install
    umount ~/.xcat
    umount /db2database

   When trying to umount the file systems, if there are some processes that are accessing the files and directories on the file systems, you will get "Device busy" error. Then stop or kill all the processes that are accessing the shared data file systems and retry the unmount.

#. Unconfigure Virtual IP: ::

    ifconfig eth0:0 0.0.0.0 0.0.0.0

   If the ifconfig command has been added to rc.local, remove it from rc.local.

Bring up the New Primary Management Node
----------------------------------------

Execute script ``/opt/xcat/share/xcat/hamn/activate-mn`` to make the machine be a primary management node: ::

     /opt/xcat/share/xcat/hamn/activate-mn -i eth1:2 -v 9.114.47.97 -m 255.255.255.0

On the new primary management node:

#. Configure Virtual IP: ::

    ifconfig eth0:0 9.114.47.97 netmask 255.255.255.192

   You can put the ifconfig command into rc.local to make the Virtual IP be persistent after reboot.

#. Mount shared data: ::

    mount /etc/xcat
    mount /install
    mount /.xcat
    mount /db2database

#. Start database, use MySQL as an example: ::

    service mysql start

#. Start the daemons: ::

    service dhcpd start
    service xcatd start
    service hdwr_svr start
    service conserver start

#. (DFM only) Setup connection for CEC and Frame: ::

    mkhwconn cec,frame -t
    mkhwconn cec,frame -t -T fnm
    chnwm -a

#. Setup network services and conserver

   **DNS**: run ``makedns``. Verify dns services working for node resolution. Make sure the line ``nameserver=<virtual ip>`` is in ``/etc/resolv.conf``.

   **DHCP**: if the dhcpd.leases is not syncronized between the primary management node and standby management node, run ``makedhcp -a`` to setup the DHCP leases. Verify dhcp is operational.

   **conserver**: run makeconservercf. This will recreate the ``/etc/conserver.cf`` config files for all the nodes.

#. (Optional)Setup os deployment environment

   This step is required only when you want to use this new primary management node to perform os deployment tasks.

   The operating system images definitions are already in the xCAT database, and the operating system image files are already in ``/install`` directory.

   Run the following command to list all the operating system images. ::

    lsdef -t osimage -l

   If you are seeing ssh problems when trying to ssh the compute nodes or any other nodes, the hostname in ssh keys under directory $HOME/.ssh needs to be updated.

#. Restart NFS service and re-export the NFS exports

   Because of the Virtual ip configuration and the other network configuration changes on the new primary management node, the NFS service needs to be restarted and the NFS exports need to be re-exported. ::

    exportfs -ua
    service nfs stop
    service nfs start
    exportfs -a

Setup the Cluster
-----------------

At this point you have setup your Primary and Standby management node for HA. You can now continue to setup your cluster. Return to using the Primary management node attached to the shared data. Now setup your Hierarchical cluster using the following documentation, depending on your Hardware,OS and type of install you want to do on the Nodes. Other docs are available for full disk installs :doc:`Admin Guide <../../guides/admin-guides/index>`.

For all the xCAT docs: http://xcat-docs.readthedocs.org

Appendix A Configure Shared Disks
=================================

The following two sections describe how to configure shared disks on Linux. And the steps do not apply to all shared disks configuration scenarios, you may need to use some slightly different steps according to your shared disks configuration.

The operating system is installed on the internal disks.

#. Connect the shared disk to both management nodes

   To verify the shared disks are connected correctly, run the sginfo command on both management nodes and look for the same serial number in the output. Be aware that the sginfo command may not be installed by default on Linux, the sginfo command is shipped with package sg3_utils, you can manually install the package sg3_utils on both management nodes. 

   Once the sginfo command is installed, run sginfo -l command on both management nodes to list all the known SCSI disks, for example, enter: ::

    sginfo -l

   Output will be similar to: ::

    /dev/sdd /dev/sdc /dev/sdb /dev/sda
    /dev/sg0 [=/dev/sda  scsi0 ch=0 id=1 lun=0]
    /dev/sg1 [=/dev/sdb  scsi0 ch=0 id=2 lun=0]
    /dev/sg2 [=/dev/sdc  scsi0 ch=0 id=3 lun=0]
    /dev/sg3 [=/dev/sdd  scsi0 ch=0 id=4 lun=0]

   Use the ``sginfo -s <device_name>`` to identify disks with the same serial number on both management nodes, for example: 

   On the primary management node: :: 

    [root@rhmn1 ~]# sginfo -s /dev/sdb
    Serial Number '1T23043224      '

    [root@rhmn1 ~]#

   On the standby management node: ::

    [root@rhmn2~]# sginfo -s /dev/sdb
    Serial Number '1T23043224      '

   We can see that the ``/dev/sdb`` is a shared disk on both management nodes. In some cases, as with mirrored disks and when there is no matching of serial numbers between the two management nodes, multiple disks on a single server can have the same serial number, In these cases, format the disks, mount them on both management nodes, and then touch files on the disks to determine if they are shared between the management nodes. 

#. Create partitions on shared disks

   After the shared disks are identified, create the partitions on the shared disks using fdisk command on the primary management node. Here is an example: ::

    fdisk /dev/sdc

   Verify the partitions are created by running ``fdisk -l``. 

#. Create file systems on shared disks

   Run the ``mkfs.ext3`` command on the primary management node to create file systems on the shared disk that will contain the xCAT data. For example: ::

    mkfs.ext3 -v /dev/sdc1
    mkfs.ext3 -v /dev/sdc2
    mkfs.ext3 -v /dev/sdc3
    mkfs.ext3 -v /dev/sdc4

   If you place entries for the disk in ``/etc/fstab``, which is not required, ensure that the entries do not have the system automatically mount the disk. 

   ``Note``: Since the file systems will not be mounted automatically during system reboot, it implies that you need to manually mount the file systems after the primary management node reboot. Before mounting the file systems, stop xcat daemon first; after the file systems are mounted, start xcat daemon. 

#. Verify the file systems on the primary management node.

   Verify the file systems could be mounted and written on the primary management node, here is an example: ::

     mount /dev/sdc1 /etc/xcat
     mount /dev/sdc2 /install
     mount /dev/sdc3 ~/.xcat
     mount /dev/sdc4 /db2database

   After that, umount the file system on the primary management node: ::

     umount /etc/xcat
     umount /install
     umount ~/.xcat 
     umount /db2database

#. Verify the file systems on the standby management node.

   On the standby management node, verify the file systems could be mounted and written. ::

     mount /dev/sdc1 /etc/xcat
     mount /dev/sdc2 /install
     mount /dev/sdc3 ~/.xcat
     mount /dev/sdc4 /db2database

   You may get errors "mount: you must specify the filesystem type" or "mount: special device /dev/sdb1 does not exist" when trying to mount the file systems on the standby management node, this is caused by the missing devices files on the standby management node, run ``fidsk /dev/sdx`` and simply select "w write table to disk and exit" in the fdisk menu, then retry the mount. 

   After that, umount the file system on the standby management node: :: 

    umount /etc/xcat
    umount /install
    umount ~/.xcat
    umount /db2database

