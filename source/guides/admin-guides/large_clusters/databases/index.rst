Configure a Database
====================

xCAT requires a database to hold persistent information and currently supports the following:

    * SQLite
    * MySQL/MariaDB
    * PostgreSQL
    * DB2


SQLite
------

The SQLite database (https://www.sqlite.org/) is the default database used by xCAT and is initialized when xCAT is installed on the management node.
SQLite is a small, light-weight, daemon-less database that requires very little configuration and maintenance.  This database is sufficient for smarll to moderately sized systems (typeically < 1000 nodes).

xCAT Hierarchy (Service Nodes)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The SQLite datacase **CAN NOT** be used when using xCAT hierarchy support because the xCAT service nodes require remote access to the database.  This is one reason you would need to configure one of the alternative databases listed below:

MySQL/MariaDB
-------------

.. toctree::
   :maxdepth: 2

   mysql_install.rst
   mysql_configure.rst
   mysql_using.rst
   mysql_remove.rst


PostgreSQL
----------

.. toctree::
   :maxdepth: 2

   postgres_install.rst
   postgres_configure.rst
   postgres_using.rst
   postgres_remove.rst
