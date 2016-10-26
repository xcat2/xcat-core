.. _setup_ha_mgmt_node_with_drbd_pacemaker_corosync:

Setup HA Mgmt Node With DRBD Pacemaker Corosync
================================================

This documentation illustrates how to setup a second management node, or standby management node. **Pacemaker** and **Corosync** are only support ``x86_64`` systems. In your cluster to provide high availability management capability, using several high availability products:

* **DRBD** http://www.drbd.org/ for data replication between the two management nodes.

* **drbdlinks** http://www.tummy.com/Community/software/drbdlinks/ to manage symbolic links from the configuration directories to DRBD storage device.

* **Pacemaker** http://www.clusterlabs.org/ to manage the cluster resources. Note: in RHEL 6.4 and above, the Pacemaker component ``crm`` is replaced with ``pcs``, the Pacemaker configuration on RHEL 6.4 is a little bit different. A sample Pacemaker configuration through the new ``pcs`` is listed in the Appendix A and Appendix B , Appendix A show the configuration with the same corosync and new pcs, Appendix B shows the configuration with ``cman`` and ``pcs``. ``cman`` and ``ccs`` are the preferred and supported HA tools provided from RHEL 6.5 and above corosync is likely to be phased out. This configuration was contributed by some community user, it has not been formally tested by xCAT team, so use this at your own risk.
* **Corosync** http://www.corosync.org for messaging level communication between the two management nodes.

When the primary xCAT management node fails, the standby management node can take over the role of management node automatically, and thus avoid periods of time during which your cluster does not have active cluster management function available.

The nfs service on the primary management node or the primary management node itself will be shutdown during the failover process, so any NFS mount or other network connections from the compute nodes to the management node will be temporarily disconnected during the failover process. If the network connectivity is required for compute node run-time operations, you should consider some other way to provide high availability for the network services unless the compute nodes can also be taken down during the failover process. This also implies:

#. This HAMN approach is primarily intended for clusters in which the management node manages diskful nodes or linux stateless nodes. This also includes hierarchical clusters in which the management node only directly manages the diskful or linux stateless service nodes, and the compute nodes managed by the service nodes can be of any type.

#. If the nodes use only readonly nfs mounts from the MN management node, then you can use this doc as long as you recognize that your nodes will go down while you are failing over to the standby management node.

Setting up HAMN can be done at any time during the life cycle of the cluster, in this documentation we assume the HAMN setup is done from the very beginning of the xCAT cluster setup, there will be some minor differences if the HAMN setup is done from the middle of the xCAT cluster setup.

Configuration Requirements
==========================

#. xCAT HAMN requires that the operating system version, xCAT version and database version all be identical on the two management nodes.

#. The hardware type/model are not required to be identical on the two management nodes, but it is recommended to have similar hardware capability on the two management nodes to support the same operating system and have similar management capability.

#. Since the management node needs to provide IP services through broadcast such as DHCP to the compute nodes, the primary management node and standby management node should be in the same subnet to ensure the network services will work correctly after failover.

#. Network connections between the two management nodes: there are several networks defined in the general cluster configuration strucutre, like cluster network, management network and service network; the two management nodes should be in all of these networks(if exist at all). Besides that, it is recommended, though not strictly required, to use a direct, back-to-back, Gigabit Ethernet or higher bandwidth connection for the DRBD, Pacemaker and Corosync communication between the two management nodes. If the connection is run over switches, use of redundant components and the bonding driver (in active-backup mode) is recommended.

``Note``: A crossover Ethernet cable is required to setup the direct, back-to-back, Ethernet connection between the two management nodes, but with most of the current hardware, a normal Ethernet cable can also work, the Ethernet adapters will internally handle the crossover bit. Hard disk for DRBD: DRBD device can be setup on a partition of the disk that the operating system runs on, but it is recommended to use a separate standalone disk or RAID/Multipath disk for DRBD configuration.

Examples in this doc
====================

The examples in this documentation are based on the following cluster environment: ::

    Virtual login ip address: 9.114.34.4
    Virtual cluster IP alias address: 10.1.0.1
    Primary Management Node: x3550m4n01(10.1.0.221), netmask is 255.255.255.0. Running x86_64 RHEL 6.3 and MySQL 5.1.61.
    Standby Management Node: x3550m4n02(10.1.0.222), netmask is 255.255.255.0. Running x86_64 RHEL 6.3 and MySQL 5.1.61.

The dedicated direct, back-to-back Gigabit Ethernet connection between the two management nodes for ``DRBD``, ``Pacemaker`` and ``Corosync``: ::

    On Primary Management Node: 10.12.0.221
    On Standby Management Node: 10.12.0.222

You need to substitute the hostnames and ip address with your own values when setting up your HAMN environment.

Get the RPM packages
====================

You have several options to get the RPM packages for ``DRBD``, ``drbdlinks``, ``pacemaker`` and ``corosync``:

#. Operating system repository: some of these packages are shipped with the operating system itself, in this case, you can simply install the packages from the operating system repository. For example, RHEL 6.3 ships ``pacemaker`` and ``corosync``.

#. Application website: the application website will usually provides download links for the precompiled RPM packages for some operating systems, you can download the RPM packages from the application website also.

#. Compile from source code: if none of the options work for some specific applications, you will have to compile RPMs from the source code. You can compile these packages on one of the management node or on a separate build machine with the same arch and operating system with the management nodes. Here are the instructions for compiling the RPM packages from source code:

Before compiling the RPM packages, you need to install some compling tools like gcc, make, glibc, rpm-build. ::

    yum groupinstall "Development tools"
    yum install libxslt libxslt-devel

DRBD
----

DRBD binary RPMs heavily depend on the kernel version running on the machine, so it is very likely that you need to compile DRBD on your own. An exception is that DRBD is shipped with SLES 11 SPx High Availability extension, you can download the pre-compiled RPMs from SuSE website, see more details at `https://www.suse.com/products/highavailability/`.

#. Download the latest drbd source code tar ball: ::

    wget http://oss.linbit.com/drbd/8.4/drbd-8.4.2.tar.gz

#. Uncompress the source code tar ball: ::

    tar zxvf drbd-8.4.2.tar.gz

#. Make the RPM packages: ::

    cd drbd-8.4.2
    mkdir -p /root/rpmbuild/SOURCES/
    mkdir -p /root/rpmbuild/RPMS/
    mkdir -p /root/rpmbuild/SPECS/
    ./configure
    make rpm
    make km-rpm

   After the procedure above is finished successfully, all the ``DRBD`` packages are under directory ``/root/rpmbuild/RPMS/x86_64/``: ::

    [root@x3550m4n01 ~]# ls /root/rpmbuild/RPMS/x86_64/drbd*
    /root/rpmbuild/RPMS/x86_64/drbd-8.4.2-2.el6.x86_64.rpm
    /root/rpmbuild/RPMS/x86_64/drbd-bash-completion-8.4.2-2.el6.x86_64.rpm
    /root/rpmbuild/RPMS/x86_64/drbd-debuginfo-8.4.2-2.el6.x86_64.rpm
    /root/rpmbuild/RPMS/x86_64/drbd-heartbeat-8.4.2-2.el6.x86_64.rpm
    /root/rpmbuild/RPMS/x86_64/drbd-km-2.6.32_279.el6.x86_64-8.4.2-2.el6.x86_64.rpm
    /root/rpmbuild/RPMS/x86_64/drbd-km-debuginfo-8.4.2-2.el6.x86_64.rpm
    /root/rpmbuild/RPMS/x86_64/drbd-pacemaker-8.4.2-2.el6.x86_64.rpm
    /root/rpmbuild/RPMS/x86_64/drbd-udev-8.4.2-2.el6.x86_64.rpm
    /root/rpmbuild/RPMS/x86_64/drbd-utils-8.4.2-2.el6.x86_64.rpm
    /root/rpmbuild/RPMS/x86_64/drbd-xen-8.4.2-2.el6.x86_64.rpm

drbdlinks
---------

The ``drbdlinks`` provides a RPM that could be installed on most of the hardware platform and operating system, it could be downloaded from ``ftp://ftp.tummy.com/pub/tummy/drbdlinks/``, so there is no need to compile ``drbdlinks`` in most cases.

Pacemaker
---------

Pacemaker ships as part of all recent Fedora, openSUSE, and SLES(in High Availability Extension). And the project also makes the latest binaries available for Fedora, openSUSE, and EPEL-compatible distributions (RHEL, CentOS, Scientific Linux, etc). So there is no need to compile Pacemaker in most cases.

``Note``: if you choose to use heartbeat instead of corosync in your configuration for whatever reason, you will need to compile the Pacemaker from source code, the version shipped with operating system might not provide all you need.

Corosync
--------

The Corosync is shipped with all recent Fedora, openSUSE, and SLES(in High Availability Extension), so there is no need to compile Pacemaker in most cases.

Setup xCAT on the Primary Management Node
=========================================

Most of the xCAT data will eventually be put on the shared DRBD storage, but you might want to keep a copy of xCAT data on the local disks on the two management nodes, with this local copy, you could get at least one usable management node even if severe problems occur with the HA configuration and the DRBD data is not available any more, although this is unlikely to happen, it does not hurt anything to keep this local copy.

So, in this documentation, we will setup xCAT on both management nodes before we setup DRBD, just to keep the local copies of xCAT data. If you do NOT want to keep these local copies, swap the "Configure DRBD" section with this section, then you will have all the xCAT data on shared DRBD storage.

#. Set up the ``Virtual IP address``. The xcatd daemon should be addressable with the same ``Virtual IP address``, regardless of which management node it runs on. The same ``Virtual IP address`` will be configured as an alias IP address on the management node (primary and standby) that the xcatd runs on. The Virtual IP address can be any unused ip address that all the compute nodes and service nodes could reach. Here is an example on how to configure Virtual IP on Linux: ::

    ifconfig eth2:0 10.1.0.1 netmask 255.255.255.0

   Since ifconfig will not make the ip address configuration be persistent through reboots, so the Virtual IP address needs to be re-configured right after the management node is rebooted. This non-persistent Virtual IP address is designed to avoid ip address conflict when the crashed previous primary management node is recovered with the Virtual IP address configured.

#. Add the alias ip address into the ``/etc/resolv.conf`` as the nameserver. Change the hostname resolution order to be using ``/etc/hosts`` before using name server, change to "hosts: files dns" in ``/etc/nsswitch.conf``.

#. Install xCAT. The procedure described in :doc:`xCAT Install Guide <../../guides/install-guides/index>` should be used for the xCAT setup on the primary management node.

#. Change the site table master and nameservers and network tftpserver attribute to the Virtual ip : ::

    tabdump site

   If not correct: ::

    chdef -t site master=10.1.0.1
    chdef -t site nameservers=10.1.0.1
    chdef -t network 10_1_0_0-255_255_255_0 tftpserver=10.1.0.1

#. Install and configure MySQL. MySQL will be used as the xCAT database system, refer to the doc [ **todo** Setting_Up_MySQL_as_the_xCAT_DB].

   Verify xcat is running on MySQL by running: ::

    lsxcatd -a

#. Add the virtual cluster ip into the MySQL access list: ::

    [root@x3550m4n01 var]$mysql -u root -p
    Enter password:
    Welcome to the MySQL monitor.  Commands end with ; or \g.
    Your MySQL connection id is 11
    Server version: 5.1.61 Source distribution

    Copyright (c) 2000, 2011, Oracle and/or its affiliates. All rights reserved.

    Oracle is a registered trademark of Oracle Corporation and/or its
    affiliates. Other names may be trademarks of their respective
    owners.

    Type 'help;' or '\h' for help. Type '\c' to clear the current input statement.

    mysql>
    mysql> GRANT ALL on xcatdb.* TO xcatadmin@10.1.0.1 IDENTIFIED BY 'cluster';
    Query OK, 0 rows affected (0.00 sec)

    mysql> SELECT host, user FROM mysql.user;
    +------------+-----------+
    | host       | user      |
    +------------+-----------+
    | %          | xcatadmin |
    | 10.1.0.1   | xcatadmin |
    | 10.1.0.221 | xcatadmin |
    | 127.0.0.1  | root      |
    | localhost  |           |
    | localhost  | root      |
    | x3550m4n01 |           |
    | x3550m4n01 | root      |
    +------------+-----------+
    8 rows in set (0.00 sec)

    mysql> quit
    Bye
    [root@x3550m4n01 var]$

#. Make sure the ``/etc/xcat/cfgloc`` points to the virtual ip address

   The ``/etc/xcat/cfglog`` should point to the virtual ip address, here is an example: ::

    mysql:dbname=xcatdb;host=10.1.0.1|xcatadmin|cluster

#. Continue with the nodes provisioning configuration using the primary management node

   Follow the corresponding xCAT docs to continue with the nodes provisioning configuration using the primary management node, including hardware discovery, configure hardware control, configure DNS, configure DHCP, configure conserver, create os image, run nodeset. It is recommended not to start the real os provisioning process until the standby management node setup and HA configuration are done.

   ``Note``: If there are service nodes configured in the cluster, when running makeconservercf to configure conserver, both the virtual ip address and physical ip addresses configured on both management nodes need to be added to the trusted hosts list in conserver, use the command like this: ::

     makeconservercf <node_range> -t <virtual_ip>,<physcial_ip_mn1>,<physical_ip_mn2>

