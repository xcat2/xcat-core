
########
ppping.1
########

.. highlight:: perl


********
SYNOPSIS
********


\ **ppping**\  [\ **-i | -**\ **-interface**\  \ *interfaces*\ ] [\ **-d | -**\ **-debug**\ ] [\ **-V | -**\ **-verbose**\ ] [\ **-q | -**\ **-quiet**\ ] [\ **-s | -**\ **-serial**\ ] \ *noderange*\ 

\ **ppping**\  [\ **-h | -**\ **-help**\ ]

\ **pping**\  {\ **-v | -**\ **-version**\ }


***********
DESCRIPTION
***********


\ **ppping**\  is a utility used to test the connectivity between nodes in the noderange using ping.
By default, \ **ppping**\  will return an unsorted list of the node pairs that are not able to ping each other, or a message that all nodes are pingable.
More or less output can be controlled by the -V and -q options.
\ **ppping**\  front-ends \ **pping**\  and \ **xdsh**\ .


*******
OPTIONS
*******



\ **-s**\ 
 
 Ping serially instead of in parallel.
 


\ **-i | -**\ **-interface**\  \ *interfaces*\ 
 
 A comma separated list of network interface names that should be pinged instead of the interface represented by the nodename/hostname.
 The following name resolution convention is assumed:  an interface is reachable by the hostname <nodename>-<interface>.  For example,
 the ib2 interface on node3 has a hostname of node3-ib2.
 
 If more than one interface is specified, each interface will be combined with the nodenames as described above and will be pinged in turn.
 


\ **-V | -**\ **-verbose**\ 
 
 Display verbose output.  The result of every ping attempt from every node will be displayed.  Without this option, just a summary
 of the successful pings are displayed, along with all of the unsuccessful pings.
 


\ **-q | -**\ **-quiet**\ 
 
 Display minimum output:  just the unsuccessful pings.  This option has the effect that if all pings are successful, nothing is displayed.
 But it also has the performance benefit that each node does not have to send successful ping info back to the management node.
 


\ **-d | -**\ **-debug**\ 
 
 Print debug information.
 


\ **-h | -**\ **-help**\ 
 
 Show usage information.
 


\ **-v | -**\ **-version**\ 
 
 Display the installed version of xCAT.
 



********
EXAMPLES
********



1.
 
 
 .. code-block:: perl
 
   ppping all -q
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   blade7: node2: noping
   blade8: node2: noping
   blade9: node2: noping
   devmaster: node2: noping
   node2: noping
 
 


2.
 
 
 .. code-block:: perl
 
   ppping node1,node2 -i ib0,ib1,ib2,ib3
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   node1: pinged all nodes successfully on interface ib0
   node1: pinged all nodes successfully on interface ib1
   node1: pinged all nodes successfully on interface ib2
   node1: pinged all nodes successfully on interface ib3
   node2: pinged all nodes successfully on interface ib0
   node2: pinged all nodes successfully on interface ib1
   node2: pinged all nodes successfully on interface ib2
   node2: pinged all nodes successfully on interface ib3
 
 



********
SEE ALSO
********


psh(1)|psh.1, pping(1)|pping.1

