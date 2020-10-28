Removing ``xcatdb`` from PostgreSQL and restoring data into SQLite
==================================================================

.. note. If you are using *xCAT Hierarchy (service nodes)* and removing ``xcatdb`` from postgres, hierarchy will no longer work. You will need to configure another database which supports remote database access to continue using the hierarchy feature. ::

To remove ``xcatdb`` completely from the PostgreSQL database and restore xCAT data into SQLite:

#. Run a backup of the database to save any information that is needed: ::

      mkdir -p ~/xcat-dbback
      dumpxCATdb -p ~/xcat-dbback

#. Stop the ``xcatd`` daemon on the management node.

      service xcatd stop

#. Remove the ``xatdb`` from PostgreSQL: ::

      su - postgres

   drop the xcatdb: ::

      dropdb xcatdb

   remove the xcatadm database owner : ::

      dropuser xcatadm

   clean up the postgresql files (necessary if you want to re-create the database): ::

      cd /var/lib/pgsql/data
      rm -rf *
      exit

#. Move, or remove, the  ``/etc/xcat/cfglog`` file as it points xCAT to PostgreSQL.  (without this file, xCAT defaults to SQLite): ::

      mv /etc/xcat/cfgloc /etc/xcat/cfglog.postgres

#. Restore the PostgreSQL database into SQLite: ::

      XCATBYPASS=1 restorexCATdb -p ~/xcat-dbback

#. Restart ``xcatd``: ::

      service xcatd start

