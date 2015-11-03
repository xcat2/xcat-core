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

  There isn't an easy way to remove all RPMs installed because of xCAT. you can just remove the RPMs calculated by below command. Depending on the past experience, it's safe.
  
  [RHEL and SLES] ::

      rpm -qa |grep -i xcat

  [Ubuntu] ::	  
  
	  dpkg -l | awk  '{ print $2 }' |grep -i xcat

  If you want to remove more cleanly. below list maybe helpful for you. They are the packages list of xcat installation tarball. These list are the whole RPMs list, it's possible for some RPMs not to be installed due to them are not suitable for your environment. Please do judgment by yourself.

* xCAT Core Packages list (xcat-core):

    [RHEL and SLES] ::
	
      perl-xCAT
      xCAT
      xCAT-buildkit
      xCAT-client
      xCAT-confluent
      xCAT-genesis-scripts-ppc64
      xCAT-genesis-scripts-x86_64
      xCAT-server
      xCATsn
      xCAT-SoftLayer
      xCAT-test
      xCAT-vlan
	
    [Ubuntu] ::
	
      perl-xcat
      xcat
      xcat-buildkit
      xcat-client
      xcat-confluent
      xcat-genesis-scripts
      xcat-server
      xcatsn
      xcat-test
      xcat-vlan

* xCAT Dependency Packages (xcat-dep):	

    [RHEL and SLES] ::
	
	conserver-xcat
	cpio
	cpio-lang
	elilo-xcat
	esxboot-xcat
	fping
	ganglia-devel
	ganglia-gmetad
	ganglia-gmond
	ganglia-gmond-modules-python
	ganglia-web
	grub2-xcat
	ipmitool-xcat
	libconfuse
	libconfuse-devel
	libganglia
	lldpd
	net-snmp-perl
	perl-AppConfig
	perl-Compress-Raw-Zlib
	perl-Crypt-Blowfish
	perl-Crypt-CBC
	perl-Crypt-Rijndael
	perl-Crypt-SSLeay
	perl-DBD-DB2
	perl-DBD-DB2Lite
	perl-DBD-Pg
	perl-DBD-SQLite
	perl-Expect
	perl-HTML-Form
	perl-IO-Compress-Base
	perl-IO-Compress-Zlib
	perl-IO-Socket-SSL
	perl-IO-Stty
	perl-IO-Tty
	perl-JSON
	perl-Net-DNS
	perl-Net-Telnet
	perl-SOAP-Lite
	perl-Test-Manifest
	perl-version
	perl-XML-Simple
	pyodbc
	rrdtool
	scsi-target-utils
	stunnel
	syslinux-xcat
	systemconfigurator
	systemimager-client
	systemimager-common
	systemimager-server
	xCAT-genesis-base-ppc64
	xCAT-genesis-base-x86_64
	xCAT-genesis-x86_64
	xCAT-UI-deps
	xnba-kvm
	xnba-undi
	yaboot-xcat
	zhcp

    [Ubuntu] ::
	
	conserver-xcat
	elilo-xcat
	grub2-xcat
	ipmitool-xcat
	syslinux
	syslinux-extlinux
	syslinux-xcat
	xcat-genesis-base-amd64
	xcat-genesis-base-ppc64
	xnba-undi	

  Along with xCAT development, above list maybe change, you can get the latest list through below links:

  
* xCAT Core Packages list (xcat-core)	

  [RHEL and SLES] ::
  
    http://xcat.org/files/xcat/repos/yum/<version>/xcat-core/

  [Ubuntu] ::	
  
    http://xcat.org/files/xcat/repos/apt/<version>/xcat-core/
	  
* xCAT Dependency Packages (xcat-dep)

      `RPM Packages List (RHEL and SLES) <http://xcat.org/files/xcat/repos/yum/xcat-dep/>`_
	  
      `Debian Packages List (Ubuntu) <http://xcat.org/files/xcat/repos/apt/xcat-dep/>`_
	

  Generally, we use ``yum install xCAT`` to install xCAT. so these are some RMPs shipped by operating system are installed during xCAT installation. We don't have a easy way to find out all of them, but keep these RPMs is harmless. 


2. Remove xCAT certificate file ::

    rm -rf /root/.xcat

3. Remove xCAT data file 

  By default, xCAT use SQLite, remove SQLite data file under ``/etc/xcat/`` ::

    rm -rf /etc/xcat

4. Remove xCAT related file(Optional)

  xCAT has ever operated below directory when it was running. Do judgment by yourself before removing these directory, to avoid removing some directories used for other purpose in your environment ::

    /install
    /tftpboot
    /etc/yum.repos.d/xCAT-*
    /etc/sysconfig/xcat
    /etc/apache2/conf.d/xCAT-*
    /etc/logrotate.d/xCAT-*
    /etc/rsyslogd.d/xCAT-*
    /var/log/xcat	
    /opt/xcat/
    /mnt/xcat  

Remove Databases
----------------

* For PostgreSQL: See :doc:`Removing xCAT DB from PostgreSQL  </guides/admin-guides/large_clusters/databases/postgres_remove>`
* For MySQL/MariaDB: See :doc:`Removing xCAT DB from MySQL/MariaDB </guides/admin-guides/large_clusters/databases/mysql_remove>`

Restore xCAT User Data
----------------------

If need to restore xCAT environment, after :doc:`xCAT software installation </guides/install-guides/index>`, you can restore xCAT DB by data files dumped in the past ::

    restorexCATdb -p  <path_to_backup_saved_for_restore>

For more information of ``restorexCATdb``, please refer to :doc:`command restorexCATdb </guides/admin-guides/references/man/restorexCATdb.1>`