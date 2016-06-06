
########
nodech.1
########

.. highlight:: perl


****
NAME
****


\ **nodech**\  - Changes nodes' attributes in the xCAT cluster database.


********
SYNOPSIS
********


\ **nodech**\  \ *noderange*\  \ *table.column=value*\  [\ *...*\ ]

\ **nodech**\  {\ **-d**\  | \ **-**\ **-delete**\ } \ *noderange*\  \ *table*\  [\ *...*\ ]

\ **nodech**\  {\ **-v**\  | \ **-**\ **-version**\ }

\ **nodech**\  [\ **-?**\  | \ **-h**\  | \ **-**\ **-help**\ ]


***********
DESCRIPTION
***********


The nodech command changes the specified attributes for the given nodes.  Normally, the given
value will completely replace the current attribute value.  But if ",=" is used instead of "=",
the specified value will be prepended to the attribute's comma separated list, if it is not already
there.  If "^=" is used, the specified value will be removed from the attribute's comma separated list,
if it is there.  You can also use "^=" and ",=" in the same command to essentially replace one item
in the list with another.  (See the Examples section.)

Additionally, as in nodels, boolean expressions can be used to further limit the scope of nodech from 
the given noderange.  The operators supported are the same as nodels (=~, !~, ==, and !=).

With these operators in mind, the unambiguous assignment operator is '=@'.  If you need, for example, to set
the nodelist.comments to =foo, you would have to do \ *nodech n1 nodelist.comments=@=foo*\ .

See the \ **xcatdb**\  man page for an overview of each table.

The nodech command also supports some short cut names as aliases to common attributes.  See the
\ **nodels**\  man page for details.


*******
OPTIONS
*******



\ **-d|-**\ **-delete**\ 
 
 Delete the nodes' row in the specified tables.
 


\ **-v|-**\ **-version**\ 
 
 Command Version.
 


\ **-?|-h|-**\ **-help**\ 
 
 Display usage message.
 



************
RETURN VALUE
************



0
 
 The command completed successfully.
 


1
 
 An error has occurred.
 



********
EXAMPLES
********



\*
 
 To update nodes in noderange  node1-node4 to be in only group all:
 
 \ **nodech**\  \ *node1-node4 groups=all*\ 
 


\*
 
 To put all nodes with nodepos.rack value of 2 into a group called rack2:
 
 \ **nodech**\  \ *all*\  nodepos.rack==2 groups,=rack2
 


\*
 
 To add nodes in noderange  node1-node4 to the nodetype table with os=rhel5:
 
 \ **nodech**\  \ *node1-node4 groups=all,rhel5 nodetype.os=rhel5*\ 
 


\*
 
 To add node1-node4 to group1 in addition to the groups they are already in:
 
 \ **nodech**\  \ *node1-node4 groups,=group1*\ 
 


\*
 
 To put node1-node4 in group2, instead of group1:
 
 \ **nodech**\  \ *node1-node4 groups^=group1 groups,=group2*\ 
 



*****
FILES
*****


/opt/xcat/bin/nodech


********
SEE ALSO
********


nodels(1)|nodels.1, nodeadd(8)|nodeadd.8, noderange(3)|noderange.3

