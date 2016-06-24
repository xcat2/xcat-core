
###########
swapnodes.1
###########

.. highlight:: perl


****
NAME
****


\ **swapnodes**\  - swap the location info in the db (all the attributes in the ppc table and the nodepos table) between 2 nodes. If swapping within a cec, it will assign the IO adapters that were assigned to the defective node to the available node.


********
SYNOPSIS
********


\ **swapnodes**\  [\ **-h**\ | \ **-**\ **-help**\ ]

\ **swapnodes**\  \ **-c**\  \ *current_node*\  \ **-f**\  \ *fip_node*\  [\ **-o**\ ]


***********
DESCRIPTION
***********


This command is only for Power 775 using Direct FSP Management, and used in Power 775 Availability Plus.

The \ **swapnodes**\  command will keep the \ **current_node**\  name in the xCAT table, and use the \ *fip_node*\ 's hardware resource. Besides that, the IO adapters will be assigned to the new hardware resource if they are in the same CEC. So the swapnodes command will do 2 things:

1. Swap the location info in the db between 2 nodes:

All the ppc table attributes (including hcp, id, parent, supernode and so on).
All the nodepos table attributes(including rack, u, chassis, slot, room and so on).

2. Assign the I/O adapters from the defective node(the original current_node) to the available node(the original fip_node) if the nodes are in the same cec.

The \ **swapnodes**\  command shouldn't make the decision of which 2 nodes are swapped. It will just received the 2 node names as cmd line parameters.

After running \ **swapnodes**\  command, the order of the I/O devices may be changed after IO re-assignment, so the administrator needs to run \ **rbootseq**\  to set the boot string for the current_node. And then boot the node with the same image and same postscripts because they have the same attributes.

Without \ **-o**\  option, it's used to swap the location info in the db between 2 nodes. With \ **-o**\  option, it's used to move the \ *current_node*\  definition to \ *fip_node*\  (the 2nd octant), not move the \ *fip_node*\  definition to the 1st octant. If the two nodes are in a cec, it will assign the IO adapters that were assigned to the defective node to the available node. Originally, the \ *current_node*\  is a defective non-compute node, and \ *fip_node*\  is a avaible compute node. After the swapping, the \ *current_node*\  will be a available node.


*******
OPTIONS
*******



\ **-h|-**\ **-help**\ 
 
 Display usage message.
 


\ **-c**\ 
 
 \ *current_node*\  -- the defective non-compute node.
 


\ **-f**\ 
 
 \ *fip_node*\  -- a compute node which will be swapped as the non-compute node.
 


\ **-o**\ 
 
 one way. Only move the \ *current_node*\  definition to the \ *fip_node*\ 's hardware resource, and not move the fip_node definition to the \ *current_node*\ . And then the \ *current_node*\  will use the \ *fip_node*\ 's hardware resource, and the \ *fip_node*\  definition is not changed. if the two nodes are in the same CEC, the I/O adapter from the original \ *current_node*\  will be assigned to the \ *fip_node*\ .
 



************
RETURN VALUE
************


0 The command completed successfully.

1 An error has occurred.


********
EXAMPLES
********



1. To swap the service node attributes and IO assignments between sn1 and compute2 which are in the same cec, all the attributes in the ppc table and nodepos talbe of the two node will be swapped, and the the I/O adapters from the defective node (the original sn1) will be assigned to the available node (the original compute2). After the swapping, the sn1 will use the compute2's hardware resource and the I/O adapters from the original sn1.
 
 
 .. code-block:: perl
 
   swapnodes -c sn1 -f compute2
 
 


2. To swap the service node attributes and IO assignments between sn1 and compute2 which are NOT in the same cec, all the attributes in the ppc table and nodepos talbe of the two node will be swapped. After the swapping, the sn1 will use the compute2's hardware resource.
 
 
 .. code-block:: perl
 
   swapnodes -c sn1 -f compute2
 
 


3. Only to move the service node (sn1) definition to the compute node (compute2)'s hardware resource, and not move the compute2 definition to the sn1. After the swapping, the sn1 will use the compute2's hardware resource, and the compute2 definition is not changed.
 
 
 .. code-block:: perl
 
   swapnodes -c sn1 -f compute2 -o
 
 



*****
FILES
*****


$XCATROOT/bin/swapnodes

(The XCATROOT environment variable is set when xCAT is installed. The
default value is "/opt/xcat".)


*****
NOTES
*****


This command is part of the xCAT software product.


********
SEE ALSO
********


lsvm(1)|lsvm.1, mkvm(1)|mkvm.1, chvm(1)|chvm.1