Setup xCAT on the Standby Management Node
=========================================

#. Copy the following files from primary management node: ::

     /etc/resolv.conf
     /etc/hosts
     /etc/nsswitch.conf.

#. Install xCAT. The procedure described in :doc:`xCAT Install Guide <../../guides/install-guides/index>` should be used for the xCAT setup on the standby management node.

#. Install and configure MySQL. MySQL will be used as the xCAT database system, refer to the doc [Setting_Up_MySQL_as_the_xCAT_DB].

   Verify xcat is running on MySQL by running: ::

     lsxcatd -a

#. Copy the xCAT database from primary management node

   On primary management node: ::

     dumpxCATdb -p /tmp/xcatdb
     scp -r /tmp/xcatdb x3550m4n02:/tmp/

   On the standby management node: ::

     restorexCATdb -p /tmp/xcatdb

#. Setup hostname resolution between the primary management node and standby management node. Make sure the primary management node can resolve the hostname of the standby management node, and vice versa.

#. Setup ssh authentication between the primary management node and standby management node. It should be setup as "passwordless ssh authentication" and it should work in both directions. The summary of this procedure is:

   a. cat keys from ``/.ssh/id_rsa.pub`` on the primary management node and add them to ``/.ssh/authorized_keys`` on the standby management node. Remove the standby management node entry from ``/.ssh/known_hosts`` on the primary management node prior to issuing ssh to the standby management node.

   b. cat keys from ``/.ssh/id_rsa.pub`` on the standby management node and add them to ``/.ssh/authorized_keys`` on the primary management node. Remove the primary management node entry from ``/.ssh/known_hosts`` on the standby management node prior to issuing ssh to the primary management node.

#. Make sure the time on the primary management node and standby management node is synchronized.

   Now, do a test reboot on each server, one at a time. This is a sanity check, so that if you have an issue later, you know that it was working before you started. Do NOT skip this step.

Install DRBD, drbdlinks, Pacemaker and Corosync on both management nodes
========================================================================

To avoid RPM dependency issues, it is recommended to use ``yum/zypper`` install the RPMs of DRBD, drbdlinks, Pacemaker and Corosync, here is an example:

#. Put all of these RPM packages into a directory, for example ``/root/hamn/packages``

#. Add a new repository:

   * **[RedHat]**: ::

      [hamn-packages]
      name=HAMN Packages
      baseurl=file:///root/hamn/packages
      enabled=1
      gpgcheck=0

   * **[SLES]**: ::

      zypper ar file:///root/hamn/packages

#. Install the packages:

   * **[RedHat]**: ::

      yum install drbd drbd-bash-completion drbd-debuginfo drbd-km drbd-km-debuginfo drbd-pacemaker  drbd-utils drbd-xen drbd-heartbeat
      yum install drbdlinks
      yum install pacemaker pacemaker-cli pacemaker-cluster-libs pacemaker-libs pacemaker-libs-devel
      yum install corosync corosynclib corosynclib-devel

   * **[SLES]**: ::

      zypper install drbd drbd-bash-completion drbd-debuginfo drbd-km drbd-km-debuginfo drbd-pacemaker  drbd-utils drbd-xen drbd-heartbeat
      zypper install drbdlinks
      zypper install pacemaker pacemaker-cli pacemaker-cluster-libs pacemaker-libs pacemaker-libs-devel
      zypper install corosync corosynclib corosynclib-devel

Turn off init scripts for HA managed services
=============================================

All the HA managed services, including drbd, nfs, nfslock, dhcpd, xcatd, httpd, mysqld, conserver will be controlled by ``pacemaker``. These services should not start on boot. Need to turn off the init scripts for these services on both management nodes. Here is an example: ::

     chkconfig drbd off
     chkconfig nfs off
     chkconfig nfslock off
     chkconfig dhcpd off
     chkconfig xcatd off
     chkconfig httpd off
     chkconfig mysqld off
     chkconfig conserver off

``Note``: The conserver package is optional for xCAT to work, if the conserver is not used in your xCAT cluster, then it is not needed to manage conserver service using ``pacemaker``.

Configure DRBD
==============

``Note``: ``DRBD`` (by convention) uses TCP ports from 7788 upwards, with every resource listening on a separate port. DRBD uses two TCP connections for every resource configured. For proper DRBD functionality, it is required that these connections are allowed by your firewall configuration.

#. Create disk partition for DRBD device

   In this example, we use a separate disk ``/dev/sdb`` for DRBD device, before using ``/dev/sdb`` as the DRBD device, we need to create a partition using either fdisk or parted. The partition size can be determined by the cluster configuration, generally speaking, 100GB should be enough for most cases. The partition size should be the same on the two management nodes, the partition device name need not have the same name on the two management nodes, but it is recommended to have the same partition device name on the two management nodes. After the partition is created, do not create file system on it. Here is an example: ::

    [root@x3550m4n01 ~]# fdisk -l /dev/sdb

    Disk /dev/sdb: 299.0 GB, 298999349248 bytes
    255 heads, 63 sectors/track, 36351 cylinders
    Units = cylinders of 16065 * 512 = 8225280 bytes
    Sector size (logical/physical): 512 bytes / 512 bytes
    I/O size (minimum/optimal): 512 bytes / 512 bytes
    Disk identifier: 0x00000000

     Device Boot      Start         End      Blocks   Id  System
    /dev/sdb1               1       13055   104864256    5  Extended
    /dev/sdb5               1       13055   104864224+  83  Linux

#. Create ``DRBD`` resource configuration file

   All the ``DRBD`` resource configuration files are under ``/etc/drbd.d/``, we need to create a ``DRBD`` resource configuration file for the xCAT HA MN. Here is an example: ::

    [root@x3550m4n01 ~]# cat /etc/drbd.d/xcat.res
     resource xCAT {
       net {
         verify-alg sha1;
         after-sb-0pri discard-least-changes;
         after-sb-1pri consensus;
         after-sb-2pri call-pri-lost-after-sb;
       }
       on x3550m4n01 {
         device    /dev/drbd1;
         disk      /dev/sdb5;
         address   10.12.0.221:7789;
         meta-disk internal;
       }
       on x3550m4n02 {
         device    /dev/drbd1;
         disk      /dev/sdb5;
         address   10.12.0.222:7789;
         meta-disk internal;
       }
     }

   substitute the hostname, device, disk partition and ip address with your own values.

#. Create device metadata

   This step must be completed only on initial device creation. It initializes DRBD.s metadata, it should be run on both management nodes. ::

     [root@x3550m4n01 drbd.d]# drbdadm create-md xCAT
     Writing meta data...
     initializing activity log
     NOT initializing bitmap
     New drbd meta data block successfully created.
     success
     [root@x3550m4n01 drbd.d]#

     [root@x3550m4n02 ~]# drbdadm create-md xCAT
     Writing meta data...
     initializing activity log
     NOT initializing bitmap
     New drbd meta data block successfully created.
     success

#. Enable the resource

   This step associates the resource with its backing device (or devices, in case of a multi-volume resource), sets replication parameters, and connects the resource to its peer. This step should be done on both management nodes. ::

     [root@x3550m4n01 ~]# drbdadm up xCAT
     [root@x3550m4n02 ~]# drbdadm up xCAT

   Observe /proc/drbd. DRBD.s virtual status file in the /proc filesystem, /proc/drbd, should now contain information similar to the following: ::

     [root@x3550m4n01 ~]# cat /proc/drbd
     version: 8.4.2 (api:1/proto:86-101)
     GIT-hash: 7ad5f850d711223713d6dcadc3dd48860321070c build by root@x3550m4n01, 2012-09-14 10:08:13

      1: cs:Connected ro:Secondary/Secondary ds:Inconsistent/Inconsistent C r-----
         ns:0 nr:0 dw:0 dr:0 al:0 bm:0 lo:0 pe:0 ua:0 ap:0 ep:1 wo:f oos:104860984
     [root@x3550m4n01 ~]#

#. Start the initial full synchronization

   This step must be performed on only one node, only on initial resource configuration, and only on the node you selected as the synchronization source. To perform this step, issue this command: ::

    [root@x3550m4n01 ~]# drbdadm primary --force xCAT

   Based on the DRBD device size and the network bandwidth, the initial full synchronization might take a while to finish, in this configuration, a 100GB DRBD device through 1Gb networks takes about 30 minutes. The ``/proc/drbd`` or ``service drbd status`` shows the progress of the initial full synchronization. ::

    version: 8.4.2 (api:1/proto:86-101) GIT-hash: 7ad5f850d711223713d6dcadc3dd48860321070c build by root@x3550m4n01, 2012-09-14 10:08:13

    1: cs:SyncSource ro:Primary/Secondary ds:UpToDate/Inconsistent C r-----
       ns:481152 nr:0 dw:0 dr:481816 al:0 bm:29 lo:0 pe:4 ua:0 ap:0 ep:1 wo:f oos:104380216
           [>....................] sync'ed:  0.5% (101932/102400)M
           finish: 2:29:06 speed: 11,644 (11,444) K/sec

   If a direct, back-to-back Gigabyte Ethernet connection is setup between the two management nodes and you are unhappy with the syncronization speed, it is possible to speed up the initial synchronization through some tunable parameters in DRBD. This setting is not permanent, and will not be retained after boot. For details, see http://www.drbd.org/users-guide-emb/s-configure-sync-rate.html.  ::

     drbdadm disk-options --resync-rate=110M xCAT

#. Create file system on DRBD device and mount the file system

   Even while the DRBD sync is taking place, you can go ahead and create a filesystem on the DRBD device, but it is recommended to wait for the inital full synchronization is finished before creating the file system.

   After the initial full synchronization is finished, you can take the DRBD device as a normal disk partition to create file system and mount it to some directory. The DRDB device name is set in the ``/etc/drbd.d/xcat.res`` created in the previous step. In this doc, the DRBD device name is ``/dev/drbd1``. ::

     [root@x3550m4n01]# mkfs -t ext4 /dev/drbd1
       ... ...
     [root@x3550m4n01]# mkdir /xCATdrbd
     [root@x3550m4n01]# mount /dev/drbd1 /xCATdrbd

   To test the file system is working correctly, create a test file: ::

     [root@x3550m4n01]# echo "this is a test file" > /xCATdrbd/testfile
     [root@x3550m4n01]# cat /xCATdrbd/testfile
     this is a test file
     [root@x3550m4n01]#

   ``Note``: make sure the DRBD initial full synchronization is finished before taking any subsequent step.

#. Test the ``DRBD`` failover

   To test the ``DRBD`` failover, you need to change the primary/secondary role on the two management nodes.

   On the ``DRDB`` primary server(x3550m4n01): ::

     [root@x3550m4n01 ~]# umount /xCATdrbd
     [root@x3550m4n01 ~]# drbdadm secondary xCAT

   Then the ``service drbd status`` shows both management nodes are now "Secondary" servers.::

     [root@x3550m4n01 ~]# service drbd status
     drbd driver loaded OK; device status:
     version: 8.4.2 (api:1/proto:86-101)
     GIT-hash: 7ad5f850d711223713d6dcadc3dd48860321070c build by root@x3550m4n01, 2012-09-14 10:36:39
     m:res   cs         ro                   ds                 p  mounted  fstype
     1:xCAT  Connected  Secondary/Secondary  UpToDate/UpToDate  C
     [root@x3550m4n01 ~]#

   On the ``DRBD`` secondary server(x3550m4n02): ::

     [root@x3550m4n02 ~]# drbdadm primary xCAT

   Then the ``service drbd status`` shows the new primary DRBD server is x3550m4n02: ::

     [root@x3550m4n02 ~]# service drbd status
     drbd driver loaded OK; device status:
     version: 8.4.2 (api:1/proto:86-101)
     GIT-hash: 7ad5f850d711223713d6dcadc3dd48860321070c build by root@x3550m4n01, 2012-09-14 10:36:39
     m:res   cs         ro                 ds                 p  mounted  fstype
     1:xCAT  Connected  Primary/Secondary  UpToDate/UpToDate  C

   Mount the ``DRBD`` device to the directory ``/xCATdrbd`` on the new DRBD primary server, verify the file system is synchronized: ::

     [root@x3550m4n02 ~]# mount /dev/drbd1 /xCATdrbd
     [root@x3550m4n02]# cat /xCATdrbd/testfile
     this is a test file
     [root@x3550m4n02]#

   Before proceed with the following steps, you need to failover the DRBD primary server back to x3550m4n01, using the same procedure mentioned above.

Configure drbdlinks
===================

The drbdlinks configuration is quite easy, only needs to create a configuration file, say ``/xCATdrbd/etc/drbdlinks.xCAT.conf``, and then run ``drbdlinks`` command to manage the symbolic links.

