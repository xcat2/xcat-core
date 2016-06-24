
############
rmflexnode.1
############

.. highlight:: perl


****
NAME
****


\ **rmflexnode**\  - Delete a flexible node.


********
SYNOPSIS
********


\ **rmflexnode**\  [\ **-h**\  | \ **-**\ **-help**\ ]

\ **rmflexnode**\  [\ **-v**\  | \ **-**\ **-version**\ ]

\ **rmflexnode**\  \ *noderange*\ 


***********
DESCRIPTION
***********


Delete a flexible node which created by the \ **mkflexnode**\  command.

The \ **rmflexnode**\  command will delete the \ **Partition**\  which the slots in \ *id*\  attribute assigned to.

The action of deleting flexible node will impact the hardware status. Before deleting it, the blades in the slot range should be in \ **power off**\  state.

After the deleting, use the \ **lsflexnode**\  to check the status of the node.

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



1 Delete a flexible node base on the xCAT node blade1.
 
 The blade1 should belong to a complex, the \ *id*\  attribute should be set correctly and all the slots should be in \ **power off**\  state.
 
 
 .. code-block:: perl
 
   rmflexnode blade1
 
 



*****
FILES
*****


/opt/xcat/bin/rmflexnode


********
SEE ALSO
********


lsflexnode(1)|lsflexnode.1, mkflexnode(1)|mkflexnode.1

