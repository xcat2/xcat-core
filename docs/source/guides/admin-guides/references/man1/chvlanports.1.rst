
#############
chvlanports.1
#############

.. highlight:: perl


****
NAME
****


\ **chvlanports**\  - It adds or removes nodes' switch interfaces for the vlan.


********
SYNOPSIS
********


\ **chvlanports**\  \ *vlanid*\  \ **-n | -**\ **-nodes**\  \ *noderange*\  \ **-i | -**\ **-interface**\  \ *nic*\ 

\ **chvlanports**\  \ *vlanid*\  \ **-n | -**\ **-nodes**\  \ *noderange*\  \ **-i | -**\ **-interface**\  \ *nic*\  \ **-d | -**\ **-delete**\ 

\ **chvlanports**\  [\ **-h | -**\ **-help**\ ]

\ **chvlanports**\  [\ **-v | -**\ **-version**\ ]


***********
DESCRIPTION
***********


The \ **chvlanports**\  command adds nodes switch interfaces to the given vlan. If -d is specified, the nodes switch interfaces will be removed from the vlan.

This command won't create/remove vlans on switches, it just add node's switch ports into exisitng vlan or remove them from existing vlan on switch. Before calling chvlanports, the nodes switch interfaces should be configured in table switch, and vlan must already existing in switches.
=head1 Parameters

\ *vlanid*\  is a unique vlan number.


*******
OPTIONS
*******



\ **-n|-**\ **-nodes**\     The nodes or groups to be added or removed. It takes the noderange format. Check the man page for noderange for details.



\ **-i|-**\ **-interface**\  The interface name where the vlan will be tagged on.



\ **-h|-**\ **-help**\      Display usage message.



\ **-v|-**\ **-version**\   The Command Version.




************
RETURN VALUE
************


0  The command completed successfully.

1  An error has occurred.


********
EXAMPLES
********



1.
 
 To add node1, node2 and node3 to vlan 3 using eth1 interface.
 
 
 .. code-block:: perl
 
    chvlanports 3 -n node1,node2,node3 -i eth1
 
 


2.
 
 TO remove eth1 interface of node1, node2 and node3 from vlan 3.
 
 
 .. code-block:: perl
 
    chvlanports 3 -n node1,node2,node3 -i eth1 -d
 
 



*****
FILES
*****


/opt/xcat/bin/chvlanports


********
SEE ALSO
********


mkvlan(1)|mkvlan.1, rmvlan(1)|rmvlan.1, lsvlan(1)|lsvlan.1, chvlan(1)|chvlan.1

