
#######
pping.1
#######

.. highlight:: perl


********
SYNOPSIS
********


\ **pping**\  [\ **-i | -**\ **-interface**\  \ *interfaces*\ ] [\ **-f | -**\ **-use_fping**\ ] \ *noderange*\ 

\ **pping**\  [\ **-h | -**\ **-help**\ ]

\ **pping**\  {\ **-v | -**\ **-version**\ }


***********
DESCRIPTION
***********


\ **pping**\  is a utility used to ping a list of nodes in parallel.
\ **pping**\  will return an unsorted list of nodes with a ping or noping status.
\ **pping**\  front-ends nmap or fping if available.

This command does not support the xcatd client/server communication.  It must be run on the management node.


*******
OPTIONS
*******



\ **-i | -**\ **-interface**\  \ *interfaces*\ 
 
 A comma separated list of network interface names that should be pinged instead of the interface represented by the nodename/hostname.
 The following name resolution convention is assumed:  an interface is reachable by the hostname <nodename>-<interface>.  For example,
 the ib2 interface on node3 has a hostname of node3-ib2.
 
 If more than one interface is specified, each interface will be combined with the nodenames as described above and will be pinged in turn.
 


\ **-f | -**\ **-use_fping**\ 
 
 Use fping instead of nmap
 


\ **-h | -**\ **-help**\ 
 
 Show usage information.
 


\ **-v | -**\ **-version**\ 
 
 Display the installed version of xCAT.
 



********
EXAMPLES
********



1.
 
 
 .. code-block:: perl
 
   pping all
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   node1: ping
   node2: ping
   node3: noping
 
 


2.
 
 
 .. code-block:: perl
 
   pping all -i ib0,ib1
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   node1-ib0: ping
   node2-ib0: ping
   node3-ib0: noping
   node1-ib1: ping
   node2-ib1: ping
   node3-ib1: noping
 
 



********
SEE ALSO
********


psh(1)|psh.1, noderange(3)|noderange.3

