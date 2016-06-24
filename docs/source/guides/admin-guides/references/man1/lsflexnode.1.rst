
############
lsflexnode.1
############

.. highlight:: perl


****
NAME
****


\ **lsflexnode**\  - Display the information of flexible node


********
SYNOPSIS
********


\ **lsflexnode**\  [\ **-h**\  | \ **-**\ **-help**\ ]

\ **lsflexnode**\  [\ **-v**\  | \ **-**\ **-version**\ ]

\ **lsflexnode**\  \ *noderange*\ 


***********
DESCRIPTION
***********


IBM BladeCenter HX5 offers flexibility ideal that the blades can be combined together for scalability.

There are several concepts to support the HX5 multiple blades combination:


\ **Complex**\ : Multiple blades which combined by a scalability card is a complex.

\ **Parition**\ : A logic concept which containing part of the \ **Blade slot node**\  in a complex. Each partition can map to a system to install Operating System. Each partition could have 1HX5, 1HX5+1MD or 2HX5+2MD. (MD is the Memory Drawer)

\ **Blade slot node**\ : The physical blade which installed in the slot of a chassis. It can be a HX5 or MD.

A \ **Complex**\  will be created automatically when a multiple blades combination is installed. In this \ **Complex**\ , every blade belongs to it is working as a \ **Blade slot node**\ .

A \ **Partition**\  can be created base on the \ **Complex**\ , each \ **Partition**\  can have one or multiple \ **Blade slot node**\ .

The \ *noderange*\  in the \ **SYNOPSIS**\  can be a AMM node or a blade node.


*******
OPTIONS
*******



\ **-h | -**\ **-help**\ 
 
 Display the usage message.
 


\ **-v | -**\ **-version**\ 
 
 Display the version information.
 



**********
ATTRIBUTES
**********


The meaning of attributes which displayed by the \ **lsflexnode**\ . The word 'node' in this section means \ **Blade slot node**\ .


\ **Complex**\ 
 
 The unique numeric identifier for a complex installed in the chassis.
 


\ **Partition number**\ 
 
 The number of partitions currently defined for this complex.
 


\ **Complex node number**\ 
 
 The number of nodes existing in this complex, regardless of their assignment to any given partition.
 


\ **Partition**\ 
 
 The unique numeric identifier for a partition defined within a complex installed in the chassis.
 


\ **Partition Mode**\ 
 
 The currently configured mode of this partition. It can be 'partition' or 'standalone'.
 


\ **Partition node number**\ 
 
 The number of nodes currently defined for this partition.
 


\ **Partition status**\ 
 
 The current power status of this partition when the partition has a valid partition configuration. It can be 'poweredoff', 'poweredon', 'resetting' or 'invalid'.
 


\ **Node**\ 
 
 The unique numeric identifier for this node, unique within the partition. If this node does not belong to a partition, the slot number will be displayed.
 


\ **Node state**\ 
 
 The physical power state of this node. It can be 'poweredoff', 'poweredon' or 'resetting'.
 


\ **Node slot**\ 
 
 The base slot number where the node exists in the chassis.
 


\ **Node resource**\ 
 
 A string providing a summary overview of the resources provided by this node. It includes the CPU number, CPU frequency and Memory size.
 


\ **Node type**\ 
 
 The general categorization of the node. It can be 'processor', 'memory' or 'io'.
 


\ **Node role**\ 
 
 Indicates if the node is assigned to a partition, and if so, provides an indication of whether the node is the primary node of the partition or not.
 


\ **Flexnode state**\ 
 
 The state of a flexible node. It is the state of the partition which this node belongs to. If this node does NOT belong to a partition, the value should be 'invalid'.
 
 It can be 'poweredoff', 'poweredon', 'resetting' or 'invalid'.
 


\ **Complex id**\ 
 
 The identifier of the complex this node belongs to.
 


\ **Partition id**\ 
 
 The identifier of the partition this node belongs to.
 



********
EXAMPLES
********



1 Display all the \ **Complex**\ , \ **Partition**\  and \ **Blade slot node**\  which managed by a AMM.
 
 
 .. code-block:: perl
 
   lsflexnode amm1
 
 
 The output:
 
 
 .. code-block:: perl
 
      amm1: Complex - 24068
      amm1: ..Partition number - 1
      amm1: ..Complex node number - 2
      amm1: ..Partition = 1
      amm1: ....Partition Mode - partition
      amm1: ....Partition node number - 1
      amm1: ....Partition status - poweredoff
      amm1: ....Node - 0 (logic id)
      amm1: ......Node state - poweredoff
      amm1: ......Node slot - 14
      amm1: ......Node type - processor
      amm1: ......Node resource - 2 (1866 MHz) / 8 (2 GB)
      amm1: ......Node role - secondary
      amm1: ..Partition = unassigned
      amm1: ....Node - 13 (logic id)
      amm1: ......Node state - poweredoff
      amm1: ......Node slot - 13
      amm1: ......Node type - processor
      amm1: ......Node resource - 2 (1866 MHz) / 8 (2 GB)
      amm1: ......Node role - unassigned
 
 


2 Display a flexible node.
 
 
 .. code-block:: perl
 
   lsflexnode blade1
 
 
 The output:
 
 
 .. code-block:: perl
 
      blade1: Flexnode state - poweredoff
      blade1: Complex id - 24068
      blade1: Partition id - 1
      blade1: Slot14: Node state - poweredoff
      blade1: Slot14: Node slot - 14
      blade1: Slot14: Node type - processor
      blade1: Slot14: Node resource - 2 (1866 MHz) / 8 (2 GB)
      blade1: Slot14: Node role - secondary
 
 



*****
FILES
*****


/opt/xcat/bin/lsflexnode


********
SEE ALSO
********


mkflexnode(1)|mkflexnode.1, rmflexnode(1)|rmflexnode.1

