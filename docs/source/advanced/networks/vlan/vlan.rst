VLAN Configuration
==================

Overview
--------

The main intent for this feature is the following scenario: you have a cluster with 100 nodes all on the Ethernet switch. A user requests 10 nodes from the cluster, but wants to run some sensitive things on the 10 nodes, so wants them isolated from the other 90 nodes. So as part of scheduling these 10 nodes for this user, you want to create a VLAN for these 10 nodes that is separate from the LAN the other 90 nodes are on.

xCAT has provided the following commands to do the VLAN creation and manipulation in the **xCAT-vlan** package.

* mkvlan
* chvlan
* lsvlan
* rmvlan

These VLAN functions are supported for stand-alone nodes as well as virtual machines such as KVMs.

Install the package
-------------------

Install the ``xCAT-vlan`` package using the package manager on the OS. 

[RHEL] ::

    yum install xCAT-vlan

[SLES] ::

    zypper install xCAT-vlan

[Ubuntu] ::

    apt-get install xCAT-vlan

Prepare the Cluster
-------------------

Assume the management node is installed and the other nodes are defined in the cluster. The following is what you need to do in order to use the VLAN Configuration feature.

**1. Populate the switches table**

Make sure the correct SNMP information is entered into the **switches** table for the switches involved. If there are more than one switches involved in a vlan, the ports that connect to the switches need to entered in switches.linkports with the following format: ::

    <port number>:switch,<port number>:switch....

For example: ::

    # switch,snmpversion,username,password,privacy,auth,linkports,comments,disable
    "switch1","3","user1","passw0rd",,"sha","42:switch2",,
    "switch2","2c",,,,,"50:switch1",,
    "switch3","3","admin","passw0rd","des","sha",,,
    "switch4","2c",,"mycomminity",,,,,

This means port 42 of switch1 is connected to port 50 of switch2. And switch1 can be accessed using SNMP version 3 and switch 2 can be accessed using SNMP version 2.

Note: The **username** and the **password** on the switches table are NOT the same as SSH user name and password. You have to configure SNMP on the switch for these parameters and then fill up this table. Use **tabdump switches -d** command to find out the meaning of each column.

**2. Populate the switch table**

Make sure each node has the correct switch name and port number in the **switch** table.

For example: ::

    # node,switch,port,vlan,interface,comments,disable
    "node1","switch1","33",,,,
    "node2","switch1","34",,,,
    "node3","switch2","10",,,,

For xCAT-vlan 2.7.5 and later versions, it supports creating vlans for other networks as well. To specify other networks in the switch table, the switch.interface must be specified. For example: ::

    # node,switch,port,vlan,interface,comments,disable
    "node1","switch1","33",,,,
    "node2","switch1","34",,"primary",,
    "node3","switch2","10",,"primary:eth0",,
    "node1","switch2","11",,"eth1",,
    "node2","switch2","12",,"eth1",,
    "node3","switch2","13",,"eth1",,

The interface eth1 is for the application network on node1, node2 and node3. Note that there are two rows for each node. One is for the management network and the other is for the application network. The value for **switch.interface** for management network can be empty, the word "primary" or "primary:ethx".

**3. Configure the switch for SNMP access**

Make sure that the MN can access the switch using SNMP and the switch is configured such that it has SNMP read and write permissions.

You can use **snmpwalk/snmpget** and **snmpset** commands on the mn to check. These commands are from **net-snmp-utils** rpm.

**4. Define the VLAN subnet and mask pattern**

The **site** table keys called "vlannets" and "vlanmasks" will be used to define a range of networks that can be used to define vlans. The format is a regular expression.

For example: ::

    vlannets: |(\d+)|10.($1+0).0.0|
    vlanmasks:  255.255.255.0

This means that the network for the vlan id 5 will be 10.5.0.0 and the mask is 255.255.255.0.

However, user can also customize a vlan network and netmask using -t and -m flags on **mkvlan** command.

**5. Customize host names and ip addresses for nodes**

Within the vlan, by default the hostnames for the nodes are having the following format: ::

    v<vlanid>nY

where Y is the node number.

For example, the hostname for node 5 on vlan 10 is v10n5.

User can customize the host name and ip addresses using the **hosts** table. If the host name and ip addresses are found on the **hosts.otherinterfaces**, then it will be used. For example: ::

    #node,ip,hostnames,otherinterfaces,comments,disable
    "node1","192.168.1.1",,"test1:10.0.0.1",,
    "node2","192.168.1.2",,"test2:10.0.0.2",,

**6. For KVM clients**

If you are going to include KVM clients in the VLANs, set the site table key "usexhrm" to be 1. ::

    chdef -t site usexhrm=1

Create a VLAN
-------------

For standalone nodes, VLAN can be created while the nodes are running or down.

To make a private vlan for stand-alone nodes for the management network: ::

    mkvlan -n node1,node2,node3