Note: There are three relative symbolic links in the web server (apache/httpd) files, needs to change them to be absolute links . or the web server won't start. Run the following commands on both management nodes: ::

     rm /etc/httpd/logs ; ln -s /var/log/httpd /etc/httpd/logs
     rm /etc/httpd/modules ; ln -s /usr/lib64/httpd/modules /etc/httpd/modules
     rm /etc/httpd/run ; ln -s /var/run/httpd /etc/httpd/run

Here is an example of the ``/xCATdrbd/etc/drbdlinks.xCAT.conf`` content, you might need to edit ``/xCATdrbd/etc/drbdlinks.xCAT.conf`` to reflect your needs. For example, if you are managing DNS outside of xCAT, you will not need to manage the DNS service via drbdlinks or pacemaker.::

     [root@x3550m4n01 ~]# cat /xCATdrbd/etc/drbdlinks.xCAT.conf
     #
     #  Sample configuration file for drbdlinks
     #  If passed an option of 1, SELinux features will be used.  If 0, they
     #  will not.  The default is to auto-detect if SELinux is enabled.  If
     #  enabled, created links will be added to the SELinux context using
     #  chcon -h -u <USER> -r <ROLE> -t <TYPE>, where the values plugged
     #  in this command are pulled from the original file.
     #selinux(1)

     #  One mountpoint must be listed.  This is the location where the DRBD
     #  drive is mounted.
     #mountpoint('/shared')

     #  Multiple "link" lines may be listed, one for each link that needs to be
     #  set up into the above shared mountpoint.  If "link()" is passed one
     #  argument, it is assumed that it is linked into that name under the
     #  mountpoint above.  Otherwise, you can specify a second argument which is
     #  the location of the file on the shared partition.
     #
     #  For example, if mountpoint is "/shared" and you call "link('/etc/httpd')",
     #  it is equivalent to calling "link('/etc/httpd', '/shared/etc/httpd')".
     #link('/etc/httpd')
     #link('/var/lib/pgsql/')
     #
     #
     #       services mounted under /xCATdrbd
     #
     restartSyslog(1)
     cleanthisconfig(1)
     mountpoint('/xCATdrbd')
     # ==== xCAT ====
     link('/install')
     link('/etc/xcat')
     link('/opt/xcat')
     link('/root/.xcat')
     # Hosts is a bit odd - may just want to rsync out...
     link('/etc/hosts')
     # ==== Conserver ====
     link('/etc/conserver.cf')
     # ==== DNS ====
     #link('/etc/named')
     #link('/etc/named.conf')
     #link('/etc/named.iscdlv.key')
     #link('/etc/named.rfc1912.zones')
     #link('/etc/named.root.key')
     #link('/etc/rndc.conf')
     #link('/etc/rndc.key')
     #link('/etc/sysconfig/named')
     #link('/var/named')
     # ==== YUM ====
     link('/etc/yum.repos.d')
     # ==== DHCP ====
     link('/etc/dhcp')
     link('/var/lib/dhcpd')
     link('/etc/sysconfig/dhcpd')
     link('/etc/sysconfig/dhcpd6')
     # ==== Apache ====
     link('/etc/httpd')
     link('/var/www')
     #
     # ==== MySQL ====
     link('/etc/my.cnf')
     link('/var/lib/mysql')
     #
     # ==== tftp ====
     link('/tftpboot')
     #
     # ==== NFS ====
     link('/etc/exports')
     link('/var/lib/nfs')
     link('/etc/sysconfig/nfs')
     #
     # ==== SSH  ====
     link('/etc/ssh')
     link('/root/.ssh')
     #
     # ==== SystemImager ====
     #link('/etc/systemimager')

``Note``: Make sure that none of the directories we have specified in the ``drbdlinks`` config are not mount points. If any of them are, we should a new mount point for them and edit ``/etc/fstab`` to use the new mount point.

Then run the following commands to create the symbolic links: ::

     [root@x3550m4n01]# drbdlinks -c  /xCATdrbd/etc/drbdlinks.xCAT.conf initialize_shared_storage
     [root@x3550m4n01]# drbdlinks -c /xCATdrbd/etc/drbdlinks.xCAT.conf start

Configure Corosync
==================

#. Create ``/etc/corosync/corosync.conf``

   The ``/etc/corosync/corosync.conf`` is the configuration file for Corosync, you need to modify the ``/etc/corosync/corosync.conf`` according to the cluster configuration.::

     [root@x3550m4n01]#cp /etc/corosync/corosync.conf.example /etc/corosync/corosync.conf

   Modify the ``/etc/corosync/corosync.conf``, the default configuration of Corosync uses multicast to discover the cluster members in the subnet, since this cluster only has two members and no new members will join the cluster, so we can hard code the members for this cluster.::

     [root@x3550m4n01 ~]# cat /etc/corosync/corosync.conf
     # Please read the corosync.conf.5 manual page
     compatibility: whitetank

     totem {
             version: 2
             secauth: off
             interface {
                     member {
                             memberaddr: 10.12.0.221
                     }
                     member {
                             memberaddr: 10.12.0.222
                     }
                     ringnumber: 0
                     bindnetaddr: 10.12.0.0
                     mcastport: 5405
                     ttl: 1
             }
             transport: udpu
     }

     logging {
             fileline: off
             to_logfile: yes
             to_syslog: yes
             logfile: /var/log/cluster/corosync.log
             debug: off
             timestamp: on
             logger_subsys {
                     subsys: AMF
                     debug: off
             }
     }

#. Create the service file for Pacemaker:

   To have Corosync call Pacemaker, a configuration file needs to be created under the directory ``/etc/corosync/service.d/``. Here is an example: ::

     [root@x3550m4n01 ~]# cat /etc/corosync/service.d/pcmk
     service {
             # Load the Pacemaker Cluster Resource Manager
             name: pacemaker
             ver: 0
     }

#. Copy the Corosync configuration files to standby management node

   The Corosync configuration files are needed on both the primary and standby management node, copy these configuration files to the standby management node. ::

     [root@x3550m4n01 ~]# scp /etc/corosync/corosync.conf x3550m4n02:/etc/corosync/corosync.conf

     [root@x3550m4n01 ~]# scp /etc/corosync/service.d/pcmk x3550m4n02:/etc/corosync/service.d/pcmk

#. Star Corosync

   Start Corosync on both management nodes by running: ::

     service corosync start

#. Verify the cluster status

   If the setup is correct, the cluster should now be up and running, the Pacemaker command crm_mon could show the cluster status.::

     crm_mon

     ============
     Last updated: Thu Sep 20 12:23:37 2012
     Last change: Thu Sep 20 12:23:23 2012 via cibadmin on x3550m4n01
     Stack: openais
     Current DC: x3550m4n01 - partition with quorum
     Version: 1.1.7-6.el6-148fccfd5985c5590cc601123c6c16e966b85d14
     2 Nodes configured, 2 expected votes
     0 Resources configured.
     ============

     Online: [ x3550m4n01 x3550m4n02 ]

   The cluster initialization procedure might take a short while, you can also monitor the crososync log file ``/var/log/cluster/corosync.log`` for the cluster initialization progress, after the cluster initialization process is finished, there will be some message like "Completed service synchronization, ready to provide service." in the corosync log file.

Configure Pacemaker
===================

``Note``: a temporary workaround: the ``/etc/rc.d/init.d/conserver`` shipped with conserver-xcat is not lsb compliant, will cause ``pacemaker`` problems, we need to modify the ``/etc/rc.d/init.d/conserver`` to be lsb compliant before we create ``pacemaker`` resources for conserver. xCAT will be fixing this problem in the future, but for now, we have to use this temporary workaround: ::

     diff -ruN conserver conserver.xcat
     --- conserver   2012-03-20 00:56:46.000000000 +0800
     +++ conserver.xcat      2012-09-25 17:03:57.703159703 +0800
     @@ -84,9 +84,9 @@
        stop)
          $STATUS conserver >& /dev/null
          if [ "$?" != "0" ]; then
     -        echo -n "conserver not running, already stopped. "
     +        echo -n "conserver not running, not stopping "
              $PASSED
     -        exit 0
     +        exit 1
          fi
          echo -n "Shutting down conserver: "
          killproc conserver
     @@ -100,7 +100,6 @@
          ;;
        status)
          $STATUS conserver
     -    exit $?
          ;;
        restart)
          $STATUS conserver >& /dev/null

All the cluster resources are managed by Pacemaker, here is an example ``pacemaker`` configuration that has been used by different HA MN customers. You might need to do some minor modifications based on your cluster configuration.

