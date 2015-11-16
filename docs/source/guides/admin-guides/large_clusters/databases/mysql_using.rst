Using MySQL/MariaDB
===================

Start/Stop MySQL/MariaDB service
--------------------------------

**[RHEL]** for MariaDB:  ::

    service mariadb start
    service mariadb stop

**[RHEL]** for MySQL::

    service mysqld start
    service mysqld stop

**[SLES]** and **[Ubuntu]**:  ::

    service mysql start
    service mysql stop


Basic MySQL/MariaDB commands 
-----------------------------

Refer to `<https://www.mariadb.org/>`_ for the latest documentation.

* Using ``mysql``, connect to the xcat database:  ::
   
    mysql -u root -p

* List the hosts and users which managed by this xcat MN: ::
   
    MariaDB> SELECT host, user FROM mysql.user;

* List the databases: ::

    MariaDB> SHOW DATABASES;

* Use the xcatdb:  ::

    MariaDB> use xcatdb;

* List all the tables: ::

    MariaDB [xcatdb]> SHOW TABLES;

* Show the entries in the nodelist table: ::

    MariaDB [xcatdb]> select * from nodelist;

* Quit mysql: ::

    MariaDB [xcatdb]> quit;


