Removing ``xcatdb`` from MySQL/MariaDB
======================================

If you no longer want to use MySQL/MariaDB to maintain ``xcatdb``, and like to switch to PostgreSQL or just default SQLite ( **Note:** SQLite does not support xCAT Hierarchy (has service nodes)), use the following documentation as guide to remove ``xcatdb``.

*  Run a backup of the database to save any information that is needed (optional): ::

      mkdir -p ~/xcat-dbback
      dumpxCATdb -p ~/xcat-dbback

   If you want to restore this database later: ::

      XCATBYPASS=1 restorexCATdb -p ~/xcat-dbback

*  Change to PostgreSQL, following documentation: :doc:`/advanced/hierarchy/databases/postgres_install` 


*  Change back to default xCAT database, SQLite (**Note**:  xCAT Hierarchy cluster will no longer work)

  #. Stop the ``xcatd`` daemon on the management node. :: 

      service xcatd stop

  #. Remove the ``xatdb`` from MySQL/MariaDB (optional): :: 

      /usr/bin/mysql -u root -p 

     drop the xcatdb: ::

       mysql> drop database xcatdb;

     remove the xcatadm database owner : ::

       mysql> drop user xcatadm;

  #. Move, or remove, the  ``/etc/xcat/cfglog`` file as it points xCAT to MySQL/MariaDB.  (without this file, xCAT defaults to SQLite): ::
   
      rm /etc/xcat/cfgloc 

  #. Restart ``xcatd``: ::

      service xcatd start 

