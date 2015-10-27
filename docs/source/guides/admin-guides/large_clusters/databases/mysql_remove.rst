.. _removing_xcat_from_mysql_target:

Removing ``xcatdb`` from MySQL/MariaDB
======================================

To remove the database, first run a backup:
::

   mkdir -p ~/xcat-dbback
   dumpxCATdb -p ~/xcat-dbback

Stop the xcatd daemon
::

    service xcatd stop

Now remove the database.
::

  /usr/bin/mysql -u root -p
  mysql> drop database xcatdb;

Move /etc/xcat/cfgloc file ( points xCAT to MySQL) ::

  mv /etc/xcat/cfgloc /etc/xcat/cfgloc.mysql

Switch the MySQL database to SQLite ::

  XCATBYPASS=1 restorexCATdb -p ~/xcat-dbback

Start xcatd ::

   service xcatd start

If you wish to remove all MySQL
Stop the MySQL daemon
use ``rpm -e`` to remove the ``xcat-mysql`` rpm
Remove the ``/var/lib/mysql`` directory
