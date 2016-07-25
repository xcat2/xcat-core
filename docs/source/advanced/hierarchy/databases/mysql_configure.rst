Configure MySQL/MariaDB
=======================

Migrate xCAT to use MySQL/MariaDB
---------------------------------

The following utility is provided to migrate an existing xCAT database from SQLite to MySQL/MariaDB. ::

        mysqlsetup -i


If you need to update the database at a later time to give access to your service nodes, you can use the ``mysqlsetup -u -f`` command.  A file needs to be provided with all the hostnames and/or IP addresses of the servers that need to access the database on the Management node. Wildcards can be used. ::

        mysqlsetup -u -f /tmp/servicenodes

where the /tmp/servicenodes contains a host per line: ::

    cat /tmp/servicenodes
      node1
      1.115.85.2
      10.%.%.%
      node2.cluster.net

**While not recommended**, if you wish to manually migrate your xCAT database, see the following documentation: 
`Manually set up MySQL <https://sourceforge.net/p/xcat/wiki/Setting_Up_MySQL_as_the_xCAT_DB/#configure-mysql-manually>`_

.. _grante_revoke_mysql_access_label:

Granting/Revoking access to the database for Service Node Clients
-----------------------------------------------------------------

* Log into the MySQL interactive program.  ::

    /usr/bin/mysql -u root -p

* Granting access to the xCAT database.  Service Nodes are required for xCAT hierarchical support.  Compute nodes may also need access that depends on which application is going to run. (xcat201 is xcatadmin's password for following examples) ::

    MariaDB > GRANT ALL on xcatdb.* TO xcatadmin@<servicenode(s)> IDENTIFIED BY 'xcat201';
 
  Use the wildcards to do a GRANT ALL to every ipaddress or nodename that need to access the database. ::

    MariaDB > GRANT ALL on xcatdb.* TO xcatadmin@'%.cluster.net' IDENTIFIED BY 'xcat201';
    MariaDB > GRANT ALL on xcatdb.* TO xcatadmin@'8.113.33.%' IDENTIFIED BY 'xcat201';

* To revoke access, run the following: ::

    MariaDB > REVOKE ALL on xcatdb.* FROM xcatadmin@'8.113.33.%';

* To Verify the user table was populated. ::

   MariaDB > SELECT host, user FROM mysql.user;

  
