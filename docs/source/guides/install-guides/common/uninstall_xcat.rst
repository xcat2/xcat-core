Uninstall xCAT
==============

Removing xCAT Trace
-------------------

1. Backup your xCAT database ( if you want to keep it) ::

    dumpxCATdb -p <path_to_where_to_save_the_database>

2. Save your node information

  To create a stanza file of your node definitions (all group), run the following ::

    lsdef -z all > <your_node_def_bak>.stanza

3. Save your networks information

  To create a stanza file of your network information, run the following ::

    lsdef -z -t network -l > <your_net_def_bak>.stanza

4. Clean up tftpboot

  To clean up the node information in tftpboot ::

    nodeset all offline

5. Cleanup dhcp

  You may want to remove all nodes from dhcp ::

    makedhcp -d <noderange>

6. Clean up ``/etc/hosts``

  You may want to remove you cluster nodes from ``/etc/hosts``, you can edit ``/etc/hosts`` by 'vi' directly, or using xCAT command ``tabedit`` to remove all the nodes from the hosts table ::

    tabedit hosts  

7. Removing nodes from DNS

  After removing all the nodes from ``/etc/hosts`` and the ``hosts`` table ::

    makedns -n

8. Stop xcatd ::

    service xcatd stop

9. Clean up network services(Optional)

  xCAT uses various network services on the management node and service nodes, the network services setup by xCAT may need to be cleaned up on the management node and service nodes before uninstalling xCAT.

* **NFS** : stop nfs service, unexport all the file systems exported by xCAT, and remove the xCAT file systems from ``/etc/exports``.
* **HTTP**: stop http service, remove the xcat.conf in the http configuration directory.
* **TFTP**: stop tftp service, remove the tftp files created by xCAT in tftp directory.
* **DHCP**: stop dhcp service, remove the configuration made by xCAT in dhcp configuration files.
* **DNS** : stop the named service, remove the named entries created by xCAT from the named database.

Removing xCAT RPMs
------------------

1. Removing the xCAT RPMs 

  Get xCAT RPM list by ``rpm`` command then remove them one by one ::
  
    [root@server ~]# rpm -qa | grep xCAT
    xCAT-2.10-snap201505271151.ppc64
    xCAT-client-2.10-snap201505271150.noarch
    xCAT-genesis-scripts-ppc64-2.10-snap201505271151.noarch
    xCAT-server-2.10-snap201505271151.noarch
    xCAT-test-2.10-snap201505271151.noarch
    xCAT-buildkit-2.10-snap201505271151.noarch
    perl-xCAT-2.10-snap201505271150.noarch
    xCAT-genesis-base-ppc64-2.10-snap201505172314.noarch
	
    [root@server ~]#rpm -e xCAT-genesis-scripts-ppc64-2.10-snap201505271151.noarch
    [root@server ~]#rpm -e xCAT-genesis-base-ppc64-2.10-snap201505172314.noarch
    ..........

2. Removing OSS prerequisites installed for xCAT(Optional) ::

    rpm -e fping-2.2b1-1
    rpm -e perl-Digest-MD5-2.36-1
    rpm -e perl-Net_SSLeay.pm-1.30-1
    rpm -e perl-IO-Socket-SSL-1.06-1
    rpm -e perl-IO-Stty-.02-1
    rpm -e perl-IO-Tty-1.07-1
    rpm -e perl-Expect-1.21-1
    rpm -e conserver-8.1.16-2
    rpm -e expect-5.42.1-3
    rpm -e tk-8.4.7-3
    rpm -e tcl-8.4.7-3
    rpm -e perl-DBD-SQLite-1.13-1
    rpm -e perl-DBI-1.55-1
    .......

3. Removing root ssh keys(Optional) ::

    rm -rf $ROOTHOME/.ssh

  **[NOTE]** Be caution: do not remove the ``$ROOTHOME/.ssh`` if do not plan to remove ``/install/postscripts/_ssh`` directory

4. Removing xCAT data directories ::

    rm -rf /install 
    rm -rf /tftpboot/xcat*
    rm -rf /tftpboot/etc
    rm -rf /etc/xcat
    rm -rf /etc/sysconfig/xcat ( may not exist)
    rm /mnt/xcat  
	
  **[NOTE]** Remember to uninstall the packages ``elilo-xcat`` and ``xnba-undi``, otherwise the next time of xCAT installation will fail
  
5. Removing Extraneous files ::

    rm /tmp/genimage*
    rm /tmp/packimage*
    rm /tmp/mknb*
    rm /etc/yum.repos.d/*

6. Clean up system files that were updated by xCAT (optional)

  There are multiple system configuration files that may have been updated while using xCAT to manage your cluster. In most cases you can determine what files have been updated by understanding the function of the commands that you run or by reading the xCAT documentation. There is no automated way to know what files should be cleaned up or removed. You will have to determine on a case by case basis whether or not a particular file should be updated to remove any leftover entries.

Removing Databases
------------------

* For PostgreSQL: See :ref:`Removing xCAT DB from PostgreSQL <removing_xcat_from_postgresql_target>`
* For MySQL/MariaDB: See :ref:`Removing xCAT DB from MySQL/MariaDB <removing_xcat_from_mysql_target>`


