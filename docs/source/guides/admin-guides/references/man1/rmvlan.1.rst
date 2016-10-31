
########
rmvlan.1
########

.. highlight:: perl


****
NAME
****


\ **rmvlan**\  - It remves the vlan from the cluster.


********
SYNOPSIS
********


\ **rmvlan**\  \ *vlanid*\ 

\ **rmvlan**\  [\ **-h | -**\ **-help**\ ]

\ **rmvlan**\  [\ **-v | -**\ **-version**\ ]


***********
DESCRIPTION
***********


The \ **rmvlan**\  command removes the given vlan ID from the cluster. It removes the vlan id from all the swithces involved, deconfigures the nodes so that vlan adaptor (tag) will be remved, cleans up /etc/hosts, DNS and database tables for the given vlan.

For added security, the root guard and bpdu guard were enabled for the ports in this vlan by mkvlan and chvlan commands. However, the guards will not be disabled by this command. To disable them, you need to use the switch command line interface. Refer to the switch command line interface manual to see how to disable the root guard and bpdu guard for a port.


**********
Parameters
**********


\ *vlanid*\  is a unique vlan number.


*******
OPTIONS
*******



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
 
 To remove vlan 3
 
 
 .. code-block:: perl
 
    rmvlan 3
 
 
 If the nodes are KVM guest then the do the following after the vlan is removed:
   rpower node1,node2 off
   rmvm node1,node2
 



*****
FILES
*****


/opt/xcat/bin/rmvlan


********
SEE ALSO
********


mkvlan(1)|mkvlan.1, chvlan(1)|chvlan.1, lsvlan(1)|lsvlan.1

