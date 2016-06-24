
#########
nodeadd.8
#########

.. highlight:: perl


****
NAME
****


\ **nodeadd**\  - Adds nodes to the xCAT cluster database.


********
SYNOPSIS
********


\ **nodeadd**\  \ *noderange*\  \ **groups**\ =\ *groupnames*\  [\ *table.column=value*\ ] [\ *...*\ ]

\ **nodeadd**\  [\ **-v**\  | \ **-**\ **-version**\ ]

\ **nodeadd**\  [\ **-?**\  | \ **-h**\  | \ **-**\ **-help**\ ]


***********
DESCRIPTION
***********


The nodeadd command adds the nodes specified in noderange to the xCAT database.  It also stores
the any additional attributes specified for these nodes.  At least one groupname must be supplied.
You should also consider specifying attributes in at least the following tables:  \ **nodehm**\ , \ **noderes**\ ,
\ **nodetype**\ .  See the man page for each of these for details.  Also see the \ **xcatdb**\  man page for an
overview of each table.

The nodeadd command also supports some short cut names as aliases to common attributes.  See the
\ **nodels**\  man page for details.


*******
OPTIONS
*******



\ **-v|-**\ **-version**\ 
 
 Command Version.
 


\ **-?|-h|-**\ **-help**\ 
 
 Display usage message.
 



************
RETURN VALUE
************



0.  The command completed successfully.



1.  An error has occurred.




********
EXAMPLES
********



1. To add nodes in noderange  node1-node4 with group all:
 
 
 .. code-block:: perl
 
   nodeadd node1-node4 groups=all
 
 


2. To add nodes in noderange  node1-node4 to the nodetype table with os=rhel5:
 
 
 .. code-block:: perl
 
   nodeadd node1-node4 groups=all,rhel5 nodetype.os=rhel5
 
 



*****
FILES
*****


/opt/xcat/bin/nodeadd


********
SEE ALSO
********


nodels(1)|nodels.1, nodech(1)|nodech.1, noderange(3)|noderange.3