Be aware that you need to apply ALL the configuration at once. You cannot pick and choose which pieces to put in, and you cannot put some in now, and some later. Don't execute individual commands, but use crm configure edit instead. ::

     node x3550m4n01
     node x3550m4n02
     #
     #       NFS server - monitored by 'status' operation
     #
     primitive NFS_xCAT lsb:nfs \
             op start interval="0" timeout="120s" \
             op stop interval="0" timeout="120s" \
             op monitor interval="41s"
     #
     #       NFS Lock Daemon - monitored by 'status' operation
     #
     primitive NFSlock_xCAT lsb:nfslock \
             op start interval="0" timeout="120s" \
             op stop interval="0" timeout="120s" \
             op monitor interval="43s"
     #
     #       Apache web server - we monitor it by doing wgets on the 'statusurl' and looking for 'testregex'
     #
     primitive apache_xCAT ocf:heartbeat:apache \
             op start interval="0" timeout="600s" \
             op stop interval="0" timeout="120s" \
             op monitor interval="57s" timeout="120s" \
             params configfile="/etc/httpd/conf/httpd.conf" statusurl="http://localhost:80/icons/README.html" testregex="</html>" \
             meta target-role="Started"
     #
     #       MySQL for xCAT database.  We monitor it by doing a trivial query that will always succeed.
     #
     primitive db_xCAT ocf:heartbeat:mysql \
             params config="/xCATdrbd/etc/my.cnf" test_user="mysql" binary="/usr/bin/mysqld_safe" pid="/var/run/mysqld/mysqld.pid" socket="/var/lib/mysql/mysql.sock" \
             op start interval="0" timeout="600" \
             op stop interval="0" timeout="600" \
             op monitor interval="57" timeout="120"
     #
     #       DHCP daemon - monitored by 'status' operation
     #
     primitive dhcpd lsb:dhcpd \
             op start interval="0" timeout="120s" \
             op stop interval="0" timeout="120s" \
             op monitor interval="37s"
     #
     #       DRBD filesystem replication (single instance)
     #       DRBD is a master/slave resource
     #
     primitive drbd_xCAT ocf:linbit:drbd \
             params drbd_resource="xCAT" \
             op start interval="0" timeout="240" \
             op stop interval="0" timeout="120s" \
             op monitor interval="17s" role="Master" timeout="120s" \
             op monitor interval="16s" role="Slave" timeout="119s"
     #
     #       Dummy resource that starts after all other
     #       resources have started
     #
     primitive dummy ocf:heartbeat:Dummy \
             op start interval="0" timeout="600s" \
             op stop interval="0" timeout="120s" \
             op monitor interval="57s" timeout="120s" \
             meta target-role="Started"
     #
     #       Filesystem resource - mounts /xCATdrbd - monitored by checking to see if it
     #       is still mounted.  Other options are available, but not currently used.
     #
     primitive fs_xCAT ocf:heartbeat:Filesystem \
             op start interval="0" timeout="600s" \
             op stop interval="0" timeout="120s" \
             op monitor interval="57s" timeout="120s" \
             params device="/dev/drbd/by-res/xCAT" directory="/xCATdrbd" fstype="ext4"
     #TODO TODO TODO TODO TODO TODO TODO TODO TODO TODO TODO TODO TODO TODO TODO TODO
     #
     #       Extra external IP bound to the active xCAT instance - monitored by ping
     #
     primitive ip_IBM ocf:heartbeat:IPaddr2 \
            params ip="9.114.34.4" iflabel="blue" nic="eth3" cidr_netmask="24" \
            op start interval="0" timeout="120s" \
            op stop interval="0" timeout="120s" \
            op monitor interval="37s" timeout="120s"
     #
     #       Unneeded IP address - monitored by ping
     #
     #primitive ip_dhcp1 ocf:heartbeat:IPaddr2 \
     #       params ip="10.5.0.1" iflabel="dh" nic="bond-mlan.30" cidr_netmask="16" \
     #       op start interval="0" timeout="120s" \
     #       op stop interval="0" timeout="120s" \
     #       op monitor interval="37s" timeout="120s"
     #
     #       Another unneeded IP address - monitored by ping
     #
     #primitive ip_dhcp2 ocf:heartbeat:IPaddr2 \
     #       params ip="10.6.0.1" iflabel="dhcp" nic="eth2.30" cidr_netmask="16" \
     #       op start interval="0" timeout="120s" \
     #       op stop interval="0" timeout="120s" \
     #       op monitor interval="39s" timeout="120s"
     #
     #       IP address for SNMP traps - monitored by ping
     #
     #primitive ip_snmp ocf:heartbeat:IPaddr2
     #       params ip="10.1.0.1" iflabel="snmp" nic="eth2" cidr_netmask="16"
     #       op start interval="0" timeout="120s"
     #       op stop interval="0" timeout="120s"
     #       op monitor interval="37s" timeout="120s"
     #
     # END TODO TODO TODO TODO TODO TODO TODO TODO TODO TODO TODO TODO TODO TODO TODO
     #       Main xCAT IP address - monitored by ping
     #
     primitive ip_xCAT ocf:heartbeat:IPaddr2 \
             params ip="10.1.0.1" iflabel="xCAT" nic="eth2" cidr_netmask="24" \
             op start interval="0" timeout="120s" \
             op stop interval="0" timeout="120s" \
             op monitor interval="37s" timeout="120s"
     #
     #
     #       BIND DNS daemon (named) - monitored by 'status' operation
     #
     primitive named lsb:named \
             op start interval="0" timeout="120s" \
             op stop interval="0" timeout="120s" \
             op monitor interval="37s"
     #
     #       DRBDlinks resource to manage symbolic links - monitored by checking symlinks
     #
     primitive symlinks_xCAT ocf:tummy:drbdlinks \
             params configfile="/xCATdrbd/etc/drbdlinks.xCAT.conf" \
             op start interval="0" timeout="600s" \
             op stop interval="0" timeout="120s" \
             op monitor interval="31s" timeout="120s"
     #
     #       Custom xCAT Trivial File Transfer Protocol daemon for
     #       booting diskless machines - monitored by 'status' operation
     #
     #primitive tftpd lsb:tftpd \
     #       op start interval="0" timeout="120s" \
     #       op stop interval="0" timeout="120s" \
     #       op monitor interval="41s"
     #
     #       Main xCAT daemon
     #       xCAT is best understood and modelled as a master/slave type
     #       resource - but we don't do that yet.  If it were master/slave
     #       we could easily take the service nodes into account.
     #       We just model it as an LSB init script resource :-(.
     #       Monitored by 'status' operation
     #
     primitive xCAT lsb:xcatd \
             op start interval="0" timeout="120s" \
             op stop interval="0" timeout="120s" \
             op monitor interval="42s" \
             meta target-role="Started"
     #
     #       xCAT console server - monitored by 'status' operation
     #
     primitive xCAT_conserver lsb:conserver \
             op start interval="0" timeout="120s" \
             op stop interval="0" timeout="120s" \
             op monitor interval="53"
     #
     # Group consisting only of filesystem and its symlink setup
     #
     group grp_xCAT fs_xCAT symlinks_xCAT
     #
     # Typical Master/Slave DRBD resource - mounted as /xCATdrbd elsewhere
     # We configured it as a single master resource - with only the master side being capable of
     # being written (i.e., mounted)
     #
     ms ms_drbd_xCAT drbd_xCAT \
             meta master-max="1" master-node-max="1" clone-max="2" clone-node-max="1" notify="true"
     #
     #       We model 'named' as a clone resource and set up /etc/resolv.conf as follows:
     #               virtual IP
     #               permanent IP of one machine
     #               permanent IP of the other machine
     #
     #       This helps cut us a little slack in DNS resolution during failovers.  We made it a
     #       clone resource rather than just a regular resource because named binds to all existing addresses
     #       when it starts and (a) never notices any added after it starts and (b) shuts down if any of the
     #       IPs it bound to go away after it starts up.  So we need to coordinate it with bringing up and
     #       down our IP addresses.
     #
     clone clone_named named \
             meta clone-max="2" clone-node-max="1" notify="false"
     #
     #       NFS needs to be on same machine as its filesystem
     colocation colo1 inf: NFS_xCAT grp_xCAT
     # TODO
     colocation colo10 inf: ip_dhcp2 ms_drbd_xCAT:Master
     #colocation colo11 inf: ip_IBM ms_drbd_xCAT:Master
     # END TODO
     #       NFS lock daemon needs to be on same machine as its filesystem
     colocation colo2 inf: NFSlock_xCAT grp_xCAT
     # TODO
     #       SNMP IP needs to be on same machine as xCAT
     #colocation colo3 inf: ip_snmp grp_xCAT
     # END TODO
     #       Apache needs to be on same machine as xCAT
     colocation colo4 inf: apache_xCAT grp_xCAT
     #       DHCP needs to be on same machine as xCAT
     colocation colo5 inf: dhcpd grp_xCAT
     #       tftpd needs to be on same machine as xCAT
     #colocation colo6 inf: tftpd grp_xCAT
     #       Console Server needs to be on same machine as xCAT
     colocation colo7 inf: xCAT_conserver grp_xCAT
     #       MySQL needs to be on same machine as xCAT
     colocation colo8 inf: db_xCAT grp_xCAT
     # TODO
     #colocation colo9 inf: ip_dhcp1 ms_drbd_xCAT:Master
     # END TODO
     #       Dummy resource needs to be on same machine as xCAT (not really necessary)
     colocation dummy_colocation inf: dummy xCAT
     #       xCAT group (filesystem and symlinks) needs to be on same machine as DRBD master
     colocation grp_xCAT_on_drbd inf: grp_xCAT ms_drbd_xCAT:Master
     #       xCAT IP address needs to be on same machine as DRBD master
     colocation ip_xCAT_on_drbd inf: ip_xCAT ms_drbd_xCAT:Master
     #       xCAT itself needs to be on same machine as xCAT filesystem
     colocation xCAT_colocation inf: xCAT grp_xCAT
     #       Lots of things need to start after the filesystem is mounted
     order Most_aftergrp inf: grp_xCAT ( NFS_xCAT NFSlock_xCAT apache_xCAT db_xCAT xCAT_conserver dhcpd )
     #       Some things will bind to the IP and therefore need to start after the IP
     #       Note that some of these also have to start after the filesystem is mounted
     order Most_afterip inf: ip_xCAT ( apache_xCAT db_xCAT xCAT_conserver )
     # TODO
     #order after_dhcp1 inf: ip_dhcp1 dhcpd
     #order after_dhcp2 inf: ip_dhcp2 dhcpd
     # END TODO
     #       We start named after we start the xCAT IP
     #       Note that both sides are restarted every time the IP moves.
     #       This prevents the problems with named not liking IP addresses coming and going.
     order clone_named_after_ip_xCAT inf: ip_xCAT clone_named
     order dummy_order0 inf: NFS_xCAT dummy
     #
     #       We make the dummy resource start after basically all other resources
     #
     order dummy_order1 inf: xCAT dummy
     order dummy_order2 inf: NFSlock_xCAT dummy
     order dummy_order3 inf: clone_named dummy
     order dummy_order4 inf: apache_xCAT dummy
     order dummy_order5 inf: dhcpd dummy
     #order dummy_order6 inf: tftpd dummy
     order dummy_order7 inf: xCAT_conserver dummy
     # TODO
     #order dummy_order8 inf: ip_dhcp1 dummy
     #order dummy_order9 inf: ip_dhcp2 dummy
     # END TODO
     #       We mount the filesystem and set up the symlinks afer DRBD is promoted to master
     order grp_xCAT_after_drbd_xCAT inf: ms_drbd_xCAT:promote grp_xCAT:start
     #       xCAT has to start after its database (mySQL)
     order xCAT_dborder inf: db_xCAT xCAT
     property $id="cib-bootstrap-options" \
             dc-version="1.1.7-6.el6-148fccfd5985c5590cc601123c6c16e966b85d14" \
             cluster-infrastructure="openais" \
             expected-quorum-votes="2" \
             stonith-enabled="false" \
             no-quorum-policy="ignore" \
             last-lrm-refresh="1348180592"

Cluster Maintenance Considerations
==================================

The standby management node should be taken into account when doing any maintenance work in the xCAT cluster with HAMN setup.

#. Software Maintenance - Any software updates on the primary management node should also be done on the standby management node.

#. File Synchronization - Although we have setup crontab to synchronize the related files between the primary management node and standby management node, the crontab entries are only run in specific time slots. The synchronization delay may cause potential problems with HAMN, so it is recommended to manually synchronize the files mentioned in the section above whenever the files are modified.

#. Reboot management nodes - In the primary management node needs to be rebooted, since the daemons are set to not auto start at boot time, and the shared disks file systems will not be mounted automatically, you should mount the shared disks and start the daemons manually.

#. Update xCAT - We should avoid failover during the xCAT upgrade, the failover will cause drbd mount changes, since the xCAT upgrade procedure needs to restart xcatd for one or more times, it will likely trigger failover. So it will be safer if we put the backup xCAT MN in inactive state while updating the xCAT MN, through either stopping corosync+pacemaker on the back xCAT MN or shutdown the backup xCAT MN. After the primary MN is upgraded, make the backup MN be active, failover to the backup MN, put the primary MN be inactive, and then update the backup xCAT MN.

``Note``: after software upgrade, some services that were set to not autostart on boot might be started by the software upgrade process, or even set to autostart on boot, the admin should check the services on both primary and standby EMS, if any of the services are set to autostart on boot, turn it off; if any of the services are started on the backup EMS, stop the service.

At this point, the HA MN Setup is complete, and customer workloads and system administration can continue on the primary management node until a failure occurs. The xcatdb and files on the standby management node will continue to be synchronized until such a failure occurs.

Failover
========

There are two kinds of failover, planned failover and unplanned failover. The planned failover can be useful for updating the management nodes or any scheduled maintainance activities; the unplanned failover covers the unexpected hardware or software failures.

In a planned failover, you can do necessary cleanup work on the previous primary management node before failover to the previous standby management node. In a unplanned failover, the previous management node probably is not functioning at all, you can simply shutdown the system.

But, both the planned failover and unplanned failover are fully automatic, the administrator does not need to do anything else.

On the current primary management node, if the current primary management node is still available to run commands, run the following command to cleanup things: ::

     service corosync stop

You can run ``crm resource list`` to see which node is the current primary management node: ::

    [root@x3550m4n01 html]# crm resource list
      NFS_xCAT       (lsb:nfs) Started
      NFSlock_xCAT   (lsb:nfslock) Started
      apache_xCAT    (ocf::heartbeat:apache) Started
      db_xCAT        (ocf::heartbeat:mysql) Started
      dhcpd  (lsb:dhcpd) Started
      dummy  (ocf::heartbeat:Dummy) Started
      ip_xCAT        (ocf::heartbeat:IPaddr2) Started
      xCAT   (lsb:xcatd) Started
      xCAT_conserver (lsb:conserver) Started
      Resource Group: grp_xCAT
          fs_xCAT    (ocf::heartbeat:Filesystem) Started
          symlinks_xCAT      (ocf::tummy:drbdlinks) Started
      Master/Slave Set: ms_drbd_xCAT [drbd_xCAT]
          Masters: [ x3550m4n01 ]
          Slaves: [ x3550m4n02 ]
      Clone Set: clone_named [named]
          Started: [ x3550m4n02 x3550m4n01 ]
      ip_IBM (ocf::heartbeat:IPaddr2) Started

The "Masters" of ms_drbd_xCAT should be the current primary management node.

If any of the management node is rebooted for whatever reason while the HA MN configuration is up and running, you might need to start the corosync service manually. ::

     service corosync start

To avoid this, run the following command to set the autostart for the corosync service on both management nodes: ::

     chkconfig corosync on

Backup working Pacemaker configuration (Optional)
=================================================

It is a good practice to backup the working ``pacemaker`` configuration, the backup could be in both plain text format or XML format, the plain text is more easily editable and can be modified and used chunk by chunk, the xml can be used to do a full replacement restore. It will be very useful to make such a backup everytime before you make a change.

To backup in the plain text format, run the following command: ::

     crm configure save /path/to/backup/textfile

To backup in the xml format, run the following command: ::

     crm configure save xml /path/to/backup/xmlfile

If necessary, the backup procedure can be done periodically through crontab or at, here is an sample script that will backup the ``pacemaker`` configuration automatically: ::

     TXT_CONFIG=/xCATdrbd/pacemakerconfigbackup/pacemaker.conf.txt-$(hostname -s).$(date +"%Y.%m.%d.%H.%M.%S")
     XML_CONFIG=/xCATdrbd/pacemakerconfigbackup/pacemaker.conf.xml-$(hostname -s).$(date +"%Y.%m.%d.%H.%M.%S")
     test -e $TXT_CONFIG && /bin/cp -f $TXT_CONFIG $TXT_CONFIG.bak
     test -e $XML_CONFIG && /bin/cp -f $XML_CONFIG $XML_CONFIG.bak
     crm configure save     $TXT_CONFIG
     crm configure save xml $XML_CONFIG

To restore the ``pacemaker`` configuration from the backup xml file. ::

     crm configure load replace /path/to/backup/xmlfile

Correcting DRBD Differences (Optional)
======================================

It is possible that the data between the two sides of the DRBD mirror could be different in a few chunks of data, although these differences might be harmless, but it will be good if we could discover and fix these differences in time.

Add a crontab entry to check the differences
--------------------------------------------
 ::

     0 6 * * * /sbin/drbdadm verify all

Note that this process will take a few hours. You could schedule it at a time when it can be expected to run when things are relatively idle. You might choose to only run it once a week, but nightly seems to be a nice choice as well. You should only put this cron job on one side or the other of the DRBD mirror . not both.

Correcting the differences automatically
----------------------------------------

