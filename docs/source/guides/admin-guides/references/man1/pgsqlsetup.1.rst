
############
pgsqlsetup.1
############

.. highlight:: perl


****
NAME
****


\ **pgsqlsetup**\  - Sets up the PostgreSQL database for xCAT to use.


********
SYNOPSIS
********


\ **pgsqlsetup**\  {\ **-h**\  | \ **-**\ **-help**\ }

\ **pgsqlsetup**\  {\ **-v**\  | \ **-**\ **-version**\ }

\ **pgsqlsetup**\  {\ **-i**\  | \ **-**\ **-init**\ } [\ **-N**\  | \ **-**\ **-nostart**\ ] [\ **-P**\  | \ **-**\ **-PCM**\ ] [\ **-o**\  | \ **-**\ **-odbc**\ ] [\ **-V**\  | \ **-**\ **-verbose**\ ]

\ **pgsqlsetup**\  {\ **-o**\  | \ **-**\ **-setupODBC**\ } [\ **-V**\  | \ **-**\ **-verbose**\ ]


***********
DESCRIPTION
***********


\ **pgsqlsetup**\  - Sets up the PostgreSQL database for xCAT to use. The pgsqlsetup script is run on the Management Node as root after the PostgreSQL code has been installed. The xcatd daemon will be stopped during migration.  No xCAT commands should be run during the init process, because we will be migrating the xCAT database to PostgreSQL and restarting the xcatd daemon as well as the PostgreSQL daemon. For full information on all the steps that will be done reference 
One password must be supplied for the setup,  a password for the xcatadm unix id and the same password for the xcatadm database id.  The password will be prompted for interactively or you can set the XCATPGPW environment variable to the password and then there will be no prompt.


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
 
 The init option is used to setup an installed PostgreSQL database so that xCAT can use the database.  This involves creating the xcat database, the xcat admin id, allowing access to the xcatdb database by the Management Node. It customizes the postgresql.conf configuration file, adds the management server to the pg_hba.conf and starts the PostgreSQL server.  It also backs up the current xCAT database and restores it into the newly setup xcatdb PostgreSQL database.  It creates the /etc/xcat/cfgloc file to point the xcatd daemon to the PostgreSQL database and restarts the xcatd daemon using the database. 
 On AIX, it additionally setup the xcatadm unix id and the postgres id and group. For AIX, you should be using the PostgreSQL rpms available from the xCAT website. For Linux, you should use the PostgreSQL rpms shipped with the OS. You can chose the -o option, to run after the init.
 To add additional nodes to access the PostgreSQL server, setup on the Management Node,  edit the pg_hba.conf file.
 
 For more documentation see:Setting_Up_PostgreSQL_as_the_xCAT_DB
 


\ **-N|-**\ **-nostart**\ 
 
 This option with the -i flag will create the database, but will not backup and restore xCAT tables into the database. It will create the cfgloc file such that the next start of xcatd will try and contact the database.  This can be used to setup the xCAT PostgreSQL database during or before install.
 


\ **-P|-**\ **-PCM**\ 
 
 This option sets up PostgreSQL database to be used with xCAT running with PCM.
 


\ **-o|-**\ **-odbc**\ 
 
 This option sets up the ODBC  /etc/../odbcinst.ini, /etc/../odbc.ini and the .odbc.ini file in roots home directory will be created and initialized to run off the xcatdb PostgreSQL database.
 



*********************
ENVIRONMENT VARIABLES
*********************



\ **XCATPGPW**\ 
 
 The password to be used to setup the xCAT admin id for the database.
 



********
EXAMPLES
********



1. To setup PostgreSQL for xCAT to run on the PostgreSQL xcatdb database :
 
 
 .. code-block:: perl
 
   pgsqlsetup -i
 
 


2.  To setup the ODBC for PostgreSQL xcatdb database access :
 
 
 .. code-block:: perl
 
   pgsqlsetup -o
 
 


