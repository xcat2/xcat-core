
##########
tabprune.8
##########

.. highlight:: perl


****
NAME
****


\ **tabprune**\  - Deletes records from the eventlog,auditlog,isnm_perf,isnm_perf_sum tables.


********
SYNOPSIS
********


\ **tabprune**\  [\ **eventlog | auditlog**\ ]  [\ **-V**\ ] [\ **-i**\  \ *recid*\  | \ **-n**\  \ *number of records*\  | \ **-p**\  \ *percentage*\  | \ **-d**\  \ *number of days*\  | \ **-a**\ ]

\ **tabprune**\  \ *tablename*\  \ **-a**\ 

\ **tabprune**\  [\ **-h | -**\ **-help**\ ] [\ **-v | -**\ **-version**\ ]


***********
DESCRIPTION
***********


The tabprune command is used to delete records from the auditlog, eventlog, isnm_perf, isnm_perf_sum tables. As an option, the table header and all the rows pruned from the specified table will be displayed in CSV (comma separated values) format. The all records options (-a) can be used on any xCAT table.


*******
OPTIONS
*******



\ **-h|-**\ **-help**\ 
 
 Display usage message.
 


\ **-V**\ 
 
 Verbose mode.  This will cause tabprune to display the records that are being deleted from the table, in case
 you want to redirect them to a file to archive them.
 


\ **-a**\ 
 
 Remove all records from the input table name.  This option can be used on any xCAT table.
 


\ **-i**\   \ *recid number*\ 
 
 Remove the records whose recid is less than the input recid number.
 


\ **-n**\  \ *number*\ 
 
 Remove the number of records input.
 


\ **-p**\  \ *percent*\ 
 
 Remove the number of records input.
 


\ **-d**\  \ *number of days*\ 
 
 Remove all records that occurred >= than number of days ago.
 



************
RETURN VALUE
************



0. The command completed successfully.



1. An error has occurred.




********
EXAMPLES
********



1. To remove all the records in the eventlog table:
 
 
 .. code-block:: perl
 
   tabprune eventlog -a
 
 


2. To remove all the records in the eventlog table saving the deleted records in eventlog.csv:
 
 
 .. code-block:: perl
 
   tabprune eventlog -V -a > eventlog.csv
 
 


3. To remove all the records before recid=200 in the auditlog table:
 
 
 .. code-block:: perl
 
   tabprune auditlog -i 200
 
 


4. To remove 400 records from the auditlog table and display the remove records:
 
 
 .. code-block:: perl
 
   tabprune auditlog -V -n 400
 
 


5. To remove 50% of the  eventlog table:
 
 
 .. code-block:: perl
 
   tabprune eventlog -p 50
 
 


6. To remove all records that occurred >= 5 days ago in the eventlog:
 
 
 .. code-block:: perl
 
   tabprune eventlog -d 5
 
 



*****
FILES
*****


/opt/xcat/sbin/tabprune


********
SEE ALSO
********


tabrestore(8)|tabrestore.8, tabedit(8)|tabedit.8,tabdump(8)|tabdump.8

