.. _mysql_as_xcat_db_target:

Using_MySQL_as_the_xCAT_DB
==========================

.. _config_mysql_manually_target:

Configure MySQL manually
------------------------

**Stop:** Did you notice as of xCAT 2.3.1, you can use the mysqlsetup script provided by xCAT to automatically accomplish
all the following manual steps. If you ran ``mysqlsetup -i``, then you can skip to "Create the lists of hosts that will
have permission to access the database." ``mysqlsetup`` adds the Management Server to the list, you will need to add any
service nodes.

This section takes you through setting up the the MySQL environment, starting the server and connecting to the
interactive program to create server definitions and perform queries.

This example assumes:

* Management Node: mn20
* xCAT database name: xcatdb
* Database user id used by xCAT for access: xcatadmin
* Database password for xcatadmin: xcat201

Substitute your addresses and desired database administration, password and database name as appropriate.

**All of the following steps should be run logged into the Management Node as root.**


The mysql user id and group already exists, and the permissions are already correct when MySQL is installed.
* Using the mysql userid, execute the script that will create the MySQL data directory and initialize the grant tables.
  ::

    /usr/bin/mysql_install_db --user=mysql

* For large systems you may need to increase ``max_connections`` to the database in the ``my.cnf`` file. The default is 100. Add
  this line to the configuration file:
  ::

    max_connections=300

* Start the MySQL server(running as root must use the --user option).
  ::

     /usr/bin/mysqld_safe --user=mysql &

  or
  ::

    service mysqld start (on sles service mysql start)

  or for **Mariadb**
  [RHEL]
  ::

    service mariadb start

  [SLES]
  ::

    service mysql start

  **If you need to stop the MySQL server:**
  Note the mysql root id must have been setup, see below.
  ::

    /usr/bin/mysqladmin -u root -p shutdown

  or
  [RHEL]
  ::

    service mysqld stop
  [SLES]
  ::

    service mysql stop

  or for Mariadb
  [RHEL]
  ::

    service mariadb stop

  [SLES]
  ::

    service mysql stop

  If command fails, check ``/var/log/mysqld.log``.

* Setup MySQL to automatically start after a reboot of the Management Node.
  ::

    chkconfig mysqld on ( on sles chkconfig mysql on)

* Set the MySQL root password in the MySQL database
  ::

    /usr/bin/mysqladmin -u root password 'new-password'

* Log into the MySQL interactive program.
  ::

    /usr/bin/mysql -u root -p

* Create the xcatdb database which will be populated with xCAT data later in this document.
  ::

    mysql > CREATE DATABASE xcatdb;

* Create the xcatadmin id and password
  ::

    mysql > CREATE USER xcatadmin IDENTIFIED BY 'xcat201';

* Create the lists of hosts that will have permission to access the database.

  First add your Management Node (MN), where the database is running. A good name to use for your MN is the name in the
  master attribute of the site table. Names must be resolvable hostnames or ip addresses. So in our example, if you run
  host mn20, make sure it returns mn20 is xxx.xx.xx.xx. If it returns a long host name such as mn20.cluster.net is
  xxx.xx.xx.xx, then put both the long and short hostname in the database. We assume below the short hostname is resolved
  to the short hostname.
  ::

    mysql > GRANT ALL on xcatdb.* TO xcatadmin@mn20 IDENTIFIED BY 'xcat201';


.. _migrate_xcat_data_mysql_target:

Migrate xCAT data to MySQL
``````````````````````````

If you are using the mysqlsetup script from xCAT2.3.1 or later, this section will automatically be done for you and you 
can skip it.
See :ref:`mysql_setup_target`.
You must backup your xCAT data before populating the xcatdb database.
There are required default entries that were created in the SQLite database when the xCAT RPMs were installed on the 
Management Node, and they must be migrated to the new MySQL database.
::

  mkdir -p ~/xcat-dbbackdumpxCATdb -p ~/xcat-dbback

Note: if you get an error, like ::

  Connection failure: IO::Socket::SSL: connect: Connection refused at....,

make sure your xcatd daemon is running.
Creating the ``/etc/xcat/cfgloc`` file tells xcat what database to use. If the file does not exists, it uses by default
SQLite, which is setup during the xCAT install by default. The information you put in the files, corresponds to the 
information you setup when you configured the database.
**Create a file called /etc/xcat/cfgloc and populate it with the following line:**
::

   mysql:dbname=xcatdb;host=mn20|xcatadmin|xcat201

The dbname is the xcatdb you previously created. The host must match what is in site.master for the Management Node 
which you entered as a resolvable hostname that could access the database with the "Grant ALL" command. The xcatadmin 
and password must match what was setup when you setup your xcatadmin and password when you created the xcatadmin and 
password.
Finally change permissions on the file, so only root can read, to protect the password.
::

  chmod 0600 /etc/xcat/cfgloc

* stop the xcatd daemon
  ::

    service xcatd stop