The crontab entry mentioned above will discover differences between the two sides, but will not correct any it might find. This section describes a method for automatically correcting those differences.

There are basically three reasons why this might happen:

1. A series of well-known Linux kernel bugs that have only been recently fixed and do not yet appear in any version of RHEL. All of them are known to be harmless.

2. Hardware failure - one side stored the data on disk incorrectly ,

3. Other Bugs. I don't know of any - but all software has bugs.

We do see occasional 4K chunks of data differing between the two sides of the mirror. As long as there are only a handful of them, it is almost certainly due to the harmless bugs mentioned above.

There is also a script, say drbdforceresync, which has been written to force correction of the two sides. It should be run on both sides an hour or so after the verify process kicked off after the cron job has completed. The script written for this purpose is shown below: ::

    #version: 8.4.0 (api:1/proto:86-100)
    #GIT-hash: 28753f559ab51b549d16bcf487fe625d5919c49c build by root@wbsm15-mgmt01, 2011-11-17 18:14:37
    #
    # 1: cs:Connected ro:Secondary/Primary ds:UpToDate/UpToDate C r-----
    #    ns:0 nr:301816 dw:14440824 dr:629126328 al:0 bm:206 lo:0 pe:0 ua:0 ap:0 ep:1 wo:b oos:0
    #
    #   Force a DRBD resync
    #
    force_resync() {
       echo "Disconnecting and reconnecting DRBD resource $1."
       drbdadm disconnect $1
       drbdadm connect $1
    }
    #
    #   Convert a DRBD resource name to a device number
    #
    resource2devno() {
       dev=$(readlink /dev/drbd/by-res/$1)
       echo $dev | sed 's%.*/drbd%%'
    }

    #
    #   Force a DRBD resync if we are in the secondary role
    #
    check_resync() {
       # We should only do the force_resync if we are the secondary
       resource=$1
       whichdev=$(resource2devno $resource)
       DRBD=$(cat /proc/drbd | grep "^ *${whichdev}: *cs:")
       # It would be nice if to know for sure that the ds: for the secondary
       # role would be when it has known issues...
       # Then we could do this only when strictly necessary
       case "$DRBD" in
           *${whichdev}:*'cs:Connected'*'ro:Secondary/Primary'*/UpToDate*)
                       force_resync $resource;;
       esac
    }

``Note``: this script has been tested in some HAMN clusters, and uses the DRBD-recommended method of forcing a resync (a disconnect/reconnect). If there are no differences, this script causes near-zero DRBD activity. It is only when there are differences that the disconnect/reconnect sequence does anything. So, it is recommended to add this script into crontab also, like: ::

     0 6 * * 6   /sbin/drbdforceresync

Setup the Cluster
=================

At this point you have setup your Primary and Standby management node for HA. You can now continue to setup your cluster. Return to using the Primary management node. Now setup your Hierarchical cluster using the following documentation, depending on your Hardware,OS and type of install you want to do on the Nodes :doc:`Admin Guide <../../guides/admin-guides/index>`.

For all the xCAT docs: http://xcat-docs.readthedocs.org.

Trouble shooting and debug tips
===============================

#. ``Pacemaker`` resources could not start

   In case some of the ``pacemaker`` resources could not start, it mainly because the corresponding service(like xcatd) has some problem and could not be started, after the problem is fixed, the ``pacemaker`` resource status will be updated soon, or you can run the following command to refresh the status immediately. ::

     crm resource cleanup <resource_name>

#. Add new ``Pacemaker`` resources into configuration file

   If you want to add your own ``Pacemaker`` resources into the configuration file, you might need to lookup the table on which resources are available in ``Pacemaker``, use the following commands: ::

     [root@x3550m4n01 ~]#crm ra
     crm(live)ra# classes
     heartbeat
     lsb
     ocf / heartbeat linbit pacemaker redhat tummy
     stonith
     crm(live)ra# list ocf
     ASEHAagent.sh         AoEtarget             AudibleAlarm          CTDB                  ClusterMon
     Delay                 Dummy                 EvmsSCC               Evmsd                 Filesystem
     HealthCPU             HealthSMART           ICP                   IPaddr                IPaddr2
     IPsrcaddr             IPv6addr              LVM                   LinuxSCSI             MailTo
     ManageRAID            ManageVE              Pure-FTPd             Raid1                 Route
     SAPDatabase           SAPInstance           SendArp               ServeRAID             SphinxSearchDaemon
     Squid                 Stateful              SysInfo               SystemHealth          VIPArip
     VirtualDomain         WAS                   WAS6                  WinPopup              Xen
     Xinetd                anything              apache                apache.sh             clusterfs.sh
     conntrackd            controld              db2                   drbd                  drbdlinks
     eDir88                ethmonitor            exportfs              fio                   fs.sh
     iSCSILogicalUnit      iSCSITarget           ids                   ip.sh                 iscsi
     jboss                 lvm.sh                lvm_by_lv.sh          lvm_by_vg.sh          lxc
     mysql                 mysql-proxy           mysql.sh              named.sh              netfs.sh
     nfsclient.sh          nfsexport.sh          nfsserver             nfsserver.sh          nginx
     o2cb                  ocf-shellfuncs        openldap.sh           oracle                oracledb.sh
     orainstance.sh        oralistener.sh        oralsnr               pgsql                 ping
     pingd                 portblock             postfix               postgres-8.sh         proftpd
     rsyncd                samba.sh              script.sh             scsi2reservation      service.sh
     sfex                  svclib_nfslock        symlink               syslog-ng             tomcat
     tomcat-6.sh           vm.sh                 vmware
     crm(live)ra# meta IPaddr2
     ...

     Operations' defaults (advisory minimum):

       start         timeout=20s
       stop          timeout=20s
       status        interval=10s timeout=20s
       monitor       interval=10s timeout=20s
     crm(live)ra# providers IPaddr2
     heartbeat
     crm(live)ra#

#. Fixing drbd split brain

   The machine that has taken over as the primary, lets say it's x3550m4n01, and x3550m4n02 has been left stranded, then we need to run the following commands to fix the problem

   * **x3550m4n02** ::

        drbdadm disconnect xCAT
        drbdadm secondary xCAT
        drbdadm connect --discard-my-data xCAT

   * **x3550m4n01** ::

        drbdadm connect xCAT

Disable HA MN
=============

For whatever reason, the user might want to disable HA MN, here is the procedur of disabling HA MN:

* Shut down standby management node

If the HA MN configuration is still functioning, failover the primary management node to be the management node that you would like to use as the management node after the HA MN is disabled; if the HA MN configuration is not functioning correctly, select one management node that you would like to use as the management node after the HA MN is disabled.

* Stop the HA MN services

    chkconfig off:

    pacemaker corosync drdb drdblinks clean

* Start the xCAT services

    chkconfig on:

    nfs nfslock dhcpd postgresql httpd (apache) named conserver xcatd

* Reconfigure the xcat interface

ifconfig to see the current xcat interface before shutting down HA services go to ``/etc/ifconfig/network-scripts`` and create the new interface: ::

     /etc/init.d/pacemaker stop
     /etc/init.d/corosync stop
     /etc/init.d/drbdlinksclean stop

With drbd on and with the filesystem mounted look at each link in ``/etc/drbdlinks.xCAT.conf`` for each link, remove the link if it is still linked,

then copy the drbd file or directory to the filesystem eg. first make sure that the files/directories are no longer linked: ::

     [root@ms1 etc]# ls -al drwxr-xr-x 5 root root 4096 Sep 19 05:09 xcat
     [root@ms1 etc]# cp -rp /drbd/etc/xcat /etc/

In our case, we handled the /install directory like this: ::

     rsync -av /drbd/install/ /oldinstall/
     rsync -av /drbd/install/ /oldinstall/ --delete
     unmount /oldinstall change fstab to mount /install mount /install

start services by hand ( or reboot ) nfs nfslock dhcpd postgresql httpd (apache) named conserver xcatd

Adding SystemImager support to HA
=================================

On each of the management nodes, we need to install ::

     yum install systemimager-server

Then we need to enable the systemimage in pacemaker, first we need to grab the configuration from the current setup ::

     pcs cluster cib xcat_cfg

Now we need add the relevant config to the ``xcat-cfg`` xml file ::

     pcs -f xcat_cfg resource create systemimager_rsync_xCAT lsb:systemimager-server-rsyncd \
          op monitor interval="37s"
     pcs -f xcat_cfg constraint colocation add systemimager_rsync_xCAT grp_xCAT
     pcs -f xcat_cfg constraint order grp_xCAT then systemimager_rsync_xCAT

Finally we commit the changes that are in xcat_cfg into the live system: ::

     pcs cluster push cib xcat_cfg

We then need to make sure that the ``/xCATdrbd/etc/drbdlinks.xCAT.conf`` file has the systemimager portion uncommented, and re-do the initialisation of drbdlinks as they have been done earlier in the documentation

Appendix A
==========

A sample Pacemaker configuration through pcs on RHEL 6.4, These are commands that need to be run on the MN:

Create a file to queue up the changes, this creates a file with the current configuration into a file xcat_cfg: ::

     pcs cluster cib xcat_cfg

We use the pcs -f option to make changes in the file, so this is not changing it live: ::

     pcs -f xcat_cfg property set stonith-enabled=false
     pcs -f xcat_cfg property set no-quorum-policy=ignore
     pcs -f xcat_cfg resource op defaults timeout="120s"

     pcs -f xcat_cfg resource create ip_xCAT ocf:heartbeat:IPaddr2 ip="10.1.0.1" \
          iflabel="xCAT" cidr_netmask="24" nic="eth2"\
          op monitor interval="37s"
     pcs -f xcat_cfg resource create NFS_xCAT lsb:nfs \
          op monitor interval="41s"
     pcs -f xcat_cfg resource create NFSlock_xCAT lsb:nfslock \
          op monitor interval="43s"
     pcs -f xcat_cfg resource create apache_xCAT ocf:heartbeat:apache configfile="/etc/httpd/conf/httpd.conf" \
          statusurl="http://localhost:80/icons/README.html" testregex="</html>" \
          op monitor interval="57s"
     pcs -f xcat_cfg resource create db_xCAT ocf:heartbeat:mysql config="/xCATdrbd/etc/my.cnf" test_user="mysql" \
          binary="/usr/bin/mysqld_safe" pid="/var/run/mysqld/mysqld.pid" socket="/var/lib/mysql/mysql.sock" \
          op monitor interval="57s"
     pcs -f xcat_cfg resource create dhcpd lsb:dhcpd \
          op monitor interval="37s"
     pcs -f xcat_cfg resource create drbd_xCAT ocf:linbit:drbd drbd_resource=xCAT
     pcs -f xcat_cfg resource master ms_drbd_xCAT drbd_xCAT master-max="1" master-node-max="1" clone-max="2" clone-node-max="1" notify="true"
     pcs -f xcat_cfg resource create dummy ocf:heartbeat:Dummy
     pcs -f xcat_cfg resource create fs_xCAT ocf:heartbeat:Filesystem device="/dev/drbd/by-res/xCAT" directory="/xCATdrbd" fstype="ext4" \
          op monitor interval="57s"
     pcs -f xcat_cfg resource create named lsb:named \
          op monitor interval="37s"
     pcs -f xcat_cfg resource create symlinks_xCAT ocf:tummy:drbdlinks configfile="/xCATdrbd/etc/drbdlinks.xCAT.conf" \
          op monitor interval="31s"
     pcs -f xcat_cfg resource create xCAT lsb:xcatd \
          op monitor interval="42s"
     pcs -f xcat-cfg resource create xCAT_conserver lsb:conserver \
          op monitor interval="53"
     pcs -f xcat_cfg resource clone clone_named named clone-max=2 clone-node-max=1 notify=false
     pcs -f xcat_cfg resource group add grp_xCAT fs_xCAT symlinks_xCAT
     pcs -f xcat_cfg constraint colocation add NFS_xCAT grp_xCAT
     pcs -f xcat_cfg constraint colocation add NFSlock_xCAT grp_xCAT
     pcs -f xcat_cfg constraint colocation add apache_xCAT grp_xCAT
     pcs -f xcat_cfg constraint colocation add dhcpd grp_xCAT
     pcs -f xcat_cfg constraint colocation add db_xCAT grp_xCAT
     pcs -f xcat_cfg constraint colocation add dummy grp_xCAT
     pcs -f xcat_cfg constraint colocation add xCAT grp_xCAT
     pcs -f xcat-cfg constraint colocation add xCAT_conserver grp_xCAT
     pcs -f xcat_cfg constraint colocation add grp_xCAT ms_drbd_xCAT INFINITY with-rsc-role=Master
     pcs -f xcat_cfg constraint colocation add ip_xCAT ms_drbd_xCAT INFINITY with-rsc-role=Master
     pcs -f xcat_cfg constraint order list xCAT dummy
     pcs -f xcat_cfg constraint order list NFSlock_xCAT dummy
     pcs -f xcat_cfg constraint order list apache_xCAT dummy
     pcs -f xcat_cfg constraint order list dhcpd dummy
     pcs -f xcat_cfg constraint order list db_xCAT dummy
     pcs -f xcat_cfg constraint order list NFS_xCAT dummy
     pcs -f xcat-cfg constraint order list xCAT_conserver dummy

     pcs -f xcat_cfg constraint order list fs_xCAT symlinks_xCAT

     pcs -f xcat_cfg constraint order list ip_xCAT db_xCAT
     pcs -f xcat_cfg constraint order list ip_xCAT apache_xCAT
     pcs -f xcat_cfg constraint order list ip_xCAT dhcpd
     pcs -f xcat-cfg constraint order list ip_xCAT xCAT_conserver

     pcs -f xcat_cfg constraint order list grp_xCAT NFS_xCAT
     pcs -f xcat_cfg constraint order list grp_xCAT NFSlock_xCAT
     pcs -f xcat_cfg constraint order list grp_xCAT apache_xCAT
     pcs -f xcat_cfg constraint order list grp_xCAT db_xCAT
     pcs -f xcat_cfg constraint order list grp_xCAT dhcpd
     pcs -f xcat-cfg constraint order list grp_xCAT xCAT_conserver
     pcs -f xcat_cfg constraint order list db_xCAT xCAT

     pcs -f xcat_cfg constraint order promote ms_drbd_xCAT then start grp_xCAT

