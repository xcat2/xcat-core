
############
dumpxCATdb.1
############

.. highlight:: perl


****
NAME
****


\ **dumpxCATdb**\  - dumps the xCAT db tables .


********
SYNOPSIS
********


\ **dumpxCATdb**\  [\ **-a**\ ] [\ **-V**\ ] [{\ **-p | -**\ **-path**\ } \ *path*\ ]

\ **dumpxCATdb**\  [\ **-b**\ ] [\ **-V**\ ] [{\ **-p | -**\ **-path**\ } \ *path*\ ]

\ **dumpxCATdb**\  [\ **-h | -**\ **-help**\ ] [\ **-v | -**\ **-version**\ ]


***********
DESCRIPTION
***********


If not using the binary dump option (-b), then the dumpxCATdb command creates .csv files for xCAT database tables and puts them in the directory given by the -p flag. These files can be used by the restorexCATdb command to restore the database. The command will read the list of tables in the site.skiptables attribute and not backup those tables.
Supports using XCAT_SKIPTABLES env variable to provide a list of skip tables.
The command will never backup TEAL or ISNM tables, except isnm_config.  To dump TEAL tables use the documented process for TEAL.  For ISNM use tabdump, after using tabprune to get to prune unnecessary records.

If using the binary dump option for the DB2 or postgreSQL database, then the routine will use the Database provide utilites for backup of the entire database.


*******
OPTIONS
*******


\ **-h**\           Display usage message.

\ **-v**\           Command Version.

\ **-V**\           Verbose.

\ **-a**\           All,without this flag the eventlog and auditlog will be skipped.

\ **-b**\           This flag is only used for the DB2 or postgreSQL database. The routine will use the database backup utilities to create a binary backup of the entire  database. Note to use this backup on DB2, you will have first had to modify the logging of the database and have taken an offline initial backup. Refer to the xCAT DB2 documentation for more instructions.

\ **-p**\           Path to the directory to dump the database. It will be created, if it does not exist.


************
RETURN VALUE
************


0 The command completed successfully.

1 An error has occurred.


********
EXAMPLES
********


1. To dump the xCAT database into the /tmp/db directory, enter:


.. code-block:: perl

  dumpxCATdb -p /tmp/db


2. To dump the xCAT database into the /tmp/db directory, including the auditlog and eventlog enter:


.. code-block:: perl

  dumpxCATdb -a -p /tmp/db


3. To have dumpxCATdb not backup the hosts or passwd table:


.. code-block:: perl

  chtab key=skiptables site.value="hosts,passwd"
 
  dumpxCATdb  -p /tmp/db


4. To have dumpxCATdb not backup the hosts or passwd table:


.. code-block:: perl

  export XCAT_SKIPTABLES="hosts,passwd"
 
  dumpxCATdb  -p /tmp/db


5. To have dumpxCATdb use DB2 utilities to backup the DB2 database:


.. code-block:: perl

  dumpxCATdb -b -p /install/db2backup



*****
FILES
*****


/opt/xcat/sbin/dumpxCATdb


********
SEE ALSO
********


restorexCATdb(1)|restorexCATdb.1

