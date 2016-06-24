
#################
nodediscoverdef.1
#################

.. highlight:: perl


****
NAME
****


\ **nodediscoverdef**\  - Define the undefined discovery request to a predefined xCAT node, 
or clean up the discovery entries from the discoverydata table 
(which can be displayed by nodediscoverls command)


********
SYNOPSIS
********


\ **nodediscoverdef**\  \ **-u**\  \ *uuid*\  \ **-n**\  \ *node*\ 

\ **nodediscoverdef**\  \ **-r**\  \ **-u**\  \ *uuid*\ 

\ **nodediscoverdef**\  \ **-r**\  \ **-t**\  {\ **seq | profile | switch | blade | manual | undef | all**\ }

\ **nodediscoverdef**\  [\ **-h | -**\ **-help | -v | -**\ **-version**\ ]


***********
DESCRIPTION
***********


The \ **nodediscoverdef**\  command defines the discovery entry from the discoverydata table to a predefined
xCAT node. The discovery entry can be displayed by \ **nodediscoverls**\  command.

The options \ **-u**\  and \ **-n**\  have to be used together to define a discovery request to a node.

The \ **nodediscoverdef**\  command also can be used to clean up the discovery entries from the 
discoverydata table.

The option \ **-r**\  is used to remove discovery entries. If working with \ **-u**\ , the specific entry
which uuid specified by \ **-u**\  will be removed.

You also can use the \ **-r**\  \ **-t**\  option to limit that only remove the nodes that were discovered in a
particular method of discovery.


*******
OPTIONS
*******



\ **-t seq|profile|switch|blade|manual|undef|all**\ 
 
 Specify the nodes that have been discovered by the specified discovery method:
 
 
 \* \ **seq**\  - Sequential discovery (started via nodediscoverstart noderange=<noderange> ...).
 
 
 
 \* \ **profile**\  - Profile discovery (started via nodediscoverstart networkprofile=<network-profile> ...).
 
 
 
 \* \ **switch**\  - Switch-based discovery (used when the switch and switches tables are filled in).
 
 
 
 \* \ **blade**\  - Blade discovery (used for IBM Flex blades).
 
 
 
 \* \ **manual**\  - Manually discovery (used when defining node by nodediscoverdef command).
 
 
 
 \* \ **undef**\  - Display the nodes that were in the discovery pool, but for which xCAT has not yet received a discovery request.
 
 
 
 \* \ **all**\  - All discovered nodes.
 
 
 


\ **-n**\  \ *node*\ 
 
 The xCAT node that the discovery entry will be defined to.
 


\ **-r**\ 
 
 Remove the discovery entries from discoverydata table.
 


\ **-u**\  \ *uuid*\ 
 
 The uuid of the discovered entry.
 


\ **-h|-**\ **-help**\ 
 
 Display usage message.
 


\ **-v|-**\ **-version**\ 
 
 Command version.
 



************
RETURN VALUE
************


0  The command completed successfully.

1  An error has occurred.


********
EXAMPLES
********



1. Define the discovery entry which uuid is 51E5F2D7-0D59-11E2-A7BC-3440B5BEDBB4 to node node1
 
 
 .. code-block:: perl
 
   nodediscoverdef -u 51E5F2D7-0D59-11E2-A7BC-3440B5BEDBB4 -n node1
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   Defined [51E5F2D7-0D59-11E2-A7BC-3440B5BEDBB4] to node node1.
 
 


2. Remove the discovery entry which uuid is 51E5F2D7-0D59-11E2-A7BC-3440B5BEDBB4 from the discoverydata table
 
 
 .. code-block:: perl
 
   nodediscoverdef -r -u 51E5F2D7-0D59-11E2-A7BC-3440B5BEDBB4
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   Removing discovery entries finished.
 
 


3. Remove the discovery entries which discover type is \ **seq**\  from the discoverydata table
 
 
 .. code-block:: perl
 
   nodediscoverdef -r -t seq
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   Removing discovery entries finished.
 
 



********
SEE ALSO
********


nodediscoverstart(1)|nodediscoverstart.1, nodediscoverstatus(1)|nodediscoverstatus.1, nodediscoverstop(1)|nodediscoverstop.1, nodediscoverls(1)|nodediscoverls.1