Finally we commit the changes that are in xcat_cfg into the live system: ::

     pcs cluster push cib xcat_cfg

Appendix B
==========

from RHEL 6.5, corosync is being outdated, and will be replaced by ``cman`` and ``ccs``; so as part of the installation, instead of installing corosync we need to install ``pcs`` and ``ccs``, as shown below: ::

    yum -y install cman ccs pcs

In order to do similar configs to corosync, that we need to apply to cman, is shown below. ::

    ccs -f /etc/cluster/cluster.conf --createcluster xcat-cluster
    ccs -f /etc/cluster/cluster.conf --addnode x3550m4n01
    ccs -f /etc/cluster/cluster.conf --addnode x3550m4n02
    ccs -f /etc/cluster/cluster.conf --addfencedev pcmk agent=fence_pcmk
    ccs -f /etc/cluster/cluster.conf --addmethod pcmk-redirect x3550m4n01
    ccs -f /etc/cluster/cluster.conf --addmethod pcmk-redirect x3550m4n02
    ccs -f /etc/cluster/cluster.conf --addfenceinst pcmk x3550m4n01 pcmk-redirect port=x3550m4n01
    ccs -f /etc/cluster/cluster.conf --addfenceinst pcmk x3550m4n02 pcmk-redirect port=x3550m4n02
    ccs -f /etc/cluster/cluster.conf --setcman two_node=1 expected_votes=1

    echo "CMAN_QUORUM_TIMEOUT=0" >> /etc/sysconfig/cman

As per Appendix A, a sample Pacemaker configuration through pcs on RHEL 6.5 is shown below; but there are some slight changes compared to RHEL 6.4 (So we need to keep these in mind). The commands below need to be run on the MN:

Create a file to queue up the changes, this creates a file with the current configuration into a file xcat_cfg: ::

     pcs cluster cib xcat_cfg

We use the pcs -f option to make changes in the file, so this is not changing it live: ::

     pcs -f xcat_cfg property set stonith-enabled=false
     pcs -f xcat_cfg property set no-quorum-policy=ignore
     pcs -f xcat_cfg resource op defaults timeout="120s"
     pcs -f xcat_cfg resource create ip_xCAT ocf:heartbeat:IPaddr2 ip="10.1.0.1" \
          iflabel="xCAT" cidr_netmask="24" nic="eth2"\
          op monitor interval="37s"
     pcs -f xcat_cfg resource create NFS_xCAT lsb:nfs \
          op monitor interval="41s"
     pcs -f xcat_cfg resource create NFSlock_xCAT lsb:nfslock \
          op monitor interval="43s"
     pcs -f xcat_cfg resource create apache_xCAT ocf:heartbeat:apache configfile="/etc/httpd/conf/httpd.conf" \
          statusurl="http://localhost:80/icons/README.html" testregex="</html>" \
          op monitor interval="57s"
     pcs -f xcat_cfg resource create db_xCAT ocf:heartbeat:mysql config="/xCATdrbd/etc/my.cnf" test_user="mysql" \
          binary="/usr/bin/mysqld_safe" pid="/var/run/mysqld/mysqld.pid" socket="/var/lib/mysql/mysql.sock" \
          op monitor interval="57s"
     pcs -f xcat_cfg resource create dhcpd lsb:dhcpd \
          op monitor interval="37s"
     pcs -f xcat_cfg resource create drbd_xCAT ocf:linbit:drbd drbd_resource=xCAT
     pcs -f xcat_cfg resource master ms_drbd_xCAT drbd_xCAT master-max="1" master-node-max="1" clone-max="2" clone-node-max="1" notify="true"
     pcs -f xcat_cfg resource create dummy ocf:heartbeat:Dummy
     pcs -f xcat_cfg resource create fs_xCAT ocf:heartbeat:Filesystem device="/dev/drbd/by-res/xCAT" directory="/xCATdrbd" fstype="ext4" \
          op monitor interval="57s"
     pcs -f xcat_cfg resource create named lsb:named \
          op monitor interval="37s"
     pcs -f xcat_cfg resource create symlinks_xCAT ocf:tummy:drbdlinks configfile="/xCATdrbd/etc/drbdlinks.xCAT.conf" \
          op monitor interval="31s"
     pcs -f xcat_cfg resource create xCAT lsb:xcatd \
          op monitor interval="42s"
     pcs -f xcat-cfg resource create xCAT_conserver lsb:conserver \
          op monitor interval="53"
     pcs -f xcat_cfg resource clone named clone-max=2 clone-node-max=1 notify=false
     pcs -f xcat_cfg resource group add grp_xCAT fs_xCAT symlinks_xCAT
     pcs -f xcat_cfg constraint colocation add NFS_xCAT grp_xCAT
     pcs -f xcat_cfg constraint colocation add NFSlock_xCAT grp_xCAT
     pcs -f xcat_cfg constraint colocation add apache_xCAT grp_xCAT
     pcs -f xcat_cfg constraint colocation add dhcpd grp_xCAT
     pcs -f xcat_cfg constraint colocation add db_xCAT grp_xCAT
     pcs -f xcat_cfg constraint colocation add dummy grp_xCAT
     pcs -f xcat_cfg constraint colocation add xCAT grp_xCAT
     pcs -f xcat-cfg constraint colocation add xCAT_conserver grp_xCAT
     pcs -f xcat_cfg constraint colocation add grp_xCAT ms_drbd_xCAT INFINITY with-rsc-role=Master
     pcs -f xcat_cfg constraint colocation add ip_xCAT ms_drbd_xCAT INFINITY with-rsc-role=Master
     pcs -f xcat_cfg constraint order xCAT then dummy
     pcs -f xcat_cfg constraint order NFSlock_xCAT then dummy
     pcs -f xcat_cfg constraint order apache_xCAT then dummy
     pcs -f xcat_cfg constraint order dhcpd then dummy
     pcs -f xcat_cfg constraint order db_xCAT then dummy
     pcs -f xcat_cfg constraint order NFS_xCAT then dummy
     pcs -f xcat-cfg constraint order xCAT_conserver then dummy
     pcs -f xcat_cfg constraint order fs_xCAT then symlinks_xCAT
     pcs -f xcat_cfg constraint order ip_xCAT then db_xCAT
     pcs -f xcat_cfg constraint order ip_xCAT then apache_xCAT
     pcs -f xcat_cfg constraint order ip_xCAT then dhcpd
     pcs -f xcat-cfg constraint order ip_xCAT then xCAT_conserver
     pcs -f xcat_cfg constraint order grp_xCAT then NFS_xCAT
     pcs -f xcat_cfg constraint order grp_xCAT then NFSlock_xCAT
     pcs -f xcat_cfg constraint order grp_xCAT then apache_xCAT
     pcs -f xcat_cfg constraint order grp_xCAT then db_xCAT
     pcs -f xcat_cfg constraint order grp_xCAT then dhcpd
     pcs -f xcat-cfg constraint order grp_xCAT then xCAT_conserver
     pcs -f xcat_cfg constraint order db_xCAT then xCAT
     pcs -f xcat_cfg constraint order promote ms_drbd_xCAT then start grp_xCAT

Finally we commit the changes that are in xcat_cfg into the live system: ::

     pcs cluster cib-push xcat_cfg

Once the changes have been commited, we can view the config, by running the command below: ::

     pcs config

which should result in the following output: ::

    Cluster Name: xcat-cluster
    Corosync Nodes:
    Pacemaker Nodes:
     x3550m4n01 x3550m4n02
    Resources:
     Resource: ip_xCAT (class=ocf provider=heartbeat type=IPaddr2)
      Attributes: ip=10.1.0.1 iflabel=xCAT cidr_netmask=24 nic=eth2
      Operations: monitor interval=37s (ip_xCAT-monitor-interval-37s)
     Resource: NFS_xCAT (class=lsb type=nfs)
      Operations: monitor interval=41s (NFS_xCAT-monitor-interval-41s)
     Resource: NFSlock_xCAT (class=lsb type=nfslock)
      Operations: monitor interval=43s (NFSlock_xCAT-monitor-interval-43s)
     Resource: apache_xCAT (class=ocf provider=heartbeat type=apache)
      Attributes: configfile=/etc/httpd/conf/httpd.conf statusurl=http://localhost:80/icons/README.html testregex=</html>
      Operations: monitor interval=57s (apache_xCAT-monitor-interval-57s)
     Resource: db_xCAT (class=ocf provider=heartbeat type=mysql)
      Attributes: config=/xCATdrbd/etc/my.cnf test_user=mysql binary=/usr/bin/mysqld_safe pid=/var/run/mysqld/mysqld.pid socket=/var/lib/mysql/mysql.sock
      Operations: monitor interval=57s (db_xCAT-monitor-interval-57s)
     Resource: dhcpd (class=lsb type=dhcpd)
      Operations: monitor interval=37s (dhcpd-monitor-interval-37s)
     Master: ms_drbd_xCAT
      Meta Attrs: master-max=1 master-node-max=1 clone-max=2 clone-node-max=1 notify=true
      Resource: drbd_xCAT (class=ocf provider=linbit type=drbd)
       Attributes: drbd_resource=xCAT
       Operations: monitor interval=60s (drbd_xCAT-monitor-interval-60s)
     Resource: dummy (class=ocf provider=heartbeat type=Dummy)
      Operations: monitor interval=60s (dummy-monitor-interval-60s)
     Resource: xCAT (class=lsb type=xcatd)
      Operations: monitor interval=42s (xCAT-monitor-interval-42s)
     Resource: xCAT_conserver (class=lsb type=conserver)
      Operations: monitor interval=53 (xCAT_conserver-monitor-interval-53)
     Clone: named-clone
      Meta Attrs: clone-max=2 clone-node-max=1 notify=false
      Resource: named (class=lsb type=named)
       Operations: monitor interval=37s (named-monitor-interval-37s)
     Group: grp_xCAT
      Resource: fs_xCAT (class=ocf provider=heartbeat type=Filesystem)
       Attributes: device=/dev/drbd/by-res/xCAT directory=/xCATdrbd fstype=ext4
       Operations: monitor interval=57s (fs_xCAT-monitor-interval-57s)
      Resource: symlinks_xCAT (class=ocf provider=tummy type=drbdlinks)
       Attributes: configfile=/xCATdrbd/etc/drbdlinks.xCAT.conf
       Operations: monitor interval=31s (symlinks_xCAT-monitor-interval-31s)

    Stonith Devices:
    Fencing Levels:

    Location Constraints:
    Ordering Constraints:
      start xCAT then start dummy (Mandatory) (id:order-xCAT-dummy-mandatory)
      start NFSlock_xCAT then start dummy (Mandatory) (id:order-NFSlock_xCAT-dummy-mandatory)
      start apache_xCAT then start dummy (Mandatory) (id:order-apache_xCAT-dummy-mandatory)
      start dhcpd then start dummy (Mandatory) (id:order-dhcpd-dummy-mandatory)
      start db_xCAT then start dummy (Mandatory) (id:order-db_xCAT-dummy-mandatory)
      start NFS_xCAT then start dummy (Mandatory) (id:order-NFS_xCAT-dummy-mandatory)
      start xCAT_conserver then start dummy (Mandatory) (id:order-xCAT_conserver-dummy-mandatory)
      start fs_xCAT then start symlinks_xCAT (Mandatory) (id:order-fs_xCAT-symlinks_xCAT-mandatory)
      start ip_xCAT then start db_xCAT (Mandatory) (id:order-ip_xCAT-db_xCAT-mandatory)
      start ip_xCAT then start apache_xCAT (Mandatory) (id:order-ip_xCAT-apache_xCAT-mandatory)
      start ip_xCAT then start dhcpd (Mandatory) (id:order-ip_xCAT-dhcpd-mandatory)
      start ip_xCAT then start xCAT_conserver (Mandatory) (id:order-ip_xCAT-xCAT_conserver-mandatory)
      start grp_xCAT then start NFS_xCAT (Mandatory) (id:order-grp_xCAT-NFS_xCAT-mandatory)
      start grp_xCAT then start NFSlock_xCAT (Mandatory) (id:order-grp_xCAT-NFSlock_xCAT-mandatory)
      start grp_xCAT then start apache_xCAT (Mandatory) (id:order-grp_xCAT-apache_xCAT-mandatory)
      start grp_xCAT then start db_xCAT (Mandatory) (id:order-grp_xCAT-db_xCAT-mandatory)
      start grp_xCAT then start dhcpd (Mandatory) (id:order-grp_xCAT-dhcpd-mandatory)
      start grp_xCAT then start xCAT_conserver (Mandatory) (id:order-grp_xCAT-xCAT_conserver-mandatory)
      start db_xCAT then start xCAT (Mandatory) (id:order-db_xCAT-xCAT-mandatory)
      promote ms_drbd_xCAT then start grp_xCAT (Mandatory) (id:order-ms_drbd_xCAT-grp_xCAT-mandatory)
    Colocation Constraints:
      NFS_xCAT with grp_xCAT (INFINITY) (id:colocation-NFS_xCAT-grp_xCAT-INFINITY)
      NFSlock_xCAT with grp_xCAT (INFINITY) (id:colocation-NFSlock_xCAT-grp_xCAT-INFINITY)
      apache_xCAT with grp_xCAT (INFINITY) (id:colocation-apache_xCAT-grp_xCAT-INFINITY)
      dhcpd with grp_xCAT (INFINITY) (id:colocation-dhcpd-grp_xCAT-INFINITY)
      db_xCAT with grp_xCAT (INFINITY) (id:colocation-db_xCAT-grp_xCAT-INFINITY)
      dummy with grp_xCAT (INFINITY) (id:colocation-dummy-grp_xCAT-INFINITY)
      xCAT with grp_xCAT (INFINITY) (id:colocation-xCAT-grp_xCAT-INFINITY)
      xCAT_conserver with grp_xCAT (INFINITY) (id:colocation-xCAT_conserver-grp_xCAT-INFINITY)
      grp_xCAT with ms_drbd_xCAT (INFINITY) (with-rsc-role:Master) (id:colocation-grp_xCAT-ms_drbd_xCAT-INFINITY)
      ip_xCAT with ms_drbd_xCAT (INFINITY) (with-rsc-role:Master) (id:colocation-ip_xCAT-ms_drbd_xCAT-INFINITY)

    Cluster Properties:
     cluster-infrastructure: cman
     dc-version: 1.1.10-14.el6-368c726
     no-quorum-policy: ignore
     stonith-enabled: false

