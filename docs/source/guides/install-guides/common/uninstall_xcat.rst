Remove xCAT
===========

Backup xCAT User Data
---------------------

Before removing xCAT, recommand to backup xCAT database. It's convenient to restore xCAT management environment in the future if needed ::

    dumpxCATdb -p <path_to_save_the_database>

For more information of ``dumpxCATdb``, please refer to :doc:`command dumpxCATdb </guides/admin-guides/references/man/dumpxCATdb.1>`. For how to restore xcat DB, please refer to `Restore xCAT User Data`_

Clean Up xCAT Related Configuration
-----------------------------------

1. To clean up the node information from dhcp ::

    makedhcp -d all

2. To clean up the node information in tftpboot ::

    nodeset all offline

3. To clean up the node information from ``/etc/hosts`` (optional)

  Keep xCAT nodes information in ``/etc/hosts`` is harmless, But if really need to remove them from ``/etc/hosts``, you can edit ``/etc/hosts`` by 'vi' directly, or using xCAT command ``makehosts`` ::

    makehosts -d all  

4. To clean up the node information from DNS (optional)

  After removing all the nodes from ``/etc/hosts``, run below command to clean up the node information from DNS ::

    makedns -n

Stop xCAT Service	
-----------------
	
1. Stop xCAT service ::

    service xcatd stop

2. Stop xCAT related services(Optional)

  xCAT uses various network services on the management node and service nodes, the network services setup by xCAT may need to be cleaned up on the management node and service nodes before uninstalling xCAT.

* **NFS** : stop nfs service, unexport all the file systems exported by xCAT, and remove the xCAT file systems from ``/etc/exports``.
* **HTTP**: stop http service, remove the xcat.conf in the http configuration directory.
* **TFTP**: stop tftp service, remove the tftp files created by xCAT in tftp directory.
* **DHCP**: stop dhcp service, remove the configuration made by xCAT in dhcp configuration files.
* **DNS** : stop the named service, remove the named entries created by xCAT from the named database.

Remove xCAT files
-----------------

1. Remove the xCAT RPMs
 
Generally, we use ``yum install xCAT`` to install xCAT. There isn't an easy way to remove all RPMs installed by xCAT(include xcat-core and xcat-dep). we have to remove the RPMs one by one. In addition to this, you have to make judgment by yourself before removing some dependance package, to avoid removing some files used by other application too in your environment.

You can obtain the RPM list from below link:

  1). xCAT Core Packages (xcat-core):
  
      `RPM Packages (RHEL and SLES) <http://xcat.org/files/xcat/repos/yum/2.10/xcat-core/>`_
	  
      `Debian Packages (Ubuntu) <http://xcat.org/files/xcat/repos/apt/2.10/xcat-core/>`_
	  
  2). xCAT Dependency Packages (xcat-dep):
  
      `RPM Packages (RHEL and SLES) <http://xcat.org/files/xcat/repos/yum/xcat-dep/>`_
	  
      `Debian Packages (Ubuntu) <http://xcat.org/files/xcat/repos/apt/xcat-dep/>`_
	  
2. Remove xCAT certificate file ::

    rm -rf $ROOTHOME/.xcat
    rm -rf /root/.xcat

3. Remove xCAT data file ::

    rm -rf /etc/xcat

4. Remove xCAT related file(Optional)

  xCAT has ever operated below directory when it was running. Do judgment by yourself before removing these directory, to avoid removing some directories used for other purpose in your environment ::

    /isntall
    /tftpboot
    /etc/yum.repos.d/*
    /etc/sysconfig/xcat
    /etc/apache2/conf.d/xcat*   
    /etc/logrotate.d/xcat*
    /etc/rsyslogd.d/xcat*
    /var/log/xcat	
    /opt/xcat/
    /mnt/xcat 
    /tmp/genimage*
    /tmp/genimage*
    /tmp/packimage*
    /tmp/mknb*

Remove Databases
----------------

* For PostgreSQL: See :doc:`Removing xCAT DB from PostgreSQL  </guides/admin-guides/large_clusters/databases/postgres_remove>`
* For MySQL/MariaDB: See :doc:`Removing xCAT DB from MySQL/MariaDB </guides/admin-guides/large_clusters/databases/mysql_remove>`

Restore xCAT User Data
----------------------

If need to restore xCAT environment, after :doc:`xCAT software installation </guides/install-guides/index>`, you can restore xCAT DB by data files dumped in the past ::

    restorexCATdb -p <path_to_save_the_database>

For more information of ``restorexCATdb``, please refer to :doc:`command restorexCATdb </guides/admin-guides/references/man/restorexCATdb.1>`