
########
mkvlan.1
########

.. highlight:: perl


****
NAME
****


\ **mkvlan**\  - It takes a list of nodes and create a private tagged vlan for them.


********
SYNOPSIS
********


\ **mkvlan**\  [\ *vlanid*\ ] \ **-n | -**\ **-nodes**\  \ *noderange*\  [\ **-t | -**\ **-net**\  \ *subnet*\ ] [\ **-m | -**\ **-mask**\  \ *netmask*\ ] [\ **-p | -**\ **-prefix**\  \ *hostname_prefix*\ ] [\ **-i | -**\ **-interface**\  \ *nic*\ ]

\ **mkvlan**\  [\ **-h | -**\ **-help**\ ]

\ **mkvlan**\  [\ **-v | -**\ **-version**\ ]


***********
DESCRIPTION
***********


The \ **mkvlan**\  command takes a list of nodes and move them to a private vlan.

This command will configure the switch to create a new tagged vlan on the given nic. The primary nic will be used if the nic is not specified.  The new vlan ID is given by the command.  However, if it is omitted, xCAT will automatically generate the new vlan ID by querying all the switches involved and finding out the smallest common number that is not used by any existing vlans.  The subnet and the netmask for the vlan will be derived from the value of "vlannets" and "vlanmasks" from the \ *site*\  table if -t and -m are not specified. The following are the default site table entires:


.. code-block:: perl

     vlannets="|(\d+)|10.($1+0).0.0|";
     vlanmask="255.255.0.0";


The vlan network will be entered in the \ *networks*\  table. The nodes will be added to the vlan using the vlan tagging technique. And the new IP addresses and new hostnames will be assigned to the nodes.  The -p flag specifies the node hostname prefix for the nodes.  If it is not specified, by default, the hostnames for the nodes are having the following format:

v<vlanid>nY  where Y is the node number. For example, the hostname for node 5 on vlan 10 is v10n5.

The \ *switch.vlan*\  will be updated with the new vlan id for the node for standaline nodes. For KVM guests, the \ *vm.nics*\  identifies which vlan this node belongs to. For example: vl3 means this node is in vlan 3.

If there are more than one switches involved in the vlan, the ports that connect to the switches need to entered in \ *switches.linkports*\  with the following format:


.. code-block:: perl

     <port numner>:switch,<port number>:switch....


For example:


.. code-block:: perl

     "42:switch1,43:switch2"


This command will automatically configure the cross-over ports if the given nodes are on different switches.

For added security, the root guard and bpdu guard will be enabled for the ports in this vlan. However, the guards will not be disabled if the ports are removed from the vlan using chvlan or rmvlan commands. To disable them, you need to use the switch command line interface. Refer to the switch command line interface manual to see how to disable the root guard and bpdu guard for a port.


**********
PARAMETERS
**********


\ *vlanid*\  is a unique vlan number. If it is omitted, xCAT will automatically generate the new vlan ID by querying all the switches involved and finding out the smallest common number that is not used by any existing vlans. Use \ **lsvlan**\  to find out the existing vlan ids used by xCAT.


*******
OPTIONS
*******



\ **-n|-**\ **-nodes**\      The nodes or groups to be included in the vlan. It can be stand alone nodes or KVM guests. It takes the noderange format. Check the man page for noderange for details.



\ **-t|-**\ **-net**\        The subnet for the vlan.



\ **-m|-**\ **-mask**\       The netmask for the vlan



\ **-p|-**\ **-prefix**\     The prefix the the new hostnames for the nodes in the vlan.



\ **-i|-**\ **-interface**\  The interface name where the vlan will be tagged on. If omitted, the xCAT management network will be assumed. For FVM, this is the interface name on the host.



\ **-h|-**\ **-help**\       Display usage message.



\ **-v|-**\ **-version**\    The Command Version.




************
RETURN VALUE
************


0  The command completed successfully.

1  An error has occurred.


********
EXAMPLES
********


To start, the xCAT switches and switches table needs to be filled with switch and port info for the nodes. For example, the swith table will look like this:

#node,switch,port,vlan,interface,comments,disable
"node1","switch1","10",,,,
"node1","switch2","1",,"eth1",,
"node2","switch1","11",,"primary",,
"node2","switch2","2",,"eth1",,
"node3","switch1","12",,"primary:eth0",,
"node3","switch2","3",,"eth1",,

Note that the interface value for the management (primary) network can be empty, the word "primary" or "primary:ethx". For other networks, the interface attribute must be specified.

The following is an example of the switches table

#switch,snmpversion,username,password,privacy,auth,linkports,sshusername,sshpassword,switchtype,comments,disable
"switch1","3","username","passw0rd",,"sha","48:switch2",,,,,
"switch2","2",,,,,"43:switch1",,,,,


1.
 
 To make a private vlan for node1, node2 and node3
 
 
 .. code-block:: perl
 
    mkvlan -n node1,node2,node3
 
 
 The vlan will be created on eth0 for the nodes.
 


2.
 
 To make a private vlan for node1, node2 and node3 on eth1,
 
 
 .. code-block:: perl
 
    mkvlan -n node1,node2,node3 -i eth1
 
 


3.
 
 To make a private vlan for node1, node2 with given subnet and netmask.
 
 
 .. code-block:: perl
 
    mkvlan -n node1,node2,node3 -t 10.3.2.0 -m 255.255.255.0
 
 


4.
 
 To make a private vlan for KVM guests node1 and node2
 
 
 .. code-block:: perl
 
    chtab key=usexhrm site.vlaue=1
   
    mkdef node1 arch=x86_64 groups=kvm,all installnic=mac primarynic=mac mgt=kvm netboot=pxe nfsserver=10.1.0.204 os=rhels6 profile=compute provmethod=install serialport=0 serialspeed=115200 vmcpus=1 vmhost=x3650n01 vmmemory=512 vmnics=br0 vmstorage=nfs://10.1.0.203/vms
  
    mkdef node2 arch=x86_64 groups=kvm,all installnic=mac primarynic=mac mgt=kvm netboot=pxe nfsserver=10.1.0.204 os=rhels6 profile=compute provmethod=install serialport=0 serialspeed=115200 vmcpus=1 vmhost=x3650n01 vmmemory=512 vmnics=br0 vmstorage=nfs://10.1.0.203/vms
  
    mkvlan -n node1,node2 
  
    mkvm node1,node2 -s 20G
  
    rpower node1,node2 on
  
    rinstall node1,node2
 
 



*****
FILES
*****


/opt/xcat/bin/mkvlan


********
SEE ALSO
********


chvlan(1)|chvlan.1, rmvlan(1)|rmvlan.1, lsvlan(1)|lsvlan.1

