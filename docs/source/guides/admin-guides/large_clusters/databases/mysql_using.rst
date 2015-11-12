Using MySQL/MariaDB
===================

Start/Stop MySQL/MariaDB service
--------------------------------

**[RHEL]** for mariadb:  ::

    service mariadb start
    service mariadb stop

**[RHEL]** for mysql::

    service mysqld start
    service mysqld stop

**[SLES]** and **[Ubuntu]**:  ::

    service mysql start
    service mysql stop


Basic mysql commands 
--------------------------------------

Refer to `<https://www.mariadb.org/>`_ for the latest documentation.

Using ``mysql``, connect to the xcat database:  ::
   
    mysql -u root -p

list the hosts and users which managed by this xcat MN: ::
   
    MariaDB> SELECT host, user FROM mysql.user;

list the databases: ::

    MariaDB> SHOW DATABASES;

use the xcatdb:  ::

    MariaDB> use xcatdb;

list all the tables: ::

    MariaDB [xcatdb]> SHOW TABLES;

show the entries in the nodelist table: ::

    MariaDB [xcatdb]> select * from nodelist;

quit mysql: ::

    MariaDB [xcatdb]> quit;