You must export in to the XCATCFG env variable the contents of your cfgloc file in the next step, so it will restore 
into the new database.
Restore your database to MySQL. Use bypass mode to run the command without since we have stopped xcatd.
::

  export XCATBYPASS=1
  XCATCFG="mysql:dbname=xcatdb;host=mn20|xcatadmin|xcat201" restorexCATdb -p ~/xcat-dbback

Note: If you have errors, you can go back to using SQlite, by moving ``/etc/xcat/cfgloc`` to ``/etc/xcat/cfgloc.save`` and
restarting xcatd.
Start the xcatd daemon using the MySQL database.
::

   service xcatd restart

Test the database
::

  tabdump site

Add ODBC support
----------------

**Note:** You only need to follow the steps in this section on adding ODBC support, if you plan to develop C, C++ database
applications on the database or run such applications (like LoadLeveler). Otherwise skip to the next section.

* Install ODBC package and MySQL connector.

  These packages come as part of the OS. Please make sure the following packages are installed on your management node.

  [RHEL]
  ::

    rpm -i unixODBC-*rpm -i mysql-connector-odbc-*

  [SLES]
  ::

    rpm -i unixODBC-*
    rpm -i mysql-client-*
    rpm -i libmysqlclient*
    rpm -i MyODBC-unixODBC-*

.. _setup_the_odbc_on_service_node_target:

Setup the ODBC on the Service Node
``````````````````````````````````

Configure the Service Node. **Skip this step if there are no service nodes in the cluster.** If there are service nodes in
the cluster you need to install unixODBC and MySQL connector on them and modify the ODBC configuration files just as we
did in step 1 and 2. xCAT has utilities to install additional software on the nodes. To install ODBC and MySQL on to
the service nodes, refer to the following documents for details:
Linux : :ref:`updatenode_target`.

As of xCAT 2.6, we have provided a post install script (odbcsetup), to automatically configure the ODBC after the
Service node is installed.

Add the odbcsetup postbootscript to the service entry in your postscripts table and you can skip the following
instructions on syncing the ODBC files to the service nodes.
For example on Linux, in the postscripts table:
::

  #node,postscripts,postbootscripts,comments,disable
  "xcatdefaults","syslog,remoteshell,syncfiles","otherpkgs",,
  "service","servicenode,xcatserver,xcatclient","**odbcsetup**",,

As of xCAT 2.7, the xcatserver and xcatclient postscripts are no longer needed. Your postscripts table will be
::

  #node,postscripts,postbootscripts,comments,disable
  "xcatdefaults","syslog,remoteshell,syncfiles","otherpkgs",,
  "service","servicenode","**odbcsetup**",,

If you use the odbcsetup script, you can skip to Test the ODBC connection.
If you do not use the odbcsetup script:
Then sync the ``.odbc.ini``, ``odbcinst.ini``, and ``odbc.ini`` files to the service nodes. The service is the node group name for
all the service nodes.

[RHEL]
  ::

    xdcp service -v /etc/odbcinst.ini /etc/odbcinst.ini
    xdcp service -v /etc/odbc.ini /etc/odbc.ini
    xdcp service -v /root/.odbc.ini /root/.odbc.ini

[SLES]
  ::

    xdcp service -v /etc/unixODBC/odbcinst.ini /etc/unixODBC/odbcinst.ini
    xdcp service -v /etc/unixODBC/odbc.ini /etc/unixODBC/odbc.ini
    xdcp service -v /root/.odbc.ini /root/.odbc.ini


If ``MyODBC-unixODBC-*.rpm`` is installed on the service node, you need to remove it and replace it using the steps below:
::

  rpm -e MyODBC-unixODBC-3.51.26r1127-1.25

  # tar -xzvf mysql-connector-odbc-5.1.8-linux-glibc2.3-x86-64bit.tar.gz
  mysql-connector-odbc-5.1.8-linux-glibc2.3-x86-64bit/
  mysql-connector-odbc-5.1.8-linux-glibc2.3-x86-64bit/ChangeLog
  mysql-connector-odbc-5.1.8-linux-glibc2.3-x86-64bit/INSTALL
  mysql-connector-odbc-5.1.8-linux-glibc2.3-x86-64bit/LICENSE.gpl
  mysql-connector-odbc-5.1.8-linux-glibc2.3-x86-64bit/README
  mysql-connector-odbc-5.1.8-linux-glibc2.3-x86-64bit/README.debug
  mysql-connector-odbc-5.1.8-linux-glibc2.3-x86-64bit/bin/
  mysql-connector-odbc-5.1.8-linux-glibc2.3-x86-64bit/bin/myodbc-installer
  mysql-connector-odbc-5.1.8-linux-glibc2.3-x86-64bit/lib/
  mysql-connector-odbc-5.1.8-linux-glibc2.3-x86-64bit/lib/libmyodbc5-5.1.8.so
  mysql-connector-odbc-5.1.8-linux-glibc2.3-x86-64bit/lib/libmyodbc5.so
  mysql-connector-odbc-5.1.8-linux-glibc2.3-x86-64bit/lib/libmyodbc5.la
  mysql-connector-odbc-5.1.8-linux-glibc2.3-x86-64bit/lib/libmyodbc3S-5.1.8.so
  mysql-connector-odbc-5.1.8-linux-glibc2.3-x86-64bit/lib/libmyodbc3S.so
  mysql-connector-odbc-5.1.8-linux-glibc2.3-x86-64bit/lib/libmyodbc3S.la

