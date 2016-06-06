
########
nodels.1
########

.. highlight:: perl


****
NAME
****


\ **nodels**\  - lists the nodes, and their attributes, from the xCAT database.


********
SYNOPSIS
********


\ **nodels**\  [\ *noderange*\ ] [\ **-b**\  | \ **-**\ **-blame**\ ] [\ **-H**\  | \ **-**\ **-with-fieldname**\ ] [\ **-S**\ ] [\ *table.column*\  | \ *shortname*\ ] [\ *...*\ ]

\ **nodels**\  [\ *noderange*\ ] [\ **-H**\  | \ **-**\ **-with-fieldname**\ ] [\ *table*\ ]

\ **nodels**\  [\ **-?**\  | \ **-h**\  | \ **-**\ **-help**\  | \ **-v**\  | \ **-**\ **-version**\ ]


***********
DESCRIPTION
***********


The \ **nodels**\  command lists the nodes specified in the node range. If no noderange is provided, then all nodes are listed.

Additional attributes of the nodes will also be displayed if the table names and attribute names
are specified after the noderange in the form:  \ *table.column*\  .  A few shortcut names can
also be used as aliases to common attributes:


\ **groups**\ 
 
 nodelist.groups
 


\ **tags**\ 
 
 nodelist.groups
 


\ **mgt**\ 
 
 nodehm.mgt
 


nodels can also select based on table value criteria. The following operators are available:


\ **==**\ 
 
 Select nodes where the table.column value is exactly a certain value.
 


\ **!=**\ 
 
 Select nodes where the table.column value is not a given specific value.
 


\ **=~**\ 
 
 Select nodes where the table.column value matches a given regular expression.
 


\ **!~**\ 
 
 Select nodes where the table.column value does not match a given regular expression.
 


The \ **nodels**\  command with a specific node and one or more table.attribute parameters is a good substitute
for grep'ing through the tab files, as was typically done in xCAT 1.x.  This is because nodels will translate
any regular expression rows in the tables into their meaning for the specified node.  The tab\* commands
will not do this, instead they will just display the regular expression row verbatim.


*******
OPTIONS
*******



\ **-v|-**\ **-version**\ 
 
 Command Version.
 


\ **-H|-**\ **-with-fieldname**\ 
 
 Force display of table name and column name context for each result
 


\ **-b|-**\ **-blame**\ 
 
 For values inherited from groups, display which groups provided the inheritence
 


\ **-S**\ 
 
 List all the hidden nodes (FSP/BPA nodes) with other ones.
 


\ **-?|-h|-**\ **-help**\ 
 
 Display usage message.
 



************
RETURN VALUE
************


0  The command completed successfully.

1  An error has occurred.


********
EXAMPLES
********



1.
 
 To list all defined nodes, enter:
 
 
 .. code-block:: perl
 
   nodels
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
     node1
     node2
     node3
 
 


2.
 
 To list all defined attributes in a table for a node or noderange, enter:
 
 
 .. code-block:: perl
 
   nodels rra001a noderes
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
     rra001a: noderes.primarynic: eth0
     rra001a: noderes.xcatmaster: rra000
     rra001a: noderes.installnic: eth0
     rra001a: noderes.netboot: pxe
     rra001a: noderes.servicenode: rra000
     rra001a: noderes.node: rra001a
 
 


3.
 
 To list nodes in node group ppc, enter:
 
 
 .. code-block:: perl
 
   nodels ppc
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
     ppcnode1
     ppcnode2
     ppcnode3
 
 


4.
 
 To list the groups each node is part of:
 
 
 .. code-block:: perl
 
   nodels all groups
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
     node1: groups: all
     node2: groups: all,storage
     node3: groups: all,blade
 
 


5.
 
 To list the groups each node is part of:
 
 
 .. code-block:: perl
 
   nodels all nodehm.power
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
     node1: nodehm.power: blade
     node2: nodehm.power: ipmi
     node3: nodehm.power: ipmi
 
 


6.
 
 To list the out-of-band mgt method for blade1:
 
 
 .. code-block:: perl
 
   nodels blade1 nodehm.mgt
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
     blade1: blade
 
 


7.
 
 Listing blades managed through an AMM named 'amm1'
 
 
 .. code-block:: perl
 
   nodels all mp.mpa==amm1
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
     blade1
     blade10
     blade11
     blade12
     blade13
     blade2
     blade3
     blade4
     blade5
     blade6
     blade7
     blade8
     blade9
 
 


8.
 
 Listing the switch.switch value for nodes in the second rack:
 
 
 .. code-block:: perl
 
   nodels all nodepos.rack==2 switch.switch
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
     n41: switch.switch: switch2
     n42: switch.switch: switch2
     n43: switch.switch: switch2
     n44: switch.switch: switch2
     n45: switch.switch: switch2
     n46: switch.switch: switch2
     n47: switch.switch: switch2
     n55: switch.switch: switch2
     n56: switch.switch: switch2
     n57: switch.switch: switch2
     n58: switch.switch: switch2
     n59: switch.switch: switch2
     n60: switch.switch: switch2
 
 


9.
 
 Listing the blade slot number for anything managed through a device with a name beginning with amm:
 
 
 .. code-block:: perl
 
   nodels all mp.mpa=~/^amm.*/ mp.id
 
 
 Output looks like:
 
 
 .. code-block:: perl
 
     blade1: mp.id: 1
     blade10: mp.id: 10
     blade11: mp.id: 11
     blade12: mp.id: 12
     blade13: mp.id: 13
     blade2: mp.id: 2
     blade3: mp.id: 3
     blade4: mp.id: 4
     blade5: mp.id: 5
     blade6: mp.id: 6
     blade7: mp.id: 7
     blade8: mp.id: 8
     blade9: mp.id: 9
 
 


10.
 
 To list the hidden nodes that can't be seen with other flags.
 The hidden nodes are FSP/BPAs.
 
 
 .. code-block:: perl
 
   lsdef -S
 
 



*****
FILES
*****


/opt/xcat/bin/nodels


********
SEE ALSO
********


noderange(3)|noderange.3, tabdump(8)|tabdump.8, lsdef(1)|lsdef.1