Then we can check the status of the cluster by running the following command: ::

    pcs status

And the resulting output should be the following: ::

    Cluster name: xcat-cluster
    Last updated: Wed Feb  5 14:23:08 2014
    Last change: Wed Feb  5 14:23:06 2014 via crm_attribute on x3550m4n01
    Stack: cman
    Current DC: x3550m4n01 - partition with quorum
    Version: 1.1.10-14.el6-368c726
    2 Nodes configured
    14 Resources configured

    Online: [ x3550m4n01 x3550m4n02 ]

    Full list of resources:

     ip_xCAT    (ocf::heartbeat:IPaddr2):       Started x3550m4n01
     NFS_xCAT   (lsb:nfs):      Started x3550m4n01
     NFSlock_xCAT       (lsb:nfslock):  Started x3550m4n01
     apache_xCAT        (ocf::heartbeat:apache):        Started x3550m4n01
     db_xCAT    (ocf::heartbeat:mysql): Started x3550m4n01
     dhcpd      (lsb:dhcpd):    Started x3550m4n01
     Master/Slave Set: ms_drbd_xCAT [drbd_xCAT]
         Masters: [ x3550m4n01 ]
         Slaves: [ x3550m4n02 ]
     dummy      (ocf::heartbeat:Dummy): Started x3550m4n01
     xCAT       (lsb:xcatd):    Started x3550m4n01
     xCAT_conserver     (lsb:conserver):        Started x3550m4n01
     Clone Set: named-clone [named]
         Started: [ x3550m4n01 x3550m4n02 ]
     Resource Group: grp_xCAT
         fs_xCAT        (ocf::heartbeat:Filesystem):    Started x3550m4n01
         symlinks_xCAT  (ocf::tummy:drbdlinks): Started x3550m4n01

Appendix C
==========

from RHEL 7, there more changes that we need to consider

    yum -y install pcs

In order to do similar configs to corosync, that we need to apply to cman, is shown below. ::

    pcs cluster setup --local --name xcat-cluster x3550m4n01 x3550m4n02 --force

As per Appendix A, a sample Pacemaker configuration through pcs on RHEL 7 is shown below; but there are some slight changes compared to RHEL 6.4 (So we need to keep these in mind). The commands below need to be run on the MN:

Create a file to queue up the changes, this creates a file with the current configuration into a file xcat_cfg: ::

     pcs cluster cib xcat_cfg

We use the pcs -f option to make changes in the file, so this is not changing it live: ::

     pcs -f xcat_cfg property set stonith-enabled=false
     pcs -f xcat_cfg property set no-quorum-policy=ignore
     pcs -f xcat_cfg resource op defaults timeout="120s"
     pcs -f xcat_cfg resource create ip_xCAT ocf:heartbeat:IPaddr2 ip="10.1.0.1" \
          iflabel="xCAT" cidr_netmask="24" nic="eno2"\
          op monitor interval="37s"
     pcs -f xcat-cfg resource create NFS_xCAT ocf:heartbeat:nfsserver nfs_shared_infodir=/var/lib/nfs \
          rpcpipefs_dir=/var/lib/nfs_local/rpc_pipefs nfs_ip=10.12.0.221,10.12.0.222 \
          op monitor interval="41s" start interval=10s timeout=20s
     pcs -f xcat_cfg resource create apache_xCAT ocf:heartbeat:apache configfile="/etc/httpd/conf/httpd.conf" \
          statusurl="http://127.0.0.1:80/icons/README.html" testregex="</html>" \
          op monitor interval="57s"
     pcs -f xcat_cfg resource create db_xCAT ocf:heartbeat:mysql config="/xCATdrbd/etc/my.cnf" test_user="mysql" \
          binary="/usr/bin/mysqld_safe" pid="/var/run/mysqld/mysqld.pid" socket="/var/lib/mysql/mysql.sock" \
          op monitor interval="57s"
     pcs -f xcat_cfg resource create dhcpd systemd:dhcpd \
          op monitor interval="37s"
     pcs -f xcat_cfg resource create drbd_xCAT ocf:linbit:drbd drbd_resource=xCAT
     pcs -f xcat_cfg resource master ms_drbd_xCAT drbd_xCAT master-max="1" master-node-max="1" clone-max="2" clone-node-max="1" notify="true"
     pcs -f xcat_cfg resource create dummy ocf:heartbeat:Dummy
     pcs -f xcat_cfg resource create fs_xCAT ocf:heartbeat:Filesystem device="/dev/drbd/by-res/xCAT" directory="/xCATdrbd" fstype="ext4" \
          op monitor interval="57s"
     pcs -f xcat_cfg resource create named systemd:named \
          op monitor interval="37s"
     pcs -f xcat_cfg resource create symlinks_xCAT ocf:tummy:drbdlinks configfile="/xCATdrbd/etc/drbdlinks.xCAT.conf" \
          op monitor interval="31s"
     pcs -f xcat_cfg resource create xCAT lsb:xcatd \
          op monitor interval="42s"
     pcs -f xcat-cfg resource create xCAT_conserver lsb:conserver \
          op monitor interval="53"
     pcs -f xcat_cfg resource clone named clone-max=2 clone-node-max=1 notify=false
     pcs -f xcat_cfg resource group add grp_xCAT fs_xCAT symlinks_xCAT
     pcs -f xcat_cfg constraint colocation add NFS_xCAT grp_xCAT
     pcs -f xcat_cfg constraint colocation add apache_xCAT grp_xCAT
     pcs -f xcat_cfg constraint colocation add dhcpd grp_xCAT
     pcs -f xcat_cfg constraint colocation add db_xCAT grp_xCAT
     pcs -f xcat_cfg constraint colocation add dummy grp_xCAT
     pcs -f xcat_cfg constraint colocation add xCAT grp_xCAT
     pcs -f xcat-cfg constraint colocation add xCAT_conserver grp_xCAT
     pcs -f xcat_cfg constraint colocation add grp_xCAT ms_drbd_xCAT INFINITY with-rsc-role=Master
     pcs -f xcat_cfg constraint colocation add ip_xCAT ms_drbd_xCAT INFINITY with-rsc-role=Master
     pcs -f xcat_cfg constraint order xCAT then dummy
     pcs -f xcat_cfg constraint order apache_xCAT then dummy
     pcs -f xcat_cfg constraint order dhcpd then dummy
     pcs -f xcat_cfg constraint order db_xCAT then dummy
     pcs -f xcat_cfg constraint order NFS_xCAT then dummy
     pcs -f xcat-cfg constraint order xCAT_conserver then dummy
     pcs -f xcat_cfg constraint order fs_xCAT then symlinks_xCAT
     pcs -f xcat_cfg constraint order ip_xCAT then db_xCAT
     pcs -f xcat_cfg constraint order ip_xCAT then apache_xCAT
     pcs -f xcat_cfg constraint order ip_xCAT then dhcpd
     pcs -f xcat-cfg constraint order ip_xCAT then xCAT_conserver
     pcs -f xcat_cfg constraint order grp_xCAT then NFS_xCAT
     pcs -f xcat_cfg constraint order grp_xCAT then apache_xCAT
     pcs -f xcat_cfg constraint order grp_xCAT then db_xCAT
     pcs -f xcat_cfg constraint order grp_xCAT then dhcpd
     pcs -f xcat-cfg constraint order grp_xCAT then xCAT_conserver
     pcs -f xcat_cfg constraint order db_xCAT then xCAT
     pcs -f xcat_cfg constraint order promote ms_drbd_xCAT then start grp_xCAT

Finally we commit the changes that are in xcat_cfg into the live system: ::

     pcs cluster cib-push xcat_cfg

Once the changes have been commited, we can view the config, by running the command below: ::

     pcs config

