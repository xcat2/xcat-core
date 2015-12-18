PostgreSQL tips
===============

Using PostgreSQL
----------------

* Connect to the database

Use the psql command line utility to connect to the PostgreSQL database: ::

    su - postgres
    psql -h <hostname> -U xcatadm -d xcatdb 


Useful Commands
---------------

* Show create statement for a table, for example prescripts table. :: 

    /usr/bin/pg_dump xcatdb -U xcatadm -t prescripts

* Clean up the xcatdb completely from PostgreSQL: ::

    su - postgres

    # drop the xcatdb
    dropdb xcatdb

    # remove the xcatadm database owner 
    dropuser xcatadm

    # clean up the postgresql files (necessary if you want to re-create the database)
    cd /var/lib/pgsql/data
    rm -rf *

* List databases:  ::

    su - postgres
    psql -l

* Access the database: :: 

    su - postgres
    psql xcatdb
    SELECT * FROM "pg_user";    Select all users
    SELECT * FROM "site";   Select the site table
    SELECT MAX(recid) from "auditlog";
    SELECT MIN(recid) from "auditlog";
    drop table zvm;   Removes a table
    \dt    Select all tables
    \?  help
    \q   exit

