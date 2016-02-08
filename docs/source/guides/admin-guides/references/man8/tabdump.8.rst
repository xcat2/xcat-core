
#########
tabdump.8
#########

.. highlight:: perl


****
NAME
****


\ **tabdump**\  - display an xCAT database table in CSV format.


********
SYNOPSIS
********


\ **tabdump**\ 

\ **tabdump**\  [\ **-d**\ ] [\ *table*\ ]

\ **tabdump**\  [\ *table*\ ]

\ **tabdump**\  [\ **-f**\  \ *filename*\ ] [\ *table*\ ]

\ **tabdump**\  [\ **-n**\  \ *# of records*\ ] [\ **auditlog**\  | \ **eventlog**\ ]

\ **tabdump**\  [\ **-w**\  \ *attr*\ ==\ *val*\ ] [\ **-w**\  \ *attr*\ =~\ *val*\ ] ...] [\ *table*\ ]

\ **tabdump**\  [\ **-w**\  \ *attr*\ ==\ *val*\ ] [\ **-w**\  \ *attr*\ =~\ *val*\ ] ...] [\ **-f**\  \ *filename*\ ] [\ *table*\ ]

\ **tabdump**\  [\ **-v**\  | \ **-**\ **-version**\ ]

\ **tabdump**\  [\ **-?**\  | \ **-h**\  | \ **-**\ **-help**\ ]


***********
DESCRIPTION
***********


The tabdump command displays the header and all the rows of the specified table in CSV (comma separated values) format.
Only one table can be specified.  If no table is specified, the list of existing
tables will be displayed.


*******
OPTIONS
*******



\ **-?|-h|-**\ **-help**\ 
 
 Display usage message.
 


\ **-d**\ 
 
 Show descriptions of the tables, instead of the contents of the tables.  If a table name is also specified, descriptions of the columns (attributes) of the table will be displayed.  Otherwise, a summary of each table will be displayed.
 


\ **-n**\ 
 
 Shows the most recent number of entries as supplied on the -n flag from the auditlog or eventlog table.
 


\ **-f**\ 
 
 File name or path to file in which to dump the table. Without this the table is dumped
 to stdout.  Using the -f flag allows the table to be dumped one record at a time. If tables are very large, dumping to stdout can cause problems such as running out of memory.
 


\ **-w**\  \ *'attr==val'*\  \ **-w**\  \ *'attr=~val'*\  ...
 
 Use one or multiple -w flags to specify the selection string that can be used to select particular rows of the table. See examples.
 
 Operator descriptions:
 
 
 .. code-block:: perl
 
          ==        Select nodes where the attribute value is exactly this value.
          !=        Select nodes where the attribute value is not this specific value.
          >         Select nodes where the attribute value is greater than this  specific value.
          >=        Select nodes where the attribute value is greater than or equal to this  specific value.
          <         Select nodes where the attribute value is less than this  specific value.
          <=        Select nodes where the attribute value is less than or equal to this  specific value.
          =~        Select nodes where the attribute value matches the SQL LIKE value.
          !~        Select nodes where the attribute value matches the SQL NOT LIKE value.
 
 



************
RETURN VALUE
************



0.  The command completed successfully.



1.  An error has occurred.




********
EXAMPLES
********



1. To display the contents of the site table:
 
 
 .. code-block:: perl
 
   tabdump site
 
 


2. To display the contents of the nodelist table where the groups attribute is compute :
 
 
 .. code-block:: perl
 
   tabdump -w 'groups==compute' nodelist
 
 


3. To display the contents of the nodelist table where the groups attribute is comput% where % is a wildcard and can represent any string  and the status attribute is booted :
 
 
 .. code-block:: perl
 
   tabdump -w 'groups=~comput%' -w 'status==booted' nodelist
 
 


4. To display the records of the auditlog on date  2011-04-18 11:30:00 :
 
 
 .. code-block:: perl
 
   tabdump -w 'audittime==2011-04-18 11:30:00' auditlog
 
 


5. To display the records of the auditlog starting on 2011-04-18:
 
 
 .. code-block:: perl
 
   tabdump -w 'audittime>2011-04-18 11:30:00' auditlog
 
 


6. To display the 10 most recent entries in the auditlog:
 
 
 .. code-block:: perl
 
   tabdump -n 10 auditlog
 
 


7. To see what tables exist in the xCAT database:
 
 
 .. code-block:: perl
 
   tabdump
 
 


8. To back up all the xCAT database tables, instead of running \ **tabdump**\  multiple times, you can use the \ **dumpxCATdb**\  command as follows:
 
 
 .. code-block:: perl
 
   dumpxCATdb -p /tmp/xcatbak
 
 
 See the \ **dumpxCATdb**\  man page for details.
 


9. To display a summary description of each table:
 
 
 .. code-block:: perl
 
   tabdump -d
 
 


10. To display a description of each column in the nodehm table:
 
 
 .. code-block:: perl
 
   tabdump -d nodehm
 
 



*****
FILES
*****


/opt/xcat/sbin/tabdump


********
SEE ALSO
********


tabrestore(8)|tabrestore.8, tabedit(8)|tabedit.8, dumpxCATdb(1)|dumpxCATdb.1

