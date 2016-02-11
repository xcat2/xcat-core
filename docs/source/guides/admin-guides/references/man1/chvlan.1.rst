
########
chvlan.1
########

.. highlight:: perl


****
NAME
****


\ **chvlan**\  - It adds or removes nodes for the vlan.


********
SYNOPSIS
********


\ **chvlan**\  \ *vlanid*\  \ **-n | -**\ **-nodes**\  \ *noderange*\  [\ **-i | -**\ **-interface**\  \ *nic*\ ]

\ **chvlan**\  \ *vlanid*\  \ **-n | -**\ **-nodes**\  \ *noderange*\  \ **-d | -**\ **-delete**\ 

\ **chvlan**\  [\ **-h | -**\ **-help**\ ]

\ **chvlan**\  [\ **-v | -**\ **-version**\ ]


***********
DESCRIPTION
***********


The \ **chvlan**\  command adds nodes to the given vlan. If -d is specified, the nodes will be removed from the vlan.

For added security, the root guard and bpdu guard will be enabled for the ports added to this vlan. However, the guards will not be disabled if the ports are removed from the vlan using chvlan (-d) or rmvlan commands. To disable them, you need to use the switch command line interface. Please refer to the switch command line interface manual to see how to disable the root guard and bpdu guard for a port.


**********
Parameters
**********


\ *vlanid*\  is a unique vlan number.


*******
OPTIONS
*******



\ **-n|-**\ **-nodes**\     The nodes or groups to be added or removed. It can be stand alone nodes or KVM guests. It takes the noderange format. Please check the man page for noderange for details.



\ **-i|-**\ **-interface**\  (For adding only). The interface name where the vlan will be tagged on. If omitted, the xCAT management network will be assumed. For KVM, it is the interface name on the host.



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
 
 To add node1, node2 and node3 to vlan 3.
 
 
 .. code-block:: perl
 
    chvlan 3 -n node1,node2,node3
 
 


2.
 
 To add node1, node2 and node3 to vlan 3 using eth1 interface.
 
 
 .. code-block:: perl
 
    chvlan 3 -n node1,node2,node3 -i eth1
 
 


3.
 
 TO remove node1, node2 and node3 from vlan 3.
 
 
 .. code-block:: perl
 
    chvlan -n node1,node2,node3 -d
 
 


4.
 
 To add KVM guests node1 and node2 to vlan 3
 
 
 .. code-block:: perl
 
    mkdef node1 arch=x86_64 groups=kvm,all installnic=mac primarynic=mac mgt=kvm netboot=pxe nfsserver=10.1.0.204 os=rhels6 profile=compute provmethod=install serialport=0 serialspeed=115200 vmcpus=1 vmhost=x3650n01 vmmemory=512 vmnics=br0 vmstorage=nfs://10.1.0.203/vms
  
    mkdef node2 arch=x86_64 groups=kvm,all installnic=mac primarynic=mac mgt=kvm netboot=pxe nfsserver=10.1.0.204 os=rhels6 profile=compute provmethod=install serialport=0 serialspeed=115200 vmcpus=1 vmhost=x3650n01 vmmemory=512 vmnics=br0 vmstorage=nfs://10.1.0.203/vms
  
    chvlan 3 -n node1,node2
  
    mkvm node1,node2 -s 20G
  
    rpower node1,node2 on
  
    rinstall node1,node2
 
 


5.
 
 To remove KVM guests node1 and node2 from vlan 3
 
 
 .. code-block:: perl
 
    chvlan 3 -n node1,node2 -d
  
    rpower node1,node2 off
  
    rmvm node1,node2
 
 



*****
FILES
*****


/opt/xcat/bin/chvlan


********
SEE ALSO
********


mkvlan(1)|mkvlan.1, rmvlan(1)|rmvlan.1, lsvlan(1)|lsvlan.1

