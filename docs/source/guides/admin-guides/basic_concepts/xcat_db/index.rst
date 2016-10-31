xCAT Database
=============

All of the xCAT Objects and Configuration data are stored in xCAT database. By default, xCAT uses **SQLite** - an OS contained simple database engine. The powerful open source database engines like MySQL, MariaDB, PostgreSQL are also supported for a large cluster.

xCAT defines about 70 tables to store different data. You can get the xCAT database definition from file ``/opt/xcat/lib/perl/xCAT/Schema.pm``.

You can run ``tabdump`` command to get all the xCAT database tables. Or run ``tabdump -d <tablename>`` or ``man <tablename>`` to get the detail information on columns and table definitions. ::

    $ tabdump
    $ tabdump site
    $ tabdump -d site 
    $ man site

For a complete reference, see the man page for xcatdb: ``man xcatdb``.

**The tables in xCAT:**

* **site table**

  Global settings for the whole cluster. This table is different from the other tables. Each entry in **site table** is a key=>value pair. Refer to the :doc:`Global Configuration </guides/admin-guides/basic_concepts/global_cfg/index>` page for the major global attributes or run ``man site`` to get all global attributes.

* **policy table**

  Controls who has authority to run specific xCAT operations. It is the Access Control List (ACL) in xCAT. 

* **passwd table**

  Contains default userids and passwords for xCAT to access cluster components. In most cases, xCAT will also set the userid/password in the relevant component (Generally for SP like bmc, fsp.) when it is being configured or installed. The default userids/passwords in passwd table for specific cluster components can be overridden by the columns in other tables, e.g. ``mpa`` , ``ipmi`` , ``ppchcp`` , etc.

* **networks table**

  Contains the network definitions in the cluster.

  You can manipulate the networks through ``*def command`` against the **network object**. ::

    $ lsdef -t network 

* **...**

**Manipulate xCAT Database Tables**

xCAT offers 5 commands to manipulate the database tables:

* ``tabdump``

  Displays the header and all the rows of the specified table in CSV (comma separated values) format.

* ``tabedit``

  Opens the specified table in the user's editor, allows them to edit any text, and then writes changes back to the database table.  The table is flattened into a CSV (comma separated values) format file before giving it to the editor.  After the editor is exited, the CSV file will be translated back into the database format.

* ``tabgrep``

  List table names in which an entry for the given node appears.

* ``dumpxCATdb``

  Dumps all the xCAT db tables to CSV files under the specified directory, often used to backup the xCAT database for xCAT reinstallation or management node migration.

* ``restorexCATdb``

  Restore the xCAT db tables from the CSV files under the specified directory.

**Advanced Topic: How to use Regular Expression in xCAT tables:**

.. toctree::
   :maxdepth: 2
          
   regexp_db.rst 