which should result in the following output: ::

     Cluster Name: xcat-cluster
     Corosync Nodes:
      x3550m4n01 x3550m4n02
     Pacemaker Nodes:
      x3550m4n01 x3550m4n02
     
     Resources:
      Resource: ip_xCAT (class=ocf provider=heartbeat type=IPaddr2)
       Attributes: ip=10.1.0.1 iflabel=xCAT cidr_netmask=22 nic=eno2
       Operations: start interval=0s timeout=20s (ip_xCAT-start-timeout-20s)
                   stop interval=0s timeout=20s (ip_xCAT-stop-timeout-20s)
                   monitor interval=37s (ip_xCAT-monitor-interval-37s)
      Resource: NFS_xCAT (class=ocf provider=heartbeat type=nfsserver)
       Attributes: nfs_shared_infodir=/xcatdrbd/var/lib/nfs rpcpipefs_dir=/var/lib/nfs_local/rpc_pipefs nfs_ip=10.12.0.221,10.12.0.222
       Operations: start interval=10s timeout=20s (NFS_xCAT-start-interval-10s-timeout-20s)
                   stop interval=0s timeout=20s (NFS_xCAT-stop-timeout-20s)
                   monitor interval=41s (NFS_xCAT-monitor-interval-41s)
      Resource: apache_xCAT (class=ocf provider=heartbeat type=apache)
       Attributes: configfile=/etc/httpd/conf/httpd.conf statusurl=http://127.0.0.1:80/icons/README.html testregex=</html>
       Operations: start interval=0s timeout=40s (apache_xCAT-start-timeout-40s)
                   stop interval=0s timeout=60s (apache_xCAT-stop-timeout-60s)
                   monitor interval=57s (apache_xCAT-monitor-interval-57s)
      Resource: db_xCAT (class=ocf provider=heartbeat type=mysql)
       Attributes: config=/xcatdrbd/etc/my.cnf test_user=mysql binary=/usr/bin/mysqld_safe pid=/var/run/mariadb/mariadb.pid socket=/var/lib/mysql/mysql.sock
       Operations: start interval=0s timeout=120 (db_xCAT-start-timeout-120)
                   stop interval=0s timeout=120 (db_xCAT-stop-timeout-120)
                   promote interval=0s timeout=120 (db_xCAT-promote-timeout-120)
                   demote interval=0s timeout=120 (db_xCAT-demote-timeout-120)
                   monitor interval=57s (db_xCAT-monitor-interval-57s)
      Resource: dhcpd (class=systemd type=dhcpd)
       Operations: monitor interval=37s (dhcpd-monitor-interval-37s)
      Resource: dummy (class=ocf provider=heartbeat type=Dummy)
       Operations: start interval=0s timeout=20 (dummy-start-timeout-20)
                   stop interval=0s timeout=20 (dummy-stop-timeout-20)
                   monitor interval=10 timeout=20 (dummy-monitor-interval-10)
      Master: ms_drbd_xCAT
       Meta Attrs: master-max=1 master-node-max=1 clone-max=2 clone-node-max=1 notify=true
       Resource: drbd_xCAT (class=ocf provider=linbit type=drbd)
        Attributes: drbd_resource=xCAT
        Operations: start interval=0s timeout=240 (drbd_xCAT-start-timeout-240)
                    promote interval=0s timeout=90 (drbd_xCAT-promote-timeout-90)
                    demote interval=0s timeout=90 (drbd_xCAT-demote-timeout-90)
                    stop interval=0s timeout=100 (drbd_xCAT-stop-timeout-100)
                    monitor interval=20 role=Slave timeout=20 (drbd_xCAT-monitor-interval-20-role-Slave)
                    monitor interval=10 role=Master timeout=20 (drbd_xCAT-monitor-interval-10-role-Master)
      Resource: xCAT (class=lsb type=xcatd)
       Operations: monitor interval=42s (xCAT-monitor-interval-42s)
      Resource: xCAT_conserver (class=lsb type=conserver)
       Operations: monitor interval=53 (xCAT_conserver-monitor-interval-53)
      Resource: gmetad (class=systemd type=gmetad)
       Operations: monitor interval=57s (gmetad-monitor-interval-57s)
      Resource: icinga (class=lsb type=icinga)
       Operations: monitor interval=57s (icinga-monitor-interval-57s)
      Clone: named-clone
       Meta Attrs: clone-max=2 clone-node-max=1 notify=false
       Resource: named (class=systemd type=named)
        Operations: monitor interval=37s (named-monitor-interval-37s)
      Group: grp_xCAT
       Resource: fs_xCAT (class=ocf provider=heartbeat type=Filesystem)
        Attributes: device=/dev/drbd/by-res/xCAT directory=/xcatdrbd fstype=xfs
        Operations: start interval=0s timeout=60 (fs_xCAT-start-timeout-60)
                    stop interval=0s timeout=60 (fs_xCAT-stop-timeout-60)
                    monitor interval=57s (fs_xCAT-monitor-interval-57s)
       Resource: symlinks_xCAT (class=ocf provider=tummy type=drbdlinks)
        Attributes: configfile=/xcatdrbd/etc/drbdlinks.xCAT.conf
        Operations: start interval=0s timeout=1m (symlinks_xCAT-start-timeout-1m)
                    stop interval=0s timeout=1m (symlinks_xCAT-stop-timeout-1m)
                    monitor interval=31s on-fail=ignore (symlinks_xCAT-monitor-interval-31s)
     
     Stonith Devices:
     Fencing Levels:
     
     Location Constraints:
     Ordering Constraints:
       promote ms_drbd_xCAT then start grp_xCAT (kind:Mandatory) (id:order-ms_drbd_xCAT-grp_xCAT-mandatory)
       start fs_xCAT then start symlinks_xCAT (kind:Mandatory) (id:order-fs_xCAT-symlinks_xCAT-mandatory)
       start xCAT then start dummy (kind:Mandatory) (id:order-xCAT-dummy-mandatory)
       start apache_xCAT then start dummy (kind:Mandatory) (id:order-apache_xCAT-dummy-mandatory)
       start dhcpd then start dummy (kind:Mandatory) (id:order-dhcpd-dummy-mandatory)
       start db_xCAT then start dummy (kind:Mandatory) (id:order-db_xCAT-dummy-mandatory)
       start NFS_xCAT then start dummy (kind:Mandatory) (id:order-NFS_xCAT-dummy-mandatory)
       start xCAT_conserver then start dummy (kind:Mandatory) (id:order-xCAT_conserver-dummy-mandatory)
       start gmetad then start dummy (kind:Mandatory) (id:order-gmetad-dummy-mandatory)
       start icinga then start dummy (kind:Mandatory) (id:order-icinga-dummy-mandatory)
       start ip_xCAT then start db_xCAT (kind:Mandatory) (id:order-ip_xCAT-db_xCAT-mandatory)
       start ip_xCAT then start apache_xCAT (kind:Mandatory) (id:order-ip_xCAT-apache_xCAT-mandatory)
       start ip_xCAT then start dhcpd (kind:Mandatory) (id:order-ip_xCAT-dhcpd-mandatory)
       start ip_xCAT then start xCAT_conserver (kind:Mandatory) (id:order-ip_xCAT-xCAT_conserver-mandatory)
       start ip_xCAT then start named-clone (kind:Mandatory) (id:order-ip_xCAT-named-clone-mandatory)
       start grp_xCAT then start NFS_xCAT (kind:Mandatory) (id:order-grp_xCAT-NFS_xCAT-mandatory)
       start grp_xCAT then start apache_xCAT (kind:Mandatory) (id:order-grp_xCAT-apache_xCAT-mandatory)
       start grp_xCAT then start db_xCAT (kind:Mandatory) (id:order-grp_xCAT-db_xCAT-mandatory)
       start grp_xCAT then start dhcpd (kind:Mandatory) (id:order-grp_xCAT-dhcpd-mandatory)
       start grp_xCAT then start gmetad (kind:Mandatory) (id:order-grp_xCAT-gmetad-mandatory)
       start grp_xCAT then start icinga (kind:Mandatory) (id:order-grp_xCAT-icinga-mandatory)
       start grp_xCAT then start xCAT_conserver (kind:Mandatory) (id:order-grp_xCAT-xCAT_conserver-mandatory)
       start db_xCAT then start xCAT (kind:Mandatory) (id:order-db_xCAT-xCAT-mandatory)
     Colocation Constraints:
       grp_xCAT with ms_drbd_xCAT (score:INFINITY) (with-rsc-role:Master) (id:colocation-grp_xCAT-ms_drbd_xCAT-INFINITY)
       ip_xCAT with ms_drbd_xCAT (score:INFINITY) (with-rsc-role:Master) (id:colocation-ip_xCAT-ms_drbd_xCAT-INFINITY)
       NFS_xCAT with grp_xCAT (score:INFINITY) (id:colocation-NFS_xCAT-grp_xCAT-INFINITY)
       apache_xCAT with grp_xCAT (score:INFINITY) (id:colocation-apache_xCAT-grp_xCAT-INFINITY)
       dhcpd with grp_xCAT (score:INFINITY) (id:colocation-dhcpd-grp_xCAT-INFINITY)
       db_xCAT with grp_xCAT (score:INFINITY) (id:colocation-db_xCAT-grp_xCAT-INFINITY)
       dummy with grp_xCAT (score:INFINITY) (id:colocation-dummy-grp_xCAT-INFINITY)
       xCAT with grp_xCAT (score:INFINITY) (id:colocation-xCAT-grp_xCAT-INFINITY)
       xCAT_conserver with grp_xCAT (score:INFINITY) (id:colocation-xCAT_conserver-grp_xCAT-INFINITY)
       gmetad with grp_xCAT (score:INFINITY) (id:colocation-gmetad-grp_xCAT-INFINITY)
       icinga with grp_xCAT (score:INFINITY) (id:colocation-icinga-grp_xCAT-INFINITY)
       ip_xCAT with grp_xCAT (score:INFINITY) (id:colocation-ip_xCAT-grp_xCAT-INFINITY)
     
     Cluster Properties:
      cluster-infrastructure: corosync
      cluster-name: ucl_cluster
      dc-version: 1.1.12-a14efad
      have-watchdog: false
      last-lrm-refresh: 1445963044
      no-quorum-policy: ignore
      stonith-enabled: false

Then we can check the status of the cluster by running the following command: ::

    pcs status

And the resulting output should be the following: ::

     Cluster name: xcat-cluster
     Last updated: Wed Oct 28 09:59:25 2015
     Last change: Tue Oct 27 16:24:04 2015
     Stack: corosync
     Current DC: x3550m4n01 (1) - partition with quorum
     Version: 1.1.12-a14efad
     2 Nodes configured
     17 Resources configured
     
     
     Online: [ x3550m4n01 x3550m4n02 ]
     
     Full list of resources:
     
      ip_xCAT        (ocf::heartbeat:IPaddr2):       Started x3550m4n01
      NFS_xCAT       (ocf::heartbeat:nfsserver):     Started x3550m4n01
      apache_xCAT    (ocf::heartbeat:apache):        Started x3550m4n01
      db_xCAT        (ocf::heartbeat:mysql): Started x3550m4n01
      dhcpd  (systemd:dhcpd):        Started x3550m4n01
      dummy  (ocf::heartbeat:Dummy): Started x3550m4n01
      Master/Slave Set: ms_drbd_xCAT [drbd_xCAT]
          Masters: [ x3550m4n01 ]
          Slaves: [ x3550m4n02 ]
      xCAT   (lsb:xcatd):    Started x3550m4n01
      xCAT_conserver (lsb:conserver):        Started x3550m4n01
      Clone Set: named-clone [named]
          Started: [ x3550m4n01r x3550m4n02 ]
      Resource Group: grp_xCAT
          fs_xCAT    (ocf::heartbeat:Filesystem):    Started x3550m4n01
          symlinks_xCAT      (ocf::tummy:drbdlinks): Started x3550m4n01
     
     PCSD Status:
       x3550m4n01: Online
       x3550m4n02: Online
     Daemon Status:
       corosync: active/disabled
       pacemaker: active/disabled
       pcsd: active/enabled

Further from this, the following changes needed to be made for nfs in el7 ::

     cat > /etc/systemd/system/var-lib-nfs_local-rpc_pipefs.mount << EOF
     [Unit]
     Description=RPC Pipe File System
     DefaultDependencies=no
     Conflicts=umount.target
     
     [Mount]
     What=sunrpc
     Where=/var/lib/nfs_local/rpc_pipefs
     Type=rpc_pipefs
     EOF


     --- /usr/lib/systemd/system/rpc-svcgssd.service	2015-01-23 16:30:26.000000000 +0000
     +++ /etc/systemd/system/rpc-svcgssd.service	2015-10-13 01:39:36.000000000 +0100
     @@ -1,7 +1,7 @@
      [Unit]
      Description=RPC security service for NFS server
     -Requires=var-lib-nfs-rpc_pipefs.mount
     -After=var-lib-nfs-rpc_pipefs.mount
     +Requires=var-lib-nfs_local-rpc_pipefs.mount
     +After=var-lib-nfs_local-rpc_pipefs.mount
      PartOf=nfs-server.service
      PartOf=nfs-utils.service


     --- /usr/lib/systemd/system/rpc-gssd.service	2015-01-23 16:30:26.000000000 +0000
     +++ /etc/systemd/system/rpc-gssd.service	2015-10-13 01:39:36.000000000 +0100
     @@ -2,8 +2,8 @@
      Description=RPC security service for NFS client and server
      DefaultDependencies=no
      Conflicts=umount.target
     -Requires=var-lib-nfs-rpc_pipefs.mount
     -After=var-lib-nfs-rpc_pipefs.mount
     +Requires=var-lib-nfs_local-rpc_pipefs.mount
     +After=var-lib-nfs_local-rpc_pipefs.mount
     
      ConditionPathExists=/etc/krb5.keytab
     

     --- /usr/lib/systemd/system/nfs-secure.service	2015-01-23 16:30:26.000000000 +0000
     +++ /etc/systemd/system/nfs-secure.service	2015-10-13 01:39:36.000000000 +0100
     @@ -2,8 +2,8 @@
      Description=RPC security service for NFS client and server
      DefaultDependencies=no
      Conflicts=umount.target
     -Requires=var-lib-nfs-rpc_pipefs.mount
     -After=var-lib-nfs-rpc_pipefs.mount
     +Requires=var-lib-nfs_local-rpc_pipefs.mount
     +After=var-lib-nfs_local-rpc_pipefs.mount
     
      ConditionPathExists=/etc/krb5.keytab
     

     --- /usr/lib/systemd/system/nfs-secure-server.service	2015-01-23 16:30:26.000000000 +0000
     +++ /etc/systemd/system/nfs-secure-server.service	2015-10-13 01:39:36.000000000 +0100
     @@ -1,7 +1,7 @@
      [Unit]
      Description=RPC security service for NFS server
     -Requires=var-lib-nfs-rpc_pipefs.mount
     -After=var-lib-nfs-rpc_pipefs.mount
     +Requires=var-lib-nfs_local-rpc_pipefs.mount
     +After=var-lib-nfs_local-rpc_pipefs.mount
      PartOf=nfs-server.service
      PartOf=nfs-utils.service
     

     --- /usr/lib/systemd/system/nfs-blkmap.service	2015-01-23 16:30:26.000000000 +0000
     +++ /etc/systemd/system/nfs-blkmap.service	2015-10-13 01:39:36.000000000 +0100
     @@ -2,8 +2,8 @@
      Description=pNFS block layout mapping daemon
      DefaultDependencies=no
      Conflicts=umount.target
     -After=var-lib-nfs-rpc_pipefs.mount
     -Requires=var-lib-nfs-rpc_pipefs.mount
     +After=var-lib-nfs_local-rpc_pipefs.mount
     +Requires=var-lib-nfs_local-rpc_pipefs.mount
     
      Requisite=nfs-blkmap.target
      After=nfs-blkmap.target

