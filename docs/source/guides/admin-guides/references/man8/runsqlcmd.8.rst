
###########
runsqlcmd.8
###########

.. highlight:: perl


****
NAME
****


\ **runsqlcmd**\  -Runs sql command files against the current xCAT database.


********
SYNOPSIS
********


\ **runsqlcmd**\ 

\ **runsqlcmd**\  [\ **-h | -**\ **-help**\ ]

\ **runsqlcmd**\  [\ **-v | -**\ **-version**\ ]

\ **runsqlcmd**\  [\ **-d | -**\ **-dir**\  \ *directory_path*\ ] [\ **-V | -**\ **-verbose**\ ]

\ **runsqlcmd**\  [\ **-f | -**\ **-files**\  \ *list of files*\ ] [\ **-V | -**\ **-verbose**\ ]

\ **runsqlcmd**\  [\ **-V | -**\ **-verbose**\ ] [\ *sql statement*\ ]


***********
DESCRIPTION
***********


The runsqlcmd routine,  runs the sql statements contained in the \*.sql files as input to the command against the current running xCAT database. Only DB2,MySQL and PostgreSQL databases are supported.  SQLite is not supported.  
If no directory or filelist is provided,  the default /opt/xcat/lib/perl/xCAT_schema directory is used.
If the directory is input with the -d flag,  that directory will be used.
If a comma separated list of files is input with the -f flag, those files will be used.


*******
OPTIONS
*******



\ **-h|-**\ **-help**\ 
 
 Displays the usage message.
 


\ **-v|-**\ **-version**\ 
 
 Displays current code version.
 


\ **-V|-**\ **-verbose**\ 
 
 Displays extra debug information.
 


\ **-d|-**\ **-dir**\ 
 
 To use a directory other than the default directory,  enter the directory path here.
 


\ **-f|-**\ **-files**\ 
 
 Comma separated list of files (full path), wildcard (\*) can be used.
 


\ **File format**\ 
 
 The files must be of the form <name>.sql or <name>_<database>.sql  where
 
 <database>  is mysql,pgsql, or db2. Files must have permission 0755.
 


\ *sql statement*\ 
 
 Quoted sql statement syntax appropriate for the current database.
 



********
EXAMPLES
********



1. To run the database appropriate \*.sql files in /opt/xcat/lib/perl/xCAT_schema :
 
 
 .. code-block:: perl
 
   runsqlcmd
 
 


2. To run the database appropriate \*.sql files in /tmp/mysql:
 
 
 .. code-block:: perl
 
   runsqlcmd -d /tmp/mysql
 
 


3. To run the database appropriate \*.sql files in the input list:
 
 
 .. code-block:: perl
 
   runsqlcmd -f "/tmp/mysql/test*,/tmp/mysql/test1*"
 
 


4. To checkout one DB2 sql file:
 
 
 .. code-block:: perl
 
   runsqlcmd -f /tmp/db2/test_db2.sql
 
 


5. To run the following command to the database:
 
 
 .. code-block:: perl
 
   runsqlcmd "Select * from site;"
 
 


