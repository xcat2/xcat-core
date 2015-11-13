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

Granting/Revoking access to the database for Service Node Clients
-----------------------------------------------------------------

https://sourceforge.net/p/xcat/wiki/Setting_Up_MySQL_as_the_xCAT_DB/#granting-or-revoking-access-to-the-mysql-database-to-service-node-clients
