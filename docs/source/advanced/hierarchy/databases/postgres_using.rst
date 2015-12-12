Using PostgreSQL
================

Refer to `<http://www.postgresql.org/>`_ for the latest documentation.


Using ``psql``, connect to the xcat database: ::

      su - postgres
      psql -h <hostname> -U xcatadm -d xcatdb  (default pw: cluster)

list the xCAT tables: ::

      xcatdb=> \dt
 
show the entries in the nodelist table: :: 

      xcatdb=> select * from nodelist;

quit postgres: ::

      xcatdb=> \q


Useful Commands
---------------

Show the SQL create statement for a table: ::

      /usr/bin/pg_dump_xcatdb -U xcatadm -t <table_name>

      # example, for prescripts table: 
      /usr/bin/pg_dump xcatdb -U xcatadm -t prescripts

List all databases in postgres: ::

      su - postgres
      psql -l

