
#############
db2sqlsetup.1
#############

.. highlight:: perl


****
NAME
****


\ **db2sqlsetup**\  - Sets up the IBM DB2 for xCAT to use.


********
SYNOPSIS
********


\ **db2sqlsetup**\  [\ **-h | -**\ **-help**\ }

\ **db2sqlsetup**\  [\ **-v | -**\ **-version**\ }

\ **db2sqlsetup**\  [\ **-i | -**\ **-init**\ ] {\ **-S**\  | \ **-C**\ } [\ **-o | -**\ **-setupODBC**\ ] [\ **-V | -**\ **-verbose**\ ]

\ **db2sqlsetup**\  [\ **-i | -**\ **-init**\ ] {\ **-S**\ } [\ **-N | -**\ **-nostart**\ ] [\ **-o | -**\ **-setupODBC**\ ] [\ **-V | -**\ **-verbose**\ ]

\ **db2sqlsetup**\  [\ **-o | -**\ **-setupODBC**\ ] {\ **-S**\  | \ **-C**\ } [\ **-V | -**\ **-verbose**\ ]

\ **db2sqlsetup**\  [\ **-p | -**\ **-passwd**\ ] [\ **-S**\  | \ **-C**\ ]


***********
DESCRIPTION
***********


\ **db2sqlsetup**\  - Sets up the IBM DB2 database for xCAT to use. The db2sqlsetup script is run on the Management Node, after the DB2 Server code has been installed, to setup the DB2 Server (-S).
The xcatd daemon will be stopped during migration on the MN.  No xCAT commands should be run during the init process, because we will be migrating the xCAT database to DB2 and restarting the xcatd daemon.

The db2sqlsetup script must be  run on each Service Node, after the DB2 Client code has been installed, to setup the DB2 Client (-C). There are two postscripts that are provided ( db2install and odbcsetup) that will automatically setup you Service Node  as a DB2 client.

For full information on the setup of DB2,  see Setting_Up_DB2_as_the_xCAT_DB.

When running of db2sqlsetup on the MN:
One password must be supplied for the setup,  a password for the xcatdb unix id which will be used as the DB2 instance id and database name.  The password will be prompted for interactively or can be input with the XCATDB2PW  environment variable.
The script will create the xcat database instance (xcatdb) in the /var/lib/db2 directory unless overriden by setting the site.databaseloc attribute.  This attribute should not be set to the directory that is defined in the installloc attribute and it is recommended that the databaseloc be a new filesystem dedicated to the DB2 database, especially in very large clusters.

When running db2sqlseutp on the SN: 
Not only will the password for the DB2 instance Id be prompted for and must match the one on the Management Node;  but also the hostname or ip address of the Management Node as known by the Service Node must be supplied , unless the XCATDB2SERVER environment variable is set.  
You can automatically install and setup of DB2 on the SN using the db2install and odbcsetup postscripts and not need to manually run the command.  See the full documentation.

Note: On AIX , root must be running ksh and on Linux,  bash shell.


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
 
 The init option is used to setup an installed DB2 database on AIX or Linux (p-Series) so that xCAT can use the database. This must be combined with either the -S or -C flag to indicate whether we are setting up the Server or the Client. With the -S flag, it involves creating the xcatdb database, the xcatdb instance id, allowing access to the xcatdb database by the Management Node. It also backs up the current xCAT database and restores it into the newly setup xcatdb DB2 database.  It creates the /etc/xcat/cfgloc file to point the xcatd daemon to the DB2 database and restarts the xcatd daemon using the database.
 


\ **-p|-**\ **-passwd**\ 
 
 The password change option is to change the database access password for the DB2 xcatdb database. If -S is input then it will only change the password on the DB2 Server (MN).  If -C is input it will only change on the DB2 clients (SN).  If neither -S or -C are input with this flag, then it will change both the DB2 Server and Clients. When changing the password the xcatd daemon will be stopped and restarted.  Any other tools accessing the database should also be stopped before changing and restarted after changing.
 


\ **-S|-C**\ 
 
 This options says whether to setup the Server (-S) on the Management Node, or the Client (-C) on the Service Nodes.
 


\ **-N|-**\ **-nostart**\ 
 
 This option with the -S flag will create the database, but will not backup and restore xCAT tables into the database. It will create the cfgloc file such that the next start of xcatd will try and contact the database.  This can be used to setup the xCAT DB2 database during or before install.
 


\ **-o|-**\ **-setupODBC**\ 
 
 This option sets up the ODBC  /etc/../odbcinst.ini, /etc/../odbc.ini and the .odbc.ini file in roots home directory will be created and initialized to run off the xcatdb DB2 database.
 



*********************
ENVIRONMENT VARIABLES
*********************



\* XCATDB2INSPATH  overrides the default install path for DB2 which is /opt/ibm/db2/V9.7 for Linux and /opt/IBM/db2/V9.7 for AIX.



\* DATABASELOC override the where to create the xcat DB2 database, which is /var/lib/db2 by default of taken from the site.databaseloc  attribute.



\* XCATDB2PW can be set to the password for the xcatdb DB2 instance id so that there will be no prompting for a password when the script is run.




********
EXAMPLES
********



1. To setup DB2 Server for  xCAT to run on the DB2 xcatdb database, on the MN:
 
 
 .. code-block:: perl
 
   db2sqlsetup -i -S
 
 


2. To setup DB2 Client for  xCAT to run on the DB2 xcatdb database, on the SN:
 
 
 .. code-block:: perl
 
   db2sqlsetup -i -C
 
 


3. To setup the ODBC for  DB2 xcatdb database access, on the MN :
 
 
 .. code-block:: perl
 
   db2sqlsetup -o -S
 
 


4. To setup the ODBC for  DB2 xcatdb database access, on the SN :
 
 
 .. code-block:: perl
 
   db2sqlsetup -o -C
 
 


5.
 
 To setup the DB2 database but not start xcat running with it:
 
 
 .. code-block:: perl
 
   db2sqlsetup -i -S -N
 
 


6. To change the DB2 xcatdb password on both the Management and Service Nodes:
 
 
 .. code-block:: perl
 
   db2sqlsetup -p
 
 


