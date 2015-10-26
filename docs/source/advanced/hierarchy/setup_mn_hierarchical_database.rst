Setup the MN Hierarchical Database
==================================

Before setting up service nodes, you need to set up either MySQL, PostgreSQL,
as the xCAT Database on the Management Node. The database client on the
Service Nodes will be set up later when the SNs are installed. MySQL and
PostgreSQL are available with the Linux OS.

Follow the instructions in one of these documents for setting up the
Management node to use the selected database:

MySQL or MariaDB
----------------

* Follow this documentation and be sure to use the xCAT provided mysqlsetup
  command to setup the database for xCAT 3:

  -  :doc:`/guides/admin-guides/large_clusters/databases/mysql_install`

PostgreSQL:
-----------
* Follow this documentation and be sure and use the xCAT provided pgsqlsetup
  command to setup the database for xCAT:

  -  :doc:`/guides/admin-guides/large_clusters/databases/postgres_install`
