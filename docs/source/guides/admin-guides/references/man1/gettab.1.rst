
########
gettab.1
########

.. highlight:: perl


****
NAME
****


\ **gettab**\  - select table rows, based on attribute criteria, and display specific attributes.


********
SYNOPSIS
********


\ **gettab**\  [\ **-H**\  | \ **-**\ **-with-fieldname**\ ] \ *key=value,...  table.attribute ...*\ 

\ **gettab**\  [\ **-?**\  | \ **-h**\  | \ **-**\ **-help**\ ]


***********
DESCRIPTION
***********


The \ **gettab**\  command uses the specified key values to select a row in each of the tables requested.
For each selected row, the specified attributes are displayed.  The \ **gettab**\  command can be used instead
of \ **nodels**\  for tables that are not keyed by nodename (e.g. the \ **site**\  table), or to select rows based
on an attribute value other than nodename.


*******
OPTIONS
*******



\ **-H|-**\ **-with-fieldname**\ 
 
 Always display table.attribute name next to result.  By default, this is done only if more than
 one table.attribute is requested.
 


\ **-?|-h|-**\ **-help**\ 
 
 Display usage message.
 



************
RETURN VALUE
************



0 The command completed successfully.



1 An error has occurred.




********
EXAMPLES
********



1. To display setting for \ **master**\  (management node) in the site table:
 
 
 .. code-block:: perl
 
   gettab -H key=master site.value
 
 
 The output would be similar to:
 
 
 .. code-block:: perl
 
   site.value: mgmtnode.cluster.com
 
 


2. To display the first node or group name that has \ **mgt**\  set to \ **blade**\  in the nodehm table:
 
 
 .. code-block:: perl
 
   gettab mgt=blade nodehm.node
 
 
 The output would be similar to:
 
 
 .. code-block:: perl
 
   blades
 
 



*****
FILES
*****


/opt/xcat/bin/gettab


********
SEE ALSO
********


nodels(1)|nodels.1, chtab(8)|chtab.8, tabdump(8)|tabdump.8