You can specify vlan id, subnet and netmask etc. ::

    mkvlan 3 -n node1,node2,node3 -t 10.3.2.0 -m 255.255.255.0

For virtual machines, the vm guests must be down. To make a private vlan for KVM guests. ::

    chdef -t site -o clustersite usexhrm=1
    mkdef node1 arch=x86_64 groups=kvm,all installnic=mac primarynic=mac mgt=kvm netboot=pxe nfsserver=10.1.0.204 os=rhels6 profile=compute provmethod=install serialport=0 serialspeed=115200 vmcpus=1 vmhost=x3650n01 vmmemory=512 vmnics=br0 vmstorage=nfs://10.1.0.203/vms
    mkdef node2 arch=x86_64 groups=kvm,all installnic=mac primarynic=mac mgt=kvm netboot=pxe nfsserver=10.1.0.204 os=rhels6 profile=compute provmethod=install serialport=0 serialspeed=115200 vmcpus=1 vmhost=x3650n01 vmmemory=512 vmnics=br0 vmstorage=nfs://10.1.0.203/vms
    mkvlan -n node1,node2
    mkvm node1,node2 -s 20G
    rpower node1,node2 on
    rinstall node1,node2

For xCAT-vlan 2.7.5 and later versions, you can create vlans for other networks. This can be done by using -i flag to specify the interface of the network. For example: ::

    mkvlan -n node1,node2,node3 -i eth1

A tagged vlan will be created for the network that is on eth1 for node1, node2 and node3. For KVM clients, -i specifies the interface name on the KVM host that the vlan will be tagged on. If -i is omitted, the management networks will be assumed.

Note: After the vlan is created, the nodes can still be accessed by the mn using the management network. You can use **lsvan** command to list all the vlans.

For example: ::

    # lsvlan
    vlan 3:
      subnet 10.3.0.0
      netmask 255.255.0.0
    vlan 99:
      subnet 10.99.0.0
      netmask 255.255.0.0

    # lsvlan 3
    vlan 3
      subnet 10.3.0.0
      netmask 255.255.0.0
      hostname    ip address      node            vm host
      v3n1        10.3.0.1        node1
      v3n2        10.3.0.2        node2
      v3n3        10.3.0.3        node3           host1

Modify a VLAN
-------------

You can use the **chvlan** command to add or remove nodes to/from an existing vlan.

For standalone nodes, just run the command while the node are running or not. For example:

To add ::

    chvlan 3 -n node4,node5

To remove ::

    chvlan 3 -n node4,node5 -d

For virtual machines, adding them to the vlan requires that they are defined and they are not up and running.

For example: ::

    mkdef node4 arch=x86_64 groups=kvm,all installnic=mac primarynic=mac mgt=kvm netboot=pxe nfsserver=10.1.0.204 os=rhels6 profile=compute provmethod=install serialport=0 serialspeed=115200 vmcpus=1 vmhost=x3650n01 vmmemory=512 vmnics=br0 vmstorage=nfs://10.1.0.203/vms
    mkdef node5 arch=x86_64 groups=kvm,all installnic=mac primarynic=mac mgt=kvm netboot=pxe nfsserver=10.1.0.204 os=rhels6 profile=compute provmethod=install serialport=0 serialspeed=115200 vmcpus=1 vmhost=x3650n01 vmmemory=512 vmnics=br0 vmstorage=nfs://10.1.0.203/vms
    chvlan 3 -n node4,node5
    mkvm node4,node5 -s 20G
    rpower node4,node5 on
    rinstall node4,node5

For xCAT-vlan 2.7.5 and later versions, you can modify vlans for other networks. This can be done by using -i flag to specify the interface of the network. For KVM clients, -i specifies the interface name on the KVM host that the vlan will be tagged on. If -i is omitted, the management networks will be assumed.

For example: ::

    chvlan 3 -n node4,node5 -i eth1

There is no need to specify -i flag for removing nodes from a vlan.

Remove a VLAN
-------------

The **rmvlan** command removes the given vlan ID from the cluster. It removes the vlan id from all the swithces involved, deconfigures the nodes so that vlan adaptor (tag) will be remved, cleans up /etc/hosts, DNS and database tables for the given vlan.

For example: ::

    rmvlan 3

VLAN Security
-------------

To make the vlan more secure, the root guard and the bpdu guard are enabled for each ports within the vlan by **mkvlan** and **chvlan** commands. This way it guards the topology changes on the switch by the hackers who hack the STP. However, when the vlan is removed by the **rmvlan** and the **chvlan (-d)** commands, the root guard and the bpdu guard are not disabled because the code cannot tell if the guards were enabled by the admin or not. If you want to remove the gurads after the vlan is removed, you need to use the switch command line interface to do so. Refer to the documents for the switch command line interfaces for details.

Limitation
----------

Current xCAT-vlan package does not work on the following os distributions. More work will be done in the future releases. 

* ubuntu
* rhel7 and later
* sles12 and later

