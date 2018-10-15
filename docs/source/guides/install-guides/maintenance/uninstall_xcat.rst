Remove xCAT
===========

**We're sorry to see you go!** Here are some steps for removing the xCAT product.

Clean Up xCAT Related Configuration
-----------------------------------

1. To clean up the node information from dhcp ::

    makedhcp -d -a

2. To clean up the node information in tftpboot ::

    nodeset all offline

3. To clean up the node information from ``/etc/hosts`` (optional)

  Keeping xCAT nodes information in ``/etc/hosts`` is harmless,  but if you really want to remove them from ``/etc/hosts`` run:  ::

    makehosts -d all

4. To clean up the node information from DNS (optional)

  After removing all the nodes from ``/etc/hosts``, run below command to clean up the node information from DNS. ::

    makedns -n

Stop xCAT Service	
-----------------
	
1. Stop xCAT service ::

    service xcatd stop

2. Stop xCAT related services (optional)

  XCAT uses various network services on the management node and service nodes, the network services setup by xCAT may need to be cleaned up on the management node and service nodes before uninstalling xCAT.

* **NFS** : Stop nfs service, unexport all the file systems exported by xCAT, and remove the xCAT file systems from ``/etc/exports``.
* **HTTP**: Stop http service, remove the xcat.conf in the http configuration directory.
* **TFTP**: Stop tftp service, remove the tftp files created by xCAT in tftp directory.
* **DHCP**: Stop dhcp service, remove the configuration made by xCAT in dhcp configuration files.
* **DNS** : Stop the named service, remove the named entries created by xCAT from the named database.

Remove xCAT Files
-----------------

1. Remove xCAT Packages

  To automatically remove all xCAT packages, run the following command ::

      /opt/xcat/share/xcat/tools/go-xcat uninstall

  There is no easy way to identify all xCAT packages. For packages shipped by xCAT, you can manually remove them by using one of the commands below.

  [RHEL] ::

      yum remove conserver-xcat elilo-xcat goconserver grub2-xcat ipmitool-xcat perl-xCAT syslinux-xcat xCAT xCAT-SoftLayer xCAT-buildkit xCAT-client xCAT-confluent xCAT-csm xCAT-genesis-base-ppc64 xCAT-genesis-base-x86_64 xCAT-genesis-scripts-ppc64 xCAT-genesis-scripts-x86_64 xCAT-openbmc-py xCAT-probe xCAT-server xnba-undi yaboot-xcat

  [SLES] ::

      zypper remove conserver-xcat elilo-xcat goconserver grub2-xcat ipmitool-xcat perl-xCAT syslinux-xcat xCAT xCAT-SoftLayer xCAT-buildkit xCAT-client xCAT-confluent xCAT-csm xCAT-genesis-base-ppc64 xCAT-genesis-base-x86_64 xCAT-genesis-scripts-ppc64 xCAT-genesis-scripts-x86_64 xCAT-openbmc-py xCAT-probe xCAT-server xnba-undi yaboot-xcat

  [Ubuntu] ::	

      apt-get remove conserver-xcat elilo-xcat goconserver grub2-xcat ipmitool-xcat perl-xcat syslinux-xcat xcat xcat-buildkit xcat-client xcat-confluent xcat-genesis-base-amd64 xcat-genesis-base-ppc64 xcat-genesis-scripts-amd64 xcat-genesis-scripts-ppc64 xcat-probe xcat-server xcat-test xcat-vlan xcatsn xnba-undi

  To do an even more thorough cleanup, use links below to get a list of RPMs installed by xCAT. Some RPMs may not to be installed in a specific environment.

  * XCAT Core Packages List (xcat-core)	

    [RHEL and SLES] ::

        http://xcat.org/files/xcat/repos/yum/<version>/xcat-core/

    [Ubuntu] ::	

        http://xcat.org/files/xcat/repos/apt/<version>/xcat-core/pool/main
	
  * XCAT Dependency Packages (xcat-dep)

    [RHEL and SLES] ::

        http://xcat.org/files/xcat/repos/yum/xcat-dep/<os>/<arch>

    [Ubuntu] ::	

        http://xcat.org/files/xcat/repos/apt/xcat-dep/pool/main


  When ``yum install xCAT`` is used to install xCAT, dependency RPMs provided by the Operating System will be installed. Keeping those rpms installed on the system is harmless.


2. Remove xCAT certificate file ::

    rm -rf /root/.xcat

3. Remove xCAT data files

  By default, xCAT uses SQLite, remove SQLite data files under ``/etc/xcat/``. ::

    rm -rf /etc/xcat

4. Remove xCAT related files (optional)

  XCAT might have also created additional files and directories below. Take caution when removing these files as they may be used for other purposes in your environment. ::

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

* :doc:`Removing xCAT DB from PostgreSQL  </advanced/hierarchy/databases/postgres_remove>`.

* :doc:`Removing xCAT DB from MySQL/MariaDB </advanced/hierarchy/databases/mysql_remove>`.

