xCAT Management Node Migration
==============================

This document describes how to migrate xCAT Management node to a new node. After xCAT management node is migrated, the functions and data in the new xCAT management node will be the same with those in the old xCAT management node. The following example describes a typical scenario, this example is verified on redhat7.3.

#. Initially, the first xcat management node is active, and the second node is passive.
#. Back up all useful xCAT data from xCAT Management node to back-up server at regular intervals.
#. When the first xCAT management node is broken, use backup to restore original xCAT data to the second node with the same host name and ip.

Backup Old xCAT Management Node
-------------------------------

Backup xCAT management node data to backup server:

1.1 Backup xCAT important files and directories: 

    #. Get ``installdir`` from ``site`` table, back up ``installdir`` directory, 
       in this case, back up ``install`` directory: ::
       
        lsdef -t site  clustersite -i installdir
            Object name: clustersite
            installdir=/install
    
    #. Back up these two xCAT directories: :: 

        ~/.xcat
        /etc/xcat

       **Notes**: backing up ``~/.xcat`` is for all users who have xCAT client certs. 

    #. If there are customized files and directories for ``otherpkgdir``, ``pkgdir``, ``pkglist`` or ``template`` in some `osimage` definitions, back up these files and directories. for example: ::
        
        lsdef -t osimage customized_rhels7.4-x86_64-install-compute -i otherpkgdir,pkgdir,pkglist,template
            Object name: customized_rhels7.4-x86_64-install-compute
                otherpkgdir=/<customized_dir>/post/otherpkgs/rhels7.4/x86_64
                pkgdir=/<customized_pkgdir>/rhels7.4/x86_64
                pkglist=/<customized_pkglist_dir>/compute.rhels7.pkglist
                template=/<customized_temp_dir>/compute.rhels7.tmpl

1.2 Back up ssh related files: ::

    /etc/ssh
    ~/.ssh

1.3 Back up host files: ::

    /etc/resolv.conf
    /etc/hosts

1.4 Back up yum resource files: ::

    /etc/yum.repos.d

1.5 Back up conserver conf files: ::

    /etc/conserver.cf

1.6 Back up DNS related files: ::

    /etc/named
    /etc/named.conf
    /etc/named.iscdlv.key
    /etc/named.root.key
    /etc/rndc.key
    /etc/sysconfig/named
    /var/named

1.7 Back up dhcp files: ::

    /etc/dhcp
    /var/lib/dhcpd
    /etc/sysconfig/dhcpd
    /etc/sysconfig/dhcpd6

1.8 Back up apache: ::

    /etc/httpd
    /var/www

1.9 Back up tftp files: ::

    /tftpboot

1.10 Back up NFS (optional): ::

    /etc/exports
    /var/lib/nfs
    /etc/sysconfig/nfs

1.11 (optional)

Besides the files mentioned above, there may be some additional customization files and production files that need to be backup, depending on your local unique requirements. Here are some example files that can be considered: ::

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
    /etc/services
    /etc/inittab(andmore)

1.12 Back up the xCAT database tables for the current configuration, using command: ::

    dumpxCATdb -p <your_backup_dir>

1.13 Save all installed xCAT RPM names into a file: ::

   rpm -qa|grep -i xCAT > xcat_rpm_names

1.14 (Optional) Find customization made to files installed from packages, back up these files. For example ::

   rpm -q --verify -a conserver-xcat
   rpm -q --verify -a xCAT-server
   rpm -q --verify -a syslinux-xcat
   rpm -q --verify -a xCAT-client
   rpm -q --verify -a xCAT


Restore xCAT management node
----------------------------

2.1 Power off old xCAT management server before configuring new xCAT management server

2.2 Configure new xCAT management server using the same ip and hostname as old xCAT management server, refer to :doc:`Prepare the Management Node <../../guides/install-guides/yum/prepare_mgmt_node>`
    
2.3 Overwrite files/directories methioned in above 1.2,1.3,1.4 from backup server to new xCAT management server

2.4 Download xcat-core and xcat-dep tar ball, then install xCAT in new xCAT management server, refer to :doc:`install xCAT <../../guides/install-guides/yum/install>`

2.5 Use ``rpm -qa|grep -i xCAT`` to list all xCAT RPMs in new xCAT management node, compare these RPMs base name with those in ``xcat_rpm_names`` from above 1.13. If some RPMs are missing, use ``yum install <rpm_package_basename>`` to install missing RPMs. 

2.6 If use ``MySQL``/``MariaDB``/``PostgreSQL``, refer to :doc:`Configure a Database <../hierarchy/databases/index>`

2.7 To restore the xCAT database from the ``/dbbackup/db`` directory, enter: ::

    restorexCATdb -p /dbbackup/db

  Or to restore the xCAT database including ``auditlog`` and ``eventlog`` from the ``/dbbackup/db`` directory, enter: ::

    restorexCATdb -a -p /dbbackup/db

2.8 Overwrite remaining files/directories methioned in above 1.1,1.5,1.6,1.7,1.8,1.9,1.10,1.11; If needed, check if files exist based on above 1.14.

2.9 Verify xCAT: ::

      tabdump site

2.10 Restart ``named``, use ``nslookup`` to check ``DNS``: ::

    service named restart
    nslookup <cn1>

2.11 Restart ``conserver``, use ``rcons`` to check console: ::

    service conserver restart
    rcons <cn1>

2.12 Configure DHCP: ::

    makedhcp -n
    makedhcp -a

2.13 Restart ``httpd`` for REST API, more information refer to :doc:`Rest API<../../../advanced/restapi/index>`: ::

    service httpd restart
