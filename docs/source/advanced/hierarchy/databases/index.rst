Configure a Database
====================

xCAT uses the SQLite database (https://www.sqlite.org/) as the default database and it is initialized during xCAT installation of the Management Node.  If using Service Nodes, SQLite **cannot** be used because Service Nodes require remote access to the xCAT database.  One of the following databases should be used:

    * :ref:`mysql_reference_label`
    * :ref:`postgresql_reference_label`


.. _mysql_reference_label:

MySQL/MariaDB
-------------
.. toctree::
   :maxdepth: 2

   mysql_install.rst
   mysql_configure.rst
   mysql_using.rst
   mysql_remove.rst


.. _postgresql_reference_label:

PostgreSQL
----------
.. toctree::
   :maxdepth: 2

   postgres_install.rst
   postgres_configure.rst
   postgres_using.rst
   postgres_remove.rst

