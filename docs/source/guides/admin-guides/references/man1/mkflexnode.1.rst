
############
mkflexnode.1
############

.. highlight:: perl


****
NAME
****


\ **mkflexnode**\  - Create a flexible node.


********
SYNOPSIS
********


\ **mkflexnode**\  [\ **-h**\  | \ **-**\ **-help**\ ]

\ **mkflexnode**\  [\ **-v**\  | \ **-**\ **-version**\ ]

\ **mkflexnode**\  \ *noderange*\ 


***********
DESCRIPTION
***********


A flexible node is a \ **Partition**\  in a complex. Creating a flexible node is to create a partition which including all the slots defined in the xCAT blade node.

Before creating a flexible node, a general xCAT blade node should be defined. The \ *id*\  attribute of this node should be a node range like 'a-b', it means the blades installed in slots 'a-b' need to be assigned to the partition. 'a' is the start slot, 'b' is the end slot. If this partition only have one slot, the slot range can be 'a'.

The action of creating flexible node will impact the hardware status. Before creating it, the blades in the slot range should be in \ **power off**\  state.

After the creating, use the \ **lsflexnode**\  to check the status of the node.

The \ *noderange*\  only can be a blade node.


*******
OPTIONS
*******



\ **-h | -**\ **-help**\ 
 
 Display the usage message.
 


\ **-v | -**\ **-version**\ 
 
 Display the version information.
 



********
EXAMPLES
********



1. Create a flexible node base on the xCAT node blade1.
 
 The blade1 should belong to a complex, the \ *id*\  attribute should be set correctly and all the slots should be in \ **power off**\  state.
 
 
 .. code-block:: perl
 
   mkflexnode blade1
 
 



*****
FILES
*****


/opt/xcat/bin/mkflexnode


********
SEE ALSO
********


lsflexnode(1)|lsflexnode.1, rmflexnode(1)|rmflexnode.1

