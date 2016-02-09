
#########
tabedit.8
#########

.. highlight:: perl


****
NAME
****


\ **tabedit**\  - view an xCAT database table in an editor and make changes.


********
SYNOPSIS
********


\ **tabedit**\  \ *table*\ 

\ **tabedit**\  [\ **-?**\  | \ **-h**\  | \ **-**\ **-help**\ ]


***********
DESCRIPTION
***********


The tabedit command opens the specified table in the user's editor, allows them to edit any
text, and then writes changes back to the database table.  The table is flattened into a CSV
(comma separated values) format file before giving it to the editor.  After the editor is
exited, the CSV file will be translated back into the database format.
You may not tabedit the auditlog or eventlog because indexes will be regenerated.
Use tabprune command to edit auditlog and eventlog.


*******
OPTIONS
*******



\ **-?|-h|-**\ **-help**\ 
 
 Display usage message.
 



*********************
ENVIRONMENT VARIABLES
*********************



TABEDITOR
 
 The editor that should be used to edit the table, for example:  vi, vim, emacs, oocalc, pico, gnumeric, nano.
 If \ **TABEDITOR**\  is not set, the value from \ **EDITOR**\  will be used.  If \ **EDITOR**\  is not set, it will
 default to vi.
 



************
RETURN VALUE
************



0.  The command completed successfully.



1.  An error has occurred.




********
EXAMPLES
********



1. To edit the site table:
 
 
 .. code-block:: perl
 
   tabedit site
 
 



*****
FILES
*****


/opt/xcat/sbin/tabedit


********
SEE ALSO
********


tabrestore(8)|tabrestore.8, tabdump(8)|tabdump.8, chtab(8)|chtab.8

