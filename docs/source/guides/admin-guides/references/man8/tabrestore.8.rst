
############
tabrestore.8
############

.. highlight:: perl


****
NAME
****


\ **tabrestore**\  - replaces with or adds to a xCAT database table the contents in a csv file.


********
SYNOPSIS
********


\ **tabrestore**\  [\ **-a**\ ] \ *table.csv*\ 

\ **tabrestore**\  [\ **-?**\  | \ **-h**\  | \ **-**\ **-help**\ ]

\ **tabrestore**\  [\ **-v**\   | \ **-**\ **-version**\ ]


***********
DESCRIPTION
***********


The tabrestore command reads the contents of the specified file and puts its data
in the corresponding table in the xCAT database.  Any existing rows in that table
are replaced unless the (-a) flag is used and then the rows in the file are added to the table.
The file must be in csv format.  It could be created by tabdump.
Only one table can be specified.

This command can be used to copy the example table entries in /opt/xcat/share/xcat/templates/e1350
into the xCAT database.


*******
OPTIONS
*******



\ **-?|-h|-**\ **-help**\ 
 
 Display usage message.
 


\ **-v|-**\ **-version**\ 
 
 Display version.
 


\ **-a|-**\ **-addrows**\ 
 
 Add rows from the CSV file to the table instead of replacing the table with the CSV file.
 



************
RETURN VALUE
************



0. The command completed successfully.



1. An error has occurred.




********
EXAMPLES
********



1. To replace the rows in the mp table with the rows in the mp.csv file:
 
 
 .. code-block:: perl
 
   tabrestore mp.csv
 
 
 The file mp.csv could contain something like:
 
 
 .. code-block:: perl
 
    #node,mpa,id,comments,disable
    "blade","|\D+(\d+)|amm(($1-1)/14+1)|","|\D+(\d+)|(($1-1)%14+1)|",,
 
 


2. To add the rows in the mp.csv file to the rows in the mp table:
 
 
 .. code-block:: perl
 
   tabrestore -a mp.csv
 
 


3. To restore database tables from restore_directory that we dumped with dumpxCATdb:
 
 
 .. code-block:: perl
 
   restorexCATdb -p restore_directory
 
 



*****
FILES
*****


/opt/xcat/sbin/tabrestore


********
SEE ALSO
********


tabdump(8)|tabdump.8, tabedit(8)|tabedit.8, dumpxCATdb(1)|dumpxCATdb.1

