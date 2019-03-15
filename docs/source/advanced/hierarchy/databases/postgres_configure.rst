Configure PostgreSQL
====================

Migrate xCAT to use PostgreSQL
------------------------------

A utility is provided to migrate an existing xCAT database from SQLite to PostgreSQL. ::

    pgsqlsetup -i -V

**While not recommended**, if you wish to manually migrate your xCAT database, see the following documentation:
`Manually set up PostgreSQL <https://sourceforge.net/p/xcat/wiki/Setting_Up_PostgreSQL_as_the_xCAT_DB/#manually-setup-postgresql>`_

Setting up the Service Nodes
----------------------------

For service nodes, add the IP address of each service nodes to the postgres configuration file: ``/var/lib/pgsql/data/pg_hba.conf``

If you had the following two service nodes: ::


    sn10, ip: 192.168.1.10 with netmask 255.255.255.0
    sn11, ip: 192.168.1.11 with netmask 255.255.255.0

You would add the following to ``/var/lib/pgsql/data/pg_hba.conf`` ::

    host    all          all        192.168.1.10/32      md5
    host    all          all        192.168.1.11/32      md5

Restart PostgreSQL after editing the file: ::

    service postgresql restart


For more information about changing the ``pg_hab.conf`` file and ``postgresql.conf`` files, see the following documentation:
`Setup the PostgreSQL Configuration Files <https://sourceforge.net/p/xcat/wiki/Setting_Up_PostgreSQL_as_the_xCAT_DB/#setup-the-postgresql-configuration-files>`_

.. _modify_postgresql_database_diretory:

Modify PostgreSQL database directory
------------------------------------

#. Check the xcatdb have been switched to pgsql: ::

    lsxcatd -a
      Version 2.13.6 (git commit f8c0d11ff2c7c97d6e62389c0aafcdfa06cee1f6, built Mon Aug  7 07:15:47 EDT 2017)
      This is a Management Node
      cfgloc=Pg:dbname=xcatdb;host=10.3.5.100|xcatadm
      dbengine=Pg
      dbname=xcatdb
      dbhost=10.3.5.100
      dbadmin=xcatadm

#. Check the current working directory: ::

     sudo -u postgres psql
       could not change directory to "/root"
       psql (9.2.18)
       Type "help" for help.

       postgres=# SHOW data_directory;
          data_directory
       ---------------------
       /var/lib/pgsql/data
       (1 row)

       postgres-# \q

#. Stop postgresql service and modify the configuration files: ::

     systemctl stop postgresql
     mkdir /install/pgsql_db
     rsync -av /var/lib/pgsql/ /install/pgsql_db/

     cat /usr/lib/systemd/system/postgresql.service | grep -i PGDATA=
       Environment=PGDATA=**/install/pgsql_db/data/**

     cat /install/pgsql_db/data/postgresql.conf | grep data_directory
       #data_directory = 'ConfigDir'        # use data in another directory
       **data_directory = '/install/pgsql_db/data/'**

#. Reload, start postgresql service and check the working directory: ::

      systemctl daemon-reload
      systemctl start postgresql
      sudo -u postgres psql
        psql (9.2.18)
        Type "help" for help.

        postgres=# SHOW data_directory;
               data_directory
        ------------------------
        /install/pgsql_db/data
        (1 row)

        postgres=#

