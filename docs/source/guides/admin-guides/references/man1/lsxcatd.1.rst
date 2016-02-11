
#########
lsxcatd.1
#########

.. highlight:: perl


****
NAME
****


\ **lsxcatd**\  - lists xCAT daemon information.


********
SYNOPSIS
********


\ **lsxcatd**\  [\ **-h**\  | \ **-**\ **-help**\  | \ **-v**\  | \ **-**\ **-version**\  | \ **-d**\  | \ **-**\ **-database**\  | \ **-t**\  | \ **-**\ **-nodetype**\  | \ **-a**\  | \ **-**\ **-all**\  ]


***********
DESCRIPTION
***********


The \ **lsxcat**\  command lists important xCAT daemon (xcatd) information.


*******
OPTIONS
*******



\ **-v|-**\ **-version**\ 
 
 Command Version.
 


\ **-h|-**\ **-help**\ 
 
 Display usage message.
 


\ **-d|-**\ **-database**\ 
 
 Displays information about the current database being used by xCAT.
 


\ **-t|-**\ **-nodetype**\ 
 
 Displays whether the node is a Management Node or a Service Node.
 


\ **-a|-**\ **-all**\ 
 
 Displays all information about the daemon supported by the command.
 



************
RETURN VALUE
************


0  The command completed successfully.

1  An error has occurred.


********
EXAMPLES
********



1.
 
 To display information about the current database:
 
 
 .. code-block:: perl
 
   lsxcatd -d
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
    cfgloc=Pg:dbname=xcatdb;host=7.777.47.250|xcatadm
    dbengine=Pg
    dbname=xcatdb
    dbhost=7.777.47.250
    dbadmin=xcatadm
 
 


2.
 
 To display all information:
 
 
 .. code-block:: perl
 
   lsxcatd -a
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   Version 2.8.5 (git commit 0d4888af5a7a96ed521cb0e32e2c918a9d13d7cc, built Tue Jul 29 02:22:47 EDT 2014)
   This is a Management Node
   cfgloc=mysql:dbname=xcatdb;host=9.114.34.44|xcatadmin
   dbengine=mysql
   dbname=xcatdb
   dbhost=9.114.34.44
   dbadmin=xcatadmin
 
 



*****
FILES
*****


/opt/xcat/bin/lsxcatd


********
SEE ALSO
********