Copy the libraries under the extracted tar file's lib directory to ``/usr/lib64``
::

  cd mysql-connector-odbc-5.1.8-linux-glibc2.3-x86-64bit/lib/
  cp -d * /usr/lib64/

Test the ODBC connection
````````````````````````

On Linux, as root:
::

    /usr/bin/isql -v xcatdb
or as non-root user:
::

    /usr/bin/isql -v xcatdb xcatadmin xcat201

Migrate to new level MySQL
--------------------------

When migrating to a new xCAT level of MySQL go through the entire setup again. This is best to stay on your current 
level, even though a new one has been made available. In the future, we will be changing the install of MySQL to be 
more automated so this will not be the case. To summarize do the following:

#. Backup your database. Refer to section 1.3 :ref:`migrate_xcat_data_mysql_target`.
#. Stop xcatd daemon.On AIX: xcatstop '(xCAT2.4 stopsrc -s xcatd)On Linux: service xcatd stop
#. Stop the MySQL daemon.
   ::

     /usr/bin/mysqladmin -u root -p shutdown
     or
     service mysqld stop

#. Unlink the previous version of MySQL cd /usr/localrm mysql
#. Remove the old xcat database directory
   ::

     rm -rf /var/lib/mysql/*

#. Download the latest MySQL as indicated section 1.1 Install MySQL.
#. Follow the entire install process outlined in sections 1.1 Install MySQL and 1.2 Configure MySQL. You do not need to
   create the mysql id or group on AIX, since they already exist. You will need to create the /etc/my.cnf file.
#. Restore your database and start xcatd as you did in section 1.3 :ref:`migrate_xcat_data_mysql_target`.
#. You are now running on the new database level.

Diagnostics
-----------

* During restore to the MySQL database, if you see the following error message on the creation of tables:
  ::

    1071 - Specified key was too long; max key length is 1000 bytes

  Check the Default char set of xcatdb database and change to Latin1, if needed:
  ::

    Log into the MySQL interactive program
    mysql > use xcatdb;
    mysql > SHOW CREATE DATABASE xcatdb;
    if the default character set is not Latin1, then
    mysql > ALTER DATABASE xcatdb DEFAULT CHARACTER SET latin1;
    mysql > quit
    Restore you xcatdb again, or at least the tables that got errors.

* Running llconfig command get following error:
  ::

    ERROR 1227 (42000) at line 4: Access denied; you need the SUPER privilege for this operation

  Go to :ref:`mysql_granting_root_super_priviledge_target`.

Useful MySQL commands
---------------------

Log into the MySQL interactive program
::

  /usr/bin/mysql -u root -p

    mysql > show variables;
    mysql > show status;
    mysql > use xcatdb;
    mysql > show create table site;
    mysql > show tables;
    mysql > drop table prescripts;

If you lose MySql root password
-------------------------------

This web site gives instructions on how to recover if you forget your MySQL root password. This is different from the 
OS root password.
::

  http://www.cyberciti.biz/faq/mysql-reset-lost-root-password/

Here is another process that seems to work, make sure when you run mysqld stop below, all the mysql processes do stop 
and if not ``kill -9`` them. Check with ``ps -ef | grep mysql``

::

   /etc/init.d/mysqld stop
   mysqld_safe --skip-grant-tables &
   mysql -u root
   mysql >  use mysql;
   mysql >  update user set password=PASSWORD("newrootpassword") where User='root';
   mysql >  flush privileges;
   mysql >  quit
   /etc/init.d/mysqld stop
   /etc/init.d/mysqld start

.. _mysql_granting_root_super_priviledge_target:

Granting root super priviledge
------------------------------

Application, such as Loadleveler which use triggers must have the admin and root have SUPER priviledges to the MySQL 
database. If you get an error such as the following setting up the LL MySQL database, you will need to grant SUPER user 
authority.
::

  ERROR 1227 (42000) at line 4: Access denied; you need the SUPER privilege for this operation

To grant SUPER priviledge authority logon as root in interactive mode on the Management Node (MySQL server)
::

  GRANT ALL PRIVILEGES ON *.* TO 'root' @'localhost' identified by 'root_pw' WITH GRANT OPTION;
  GRANT ALL PRIVILEGES ON *.* TO 'xcatadmin' @'localhost' identified by 'xcatadmin_pw' WITH GRANT OPTION;
  flush privileges;

Show results
::

  SHOW GRANTS FOR 'root'@'localhost';

References
----------

* `mysql command <http://www.pantz.org/software/mysql/mysqlcommands.html>`_
* `mysql tutorial <http://dev.mysql.com/doc/refman/5.0/en/tutorial.html>`_
* `server-parameters <http://dev.mysql.com/doc/refman/5.1/en/server-parameters.html>`_
