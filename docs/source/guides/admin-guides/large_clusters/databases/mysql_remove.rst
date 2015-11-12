Removing ``xcatdb`` from MySQL/MariaDB
======================================

To remove ``xcatdb`` completely from the MySQL/MariaDB database:

#. Run a backup of the database to save any information that is needed: ::

      mkdir -p ~/xcat-dbback
      dumpxCATdb -p ~/xcat-dbback

#. Stop the ``xcatd`` daemon on the management node.  
   **Note:** If you are using *xCAT Hierarchy (service nodes)* and removing ``xcatdb`` from MySQL/MariaDB, hierarchy will no longer work. You will need to configure another database which supports remote database access to continue using the hierarchy feature. ::

      service xcatd stop

#. Remove the ``xatdb`` from MySQL/MariaDB: :: 

     /usr/bin/mysql -u root -p 

   drop the xcatdb: ::

      mysql> drop database xcatdb;

   remove the xcatadm database owner : ::

      mysql> drop user xcatadm;

#. Move, or remove, the  ``/etc/xcat/cfglog`` file as it points xCAT to MySQL/MariaDB.  (without this file, xCAT defaults to SQLite): ::
   
      mv /etc/xcat/cfgloc /etc/xcat/cfglog.mysql

#. Restore the MySQL/MariaDB database into SQLite: ::

      XCATBYPASS=1 restorexCATdb -p ~/xcat-dbback

#. Restart ``xcatd``: ::

      service xcatd start 

