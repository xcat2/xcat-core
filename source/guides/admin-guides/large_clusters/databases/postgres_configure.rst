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

    sn10 192.168.1.10
    sn11 192.168.1.11

You would add the following to ``/var/lib/pgsql/data/pg_hba.conf`` ::

    host    all          all        11.16.1.230/32      md5
    host    all          all        11.16.2.230/32      md5

Restart PostgreSQL after editing the file: ::

    service postgresql restart 


For more information about changing the ``pg_hab.conf`` file and ``postgresql.conf`` files, see the following documentation: 
`Setup the PostgreSQL Configuraion Files <https://sourceforge.net/p/xcat/wiki/Setting_Up_PostgreSQL_as_the_xCAT_DB/#setup-the-postgresql-configuration-files>`_
