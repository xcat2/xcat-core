Databases
=========

xCAT Supports the following databases to be used by xCAT on the Management node

* SQLite
* MySQL/MariaDB
* PostgreSQL
* DB2


SQLite
------

SQLite database is the default database used by xCAT and is initialized when xCAT is installed on the management node.

SQLite is a small, light-weight, daemon-less database that requires no configuration or maintenance. This database is sufficient for small to moderate size systems ( < 1000 nodes ) when xCAT hierarchy (*service nodes*) is not being used.  The SQLite database cannot be used for hierarchy because service nodes requires remote access to the database and SQLite does not support remote access.  

For hierarchy, you will need to use one of the following alternate databases. 

MySQL/MariaDB
-------------

.. toctree::
   :maxdepth: 2

   mysql_install.rst
   mysql_configure.rst



PostgreSQL
----------

.. toctree::
   :maxdepth: 2

   postgres_install.rst
   postgres_configure.rst
   postgres_tips.rst
