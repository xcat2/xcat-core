
############
mysqlsetup.1
############

.. highlight:: perl


****
NAME
****


\ **mysqlsetup**\  - Sets up the MySQL or MariaDB database for xCAT to use.


********
SYNOPSIS
********


\ **mysqlsetup**\  {\ **-h | -**\ **-help**\ }

\ **mysqlsetup**\  {\ **-v | -**\ **-version**\ }

\ **mysqlsetup**\  {\ **-i | -**\ **-init**\ } [\ **-f | -**\ **-hostfile**\ ] [\ **-o | -**\ **-odbc**\ ] [\ **-L | -**\ **-LL**\ ] [\ **-V | -**\ **-verbose**\ ]

\ **mysqlsetup**\  {\ **-u | -**\ **-update**\ } [\ **-f | -**\ **-hostfile**\ ] [\ **-o | -**\ **-odbc**\ ] [\ **-L | -**\ **-LL**\ ] [\ **-V | -**\ **-verbose**\ ]

\ **mysqlsetup**\  {\ **-o | -**\ **-odbc**\ } [\ **-V | -**\ **-verbose**\ ]

\ **mysqlsetup**\  {\ **-L | -**\ **-LL**\ } [\ **-V | -**\ **-verbose**\ ]


***********
DESCRIPTION
***********


\ **mysqlsetup**\  - Sets up the MySQL or MariaDB database (linux only for MariaDB) for xCAT to use. The mysqlsetup script is run on the Management Node as root after the MySQL code or MariaDB code has been installed. Before running the init option, the MySQL server should be stopped, if it is running.  The xCAT daemon, xcatd, must be running, do not stop it. No xCAT commands should be run during the init process, because we will be migrating the xCAT database to MySQL or MariaDB and restarting the xcatd daemon as well as the MySQL daemon. For full information on all the steps that will be done, read the "Configure MySQL and Migrate xCAT Data to MySQL" sections in

\ **Setting_Up_MySQL_as_the_xCAT_DB**\ 

Two passwords must be supplied for the setup,  a password for the xcatadmin id and a password for the root id in the MySQL database.  These will be prompted for interactively, unless the environment variables XCATMYSQLADMIN_PW and  XCATMYSQLROOT_PW are set to the passwords for the xcatadmin id and root id in the database,resp.

Note below we refer to MySQL but it works the same for MariaDB.


*******
OPTIONS
*******



\ **-h|-**\ **-help**\ 
 
 Displays the usage message.
 


\ **-v|-**\ **-version**\ 
 
 Displays the release version of the code.
 


\ **-V|-**\ **-verbose**\ 
 
 Displays verbose messages.
 


\ **-i|-**\ **-init**\ 
 
 The init option is used to setup a xCAT database on an installed MySQL or MariaDB server for xCAT to use. The mysqlsetup script will check for the installed MariaDB server rpm first and will use MariaDB if it is installed.   This involves creating the xcatdb database, the xcatadmin id, allowing access to the xcatdb database by the Management Node. It customizes the my.cnf configuration file for xcat and starts the MySQL server.  It also backs up the current xCAT database and restores it into the newly setup xcatdb MySQL database.  It creates the /etc/xcat/cfgloc file to point the xcatd daemon to the MySQL database and restarts the xcatd daemon using the database. 
 On AIX, it additionally setup the mysql id and group and corrects the permissions in the MySQL install directories. For AIX, you should be using the MySQL rpms available from the xCAT website. For Linux, you should use the MySQL or MariaDB rpms shipped with the OS. You can chose the -f and/or the -o option, to run after the init.
 


\ **-u|-**\ **-update**\ 
 
 To run the update option,  you must first have run the -i option and have xcat successfully running on the MySQL database. You can chose the -f and/or the -o option, to update.
 


\ **-f|-**\ **-hostfile**\ 
 
 This option runs during update, it will take all the host from the input file (provide a full path) and give them database access to the xcatdb in  MySQL for the xcatadmin id. Wildcards and ipaddresses may be used. xCAT  must have been previously successfully setup to use MySQL. xcatadmin and MySQL root password are required.
 


\ **-o|-**\ **-odbc**\ 
 
 This option sets up the ODBC  /etc/../odbcinst.ini, /etc/../odbc.ini and the .odbc.ini file in roots home directory will be created and initialized to run off the xcatdb MySQL database.
 See "Add ODBC Support" in
 Setting_Up_MySQL_as_the_xCAT_DB
 


\ **-L|-**\ **-LL**\ 
 
 Additional database configuration specifically for the LoadLeveler product. 
 See "Add ODBC Support" in
 Setting_Up_MySQL_as_the_xCAT_DB
 



*********************
ENVIRONMENT VARIABLES
*********************



\* \ **XCATMYSQLADMIN_PW**\  - the password for the xcatadmin id that will be assigned in the MySQL database.



\* \ **XCATMYSQLROOT_PW**\  - the password for the root id that will be assigned to the MySQL root id, if the script creates it.  The password to use to run MySQL command to the database as the MySQL root id.  This password may be different than the unix root password on the Management Node.




********
EXAMPLES
********



1.
 
 To setup MySQL for xCAT to run on the MySQL xcatdb database :
 
 
 .. code-block:: perl
 
   mysqlsetup -i
 
 


2.
 
 Add hosts from /tmp/xcat/hostlist that can access the xcatdb database in MySQL:
 
 
 .. code-block:: perl
 
   mysqlsetup -u -f /tmp/xcat/hostlist
 
 
 Where the file contains a host per line, for example:
 
 
 .. code-block:: perl
 
           node1
           1.115.85.2
           10.%.%.%
           nodex.cluster.net
 
 


3.
 
 To setup the ODBC for MySQL xcatdb database access :
 
 
 .. code-block:: perl
 
   mysqlsetup -o
 
 


4.
 
 To setup MySQL for xCAT and add hosts from /tmp/xcat/hostlist and setup the ODBC in Verbose mode:
 
 
 .. code-block:: perl
 
   mysqlsetup -i -f /tmp/xcat/hostlist -o -V
 
 


