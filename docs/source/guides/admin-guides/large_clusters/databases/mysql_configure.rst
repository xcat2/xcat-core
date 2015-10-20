Configure MySQL/MariaDB
=======================

Migrate xCAT to use MySQL/MariaDB
---------------------------------

The following utility is provided to migrate an existing xCAT database from SQLite to MySQL/MariaDB. ::

        mysqlsetup -i


If you need to update the database at a later time to give access to your service nodes, you can use the ``mysqlsetup -u -f`` command.  A file needs to be provided with all the hostnames and/or IP addresses of the servers that need to access the database on the Management node. Wildcards can be used. ::

        TODO: Show an example here of file1 

        mysqlsetup -u -f /path/to/file1

**While not recommended**, if you wish to manually migrate your xCAT database, see the following documentation: 
:ref:`config_mysql_manually_target`


.. _mysql_access_to_service_client_target:

Granting/Revoking access to the database for Service Node Clients
-----------------------------------------------------------------

* Log into the MySQL interactive program.
  ::

    /usr/bin/mysql -u root -p

* Granting access to the xCAT database

  Next add all other nodes that need access to the database. Service Nodes are required for xCAT hierarchical support.
  Compute nodes may also need access depending on the application running.
  ::

    mysql > GRANT ALL on xcatdb.* TO xcatadmin@<servicenode(s)> IDENTIFIED BY 'xcat201';

  ** Note: **You want to do a GRANT ALL to every ipaddress or nodename that will need to access the database. You can use
  wildcards as follows:
  ::

    mysql > GRANT ALL on xcatdb.* TO xcatadmin@'%.cluster.net' IDENTIFIED BY 'xcat201';
    mysql > GRANT ALL on xcatdb.* TO xcatadmin@'8.113.33.%' IDENTIFIED BY 'xcat201';

  You can also use the following to add these hosts, see man mysqlsetup, where you define the hostnames in the input
  hostfile.
  ::

    mysqlsetup -f <hostfile>

  - **To revoke access, run the following:**
    ::

      REVOKE ALL on xcatdb.* FROM xcatadmin@'8.113.33.%';

  - Verify the user table was populated.*
    ::

      mysql > SELECT host, user FROM mysql.user;

    +-------------+-------------+
    |   %         | xcatadmin   |
    +=============+=============+
    |  127.0.0    | root        |
    +-------------+-------------+
    | %cluster.net| xcatadmin   |
    +-------------+-------------+
    | localhost   | root        |
    +-------------+-------------+
    | mn20        | xcatadmin   |
    +-------------+-------------+

  - Check system variables
    ::

      mysql > SHOW VARIABLES;

  - Check the defined databases.
    ::

      mysql > SHOW DATABASES;

    +-------------+
    |   Database  |
    +=============+
    |   mysql     |
    +-------------+
    |   test      |
    +-------------+
    |   xcatdb    |
    +-------------+

The following shows you how to view the tables. At this point no tables have been defined in the xcatdb yet. Run again
after the database is populated.
::

  mysql > use xcatdb;
  mysql > SHOW TABLES;
  mysql > DESCRIBE <tablename>;

Exit out of MySQL.
::

  mysql > quit;

