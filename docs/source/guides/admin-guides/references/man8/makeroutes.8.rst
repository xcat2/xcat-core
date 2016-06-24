
############
makeroutes.8
############

.. highlight:: perl


****
NAME
****


\ **makeroutes**\  - add or delete routes to/from the os route table on nodes.


********
SYNOPSIS
********


\ **makeroutes**\  [\ **-r | -**\ **-routename**\  \ *r1*\ [\ *,r2...*\ ]]

\ **makeroutes**\  [\ **-d | -**\ **-delete**\ ] [\ **-r | -**\ **-routenames**\  \ *r1*\ [\ *,r2...*\ ]]

\ **makeroutes**\  \ *noderange*\  [\ **-r | -**\ **-routename**\  \ *r1*\ [\ *,r2...*\ ]]

\ **makeroutes**\  \ *noderange*\  [\ **-d | -**\ **-delete**\ ] [\ **-r | -**\ **-routenames**\  \ *r1*\ [\ *,r2...*\ ]]

\ **makeroutes**\  [\ **-h | -**\ **-help | -v | -**\ **-version**\ ]


***********
DESCRIPTION
***********


The \ **makeroutes**\  command adds or deletes routes on the management node or any given nodes. The \ **noderange**\  specifies the nodes where the routes are to be added or removed. When the \ *noderange*\  is omitted, the action will be done on the management node. The \ **-r**\  option specifies the name of routes. The details of the routes are defined in the \ **routes**\  table which contians the route name, subnet, net mask and gateway. If -r option is omitted, the names of the routes found on \ **noderes.routenames**\  for the nodes or on \ **site.mnroutenames**\  for the management node will be used.

If you want the routes be automatically setup during node deployment, first put a list of route names to \ **noderes.routenames**\  and then add \ *setroute*\  script name to the \ **postscripts.postbootscripts**\  for the nodes.


**********
Parameters
**********


\ *noderange*\  specifies the nodes where the routes are to be added or removed. If omitted, the operation will be done on the management node.


*******
OPTIONS
*******



\ **-d|-**\ **-delete**\ 
 
 Specifies to delete the given routes. If not specified, the action is to add routes.
 


\ **-r|-**\ **-routename**\ 
 
 Specifies a list of comma separated route names defined in the \ **routes**\  table. If omitted, all routes defined in \ **noderes.routenames**\  for nodes or \ **site.mnroutenames**\  for the management node will be used.
 


\ **-h|-**\ **-help**\ 
 
 Display usage message.
 


\ **-v|-**\ **-version**\ 
 
 Command Version.
 



********
EXAMPLES
********



1. To add all routes from the \ **site.mnroutenames**\  to the os route table for the management node.
 
 
 .. code-block:: perl
 
   makeroutes
 
 


2. To add all the routes from \ **noderes.routenames**\  to the os route table for node1.
 
 
 .. code-block:: perl
 
   makeroutes node1
 
 


3. To add route rr1 and rr2 to the os route table for the management node.
 
 
 .. code-block:: perl
 
   makeroutes -r rr1,rr2
 
 


4. To delete route rr1 and rr2 from the os route table on node1 and node1.
 
 
 .. code-block:: perl
 
   makeroutes node1,node2 -d -r rr1,rr2
 
 



*****
FILES
*****


/opt/xcat/sbin/makeroutes


********
SEE ALSO
********


