
###############
restorexCATdb.1
###############

.. highlight:: perl


****
NAME
****


\ **restorexCATdb**\  - restores the xCAT db tables .


********
SYNOPSIS
********


\ **restorexCATdb**\  [\ **-a**\ ] [\ **-V**\ ] [{\ **-p | -**\ **-path**\ } \ *path*\ ]

\ **restorexCATdb**\  [\ **-b**\ ] [\ **-V**\ ] [{\ **-t | -**\ **-timestamp**\ } \ *timestamp*\ ] [{\ **-p | -**\ **-path**\ } \ *path*\ ]

\ **restorexCATdb**\  [\ **-h | -**\ **-help**\ ] [\ **-v | -**\ **-version**\ ]


***********
DESCRIPTION
***********


If not using binary restore(-b), the restorexCATdb command restores the xCAT database tables from the \*.csv files in directory given by the -p flag. The site table skiptables attribute can be set to a list of tables not to restore.  It will not restore isnm_perf\* tables. See man dumpxCATdb.

If using the binary restore option for DB2 or postgreSQL,  the entire database is restored from the binary backup made with dumpxCATdb.  The database will be restored using the database Utilities.  For DB2, the timestamp of the correct DB2 backup file (-t)  must be provided.
All applications accessing the DB2 database must be stopped before you can use the binary restore options.  See the xCAT DB2 document for more information.
For postgreSQL, you do not have to stop the applications accessing the database and the complete path to the backup file, must be supplied on the -p flag.


*******
OPTIONS
*******


\ **-h|-**\ **-help**\       Display usage message.

\ **-v|-**\ **-version**\    Command Version.

\ **-V|-**\ **-verbose**\    Verbose.

\ **-a**\              All,without this flag the eventlog and auditlog will be skipped. These tables are skipped by default because restoring will generate new indexes

\ **-b**\              Restore from the binary image.

\ **-p|-**\ **-path**\       Path to the directory containing the database restore files. If restoring from the binary image (-b) and using postgeSQL, then this is the complete path to the restore file that was created with dumpxCATdb -b.

\ **-t|-**\ **-timestamp**\  Use with the -b flag to designate the timestamp of the binary image to use to restore for DB2.


************
RETURN VALUE
************


0 The command completed successfully.

1 An error has occurred.


********
EXAMPLES
********


1. To restore the xCAT database from the /dbbackup/db directory, enter:


.. code-block:: perl

  restorexCATdb -p /dbbackup/db


2. To restore the xCAT database including auditlog and eventlog from the /dbbackup/db directory, enter:


.. code-block:: perl

  restorexCATdb -a -p /dbbackup/db


3. To restore the xCAT DB2 database from the binary image with timestamp 20111130130239 enter:


.. code-block:: perl

  restorexCATdb -b -t 20111130130239 -p /dbbackup/db


4. To restore the xCAT postgreSQL database from the binary image file pgbackup.20553 created by dumpxCATdb enter:


.. code-block:: perl

  restorexCATdb -b  -p /dbbackup/db/pgbackup.20553



*****
FILES
*****


/opt/xcat/sbin/restorexCATdb


********
SEE ALSO
********


dumpxCATdb(1)|dumpxCATdb.1

