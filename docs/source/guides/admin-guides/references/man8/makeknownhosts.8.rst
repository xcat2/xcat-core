
################
makeknownhosts.8
################

.. highlight:: perl


****
NAME
****


\ **makeknownhosts**\  - Make a known_hosts file under $ROOTHOME/.ssh for input noderange.


********
SYNOPSIS
********


\ **makeknownhosts**\  \ *noderange*\  [\ **-r | -**\ **-remove**\ ] [\ **-V | -**\ **-verbose**\ ]

\ **makeknownhosts**\  [\ **-h | -**\ **-help**\ ]


***********
DESCRIPTION
***********


\ **makeknownhosts**\  Replaces or removes entries for the nodes in the known_hosts file in the $ROOTHOME/.ssh directory.
The known_hosts file entry is built from the shared ssh host key that xCAT distributes to the installed nodes.

HMCs, AMM, switches, etc., where xCAT does not distribute the shared ssh host key, should not be put in the noderange.

To build the known_hosts entry for a node, you are only required to have the node in the database, and name resolution working for the node. You do not have to be able to access the node.

Having this file with correct entries, will avoid the ssh warning when nodes are automatically added to the known_hosts file.
The file should be distributed using \ **xdcp**\  to all the nodes, if you want node to node communication not to display the warning.


*******
OPTIONS
*******



\ *noderange*\ 
 
 A set of comma delimited node names and/or group names.
 See the \ *noderange*\  man page for details on supported formats.
 


\ **-r|-**\ **-remove**\ 
 
 Only removes the entries for the nodes from the known_hosts file.
 


\ **-V|-**\ **-verbose**\ 
 
 Verbose mode.
 



********
EXAMPLES
********



1. To build the known_hosts entry for the nodes in the compute group
 
 
 .. code-block:: perl
 
   makeknownhosts compute
 
 


2. To build the known_hosts entry for the nodes in the lpars and service groups
 
 
 .. code-block:: perl
 
   makeknownhosts lpars,service
 
 


3. To remove the known_hosts entry for node02
 
 
 .. code-block:: perl
 
   makeknownhosts node02 -r
 
 


