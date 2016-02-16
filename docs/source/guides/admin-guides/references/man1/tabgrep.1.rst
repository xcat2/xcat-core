
#########
tabgrep.1
#########

.. highlight:: perl


****
NAME
****


\ **tabgrep**\  - list table names in which an entry for the given node appears.


********
SYNOPSIS
********


\ **tabgrep**\  \ *nodename*\ 

\ **tabgrep**\  [\ **-?**\  | \ **-h**\  | \ **-**\ **-help**\ ]


***********
DESCRIPTION
***********


The tabgrep command displays the tables that contain a row for the specified node.  Note that the
row can either have that nodename as the key or it could have a group that contains the node as
the key.


*******
OPTIONS
*******



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



1.
 
 To display the tables that contain blade1:
 
 
 .. code-block:: perl
 
   tabgrep blade1
 
 
 The output would be similar to:
 
 
 .. code-block:: perl
 
       nodelist
       nodehm
       mp
       chain
       hosts
       mac
       noderes
       nodetype
 
 



*****
FILES
*****


/opt/xcat/bin/tabgrep


********
SEE ALSO
********


nodels(1)|nodels.1, tabdump(8)|tabdump.8

