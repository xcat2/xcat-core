
########
lsvlan.1
########

.. highlight:: perl


****
NAME
****


\ **lsvlan**\  - It lists the existing vlans for the cluster.


********
SYNOPSIS
********


\ **lsvlan**\ 

\ **lsvlan**\  [\ *vlanid*\ ]

\ **lsvlan**\  [\ **-h | -**\ **-help**\ ]

\ **lsvlan**\  [\ **-v | -**\ **-version**\ ]


***********
DESCRIPTION
***********


The \ **lsvlan**\  command lists all the vlans for the cluster. If \ *vlanid*\  is specifined it will list more details about this vlan including the nodes in the vlan.


**********
PARAMETERS
**********


\ *vlanid*\  is a unique vlan number. If it is omitted, all vlans will be listed.


*******
OPTIONS
*******



\ **-h|-**\ **-help**\   Display usage message.



\ **-v|-**\ **-version**\   Command Version.




************
RETURN VALUE
************


0  The command completed successfully.

1  An error has occurred.


********
EXAMPLES
********



1. To list all the vlans in the cluster
 
 
 .. code-block:: perl
 
    lsvlan
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
    vlan 3:
        subnet 10.3.0.0
        netmask 255.255.0.0
  
    vlan 4:
        subnet 10.4.0.0
        netmask 255.255.0.0
 
 


2. To list the details for vlan3
 
 
 .. code-block:: perl
 
    lsvlan 3
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
    vlan 3
        subnet 10.3.0.0
        netmask 255.255.0.0
  
        hostname    ip address      node            vm host
        v3n1        10.3.0.1        c68m4hsp06
        v3n2        10.3.0.2        x3455n01
        v3n3        10.3.0.3        x3650n01
        v3n4        10.3.0.4        x3650n01kvm1    x3650n01
        v3n5        10.3.0.5        x3650n01kvm2    x3650n01
 
 



*****
FILES
*****


/opt/xcat/bin/lsvlan


********
SEE ALSO
********


mkvlan(1)|mkvlan.1, rmvlan(1)|rmvlan.1, chvlan(1)|chvlan.1

