
############
nodeimport.1
############

.. highlight:: perl


****
NAME
****


\ **nodeimport**\  - Create profiled nodes by importing hostinfo file.


********
SYNOPSIS
********


\ **nodeimport**\  [\ **-h**\  | \ **-**\ **-help**\  | \ **-v**\  | \ **-**\ **-version**\ ]

\ **nodeimport**\  \ **file=**\  \ *hostinfo-filename*\  \ **networkprofile=**\  \ *network-profile*\  \ **imageprofile=**\  \ *image-profile*\  \ **hostnameformat=**\  \ *node-name-format*\  [\ **hardwareprofile=**\  \ *hardware-profile*\ ] [\ **groups=**\  \ *node-groups*\ ]


***********
DESCRIPTION
***********


The \ **nodeimport**\  command creates nodes by importing a hostinfo file which is following stanza format. In this hostinfo file, we can define node's hostname, ip, mac, switch name, switch port and host location infomation like rack, chassis, start unit, server height...etc

After nodes imported, the configuration files related with these nodes will be updated automatically. For example: /etc/hosts, dns configuration, dhcp configuration. And the kits node plugins will also be triggered automatically to update kit related configuration/services.


*******
OPTIONS
*******


\ **-h|-**\ **-help**\ 

Display usage message.

\ **-v|-**\ **-version**\ 

Command Version.

\ **file=**\  \ *nodeinfo-filename*\ 

Specifies the node information file, where <nodeinfo-filename> is the full path and file name of the node information file.

\ **imageprofile=**\  \ *image-profile*\ 

Sets the new image profile name used by the node, where <image-profile> is the new image profile.  An image profile defines the provisioning method, OS information, kit information, and provisioning parameters for a node. If the "__ImageProfile_imgprofile" group already exists in the nodehm table, then "imgprofile" is used as the image profile name.

\ **networkprofile=**\  \ *network-profile*\ 

Sets the new network profile name used by the node, where <network-profile> is the new network profile. A network profile defines the network, NIC, and routes for a node. If the "__NetworkProfile_netprofile" group already exists in the nodehm table, then "netprofile" is used as the network profile name.

\ **hardwareprofile=**\  \ *hardware-profile*\ 

Sets the new hardware profile name used by the node, where <hardware-profile> is the new hardware management profile used by the node. If a "__HardwareProfile_hwprofile" group exists, then "hwprofile" is the hardware profile name. A hardware profile defines hardware management related information for imported nodes, including: IPMI, HMC, CEC, CMM.

\ **hostnameformat=**\  \ *host-name-format*\ 

Sets the node name format for all nodes discovered, where <node-name-format> is a supported format. The two types of formats supported are prefix#NNNappendix and prefix#RRand#NNappendix, where wildcard #NNN and #NN are replaced by a system generated number that is based on the provisioning order. Wildcard #RR represents the rack number and stays constant.

For example, if the node name format is compute-#NN, the node name is generated as: compute-00, compute-01, ... , compute-99. If the node name format is blade#NNN-x64, the node name is generated as: blade001-x64, blade002-x64, ... , blade999-x64

For example, if the node name format is compute-#RR-#NN and the rack number is 2, the node name is generated as: compute-02-00, compute-02-01, ..., compute-02-99. If node name format is node-#NN-in-#RR and rack number is 1, the node name is generated as: node-00-in-01, node-01-in-01, ... , node-99-in-01

\ **groups=**\  \ *node-groups*\ 

Sets the node groups that the imported node belongs to, where <node-group> is a comma-separated list of node groups.


************
RETURN VALUE
************


0  The command completed successfully.

1  An error has occured while validating parameters.

2  An error has occured while parsing hostinfo file.


********
EXAMPLES
********


To import nodes using a profile, follow the following steps:

1. Find all node groups and profiles, run the following command "tabdump nodegroups". For detailed profile information run "lsdef -t group <groupname>". Example of detailed profile information:


.. code-block:: perl

   # tabdump nodegroup
   #groupname,grouptype,members,membergroups,wherevals,comments,disable
   "compute","static",,,,,
   "__HardwareProfile_default_ipmi","static","static",,,,
   "__NetworkProfile_default_mn","static","static",,,,
   "__NetworkProfile_default_cn","static",,,,,
   "__ImageProfile_rhels6.2-x86_64-install-compute","static","static",,,,
    
   # lsdef -t group __NetworkProfile_default_cn
   Object name: __NetworkProfile_default_cn
       grouptype=static
       installnic=eth0
       members=compute-000,compute-001
       netboot=xnba
       nichostnamesuffixes=eth0:-eth0
       nicnetworks=eth0:provision
       nictypes=eth0:Ethernet
       primarynic=eth0


2. Prepare a node information file.


.. code-block:: perl

   Example of a node information file, a blade and a rack server defined: 
   # hostinfo begin
   # This entry defines a blade.
   __hostname__:
      mac=b8:ac:6f:37:59:24
      ip=192.168.1.20
      chassis=chassis01
 
   # This entry defines a rack server.
   __hostname__:
      mac=b8:ac:6f:37:59:25
      ip=192.168.1.20
      rack=rack01
      height=1
      unit=2
 
   # hostinfo end.
 
   Another example of a node infomation file, a PureFlex X/P node defined:
   # hostinfo begin
   # To define a PureFlex P/X node, chassis and slot id must be specified.
   # The chassis must be a PureFlex chassis.
   __hostname__:
      mac=b8:ac:6f:37:59:25
      chassis=cmm01
      slotid=1
   # hostinfo end.
 
   Example of a node information file, a switch auto discovery node defined: 
   # hostinfo begin
   # This entry defines a blade.
   __hostname__:
      switches=eth0!switch1!1,eth0!switch2!1!eth1
 
   Example of a node information file that specifies a CEC-based rack-mounted Power node that uses direct FSP management:
   # Node information file begins
   # This entry defines a Power rack-mount node.
   __hostname__:
      mac=b8:ac:6f:37:59:28
      cec=mycec
   
   __hostname__:
      mac=b8:ac:6f:37:59:28
      cec=mycec
      lparid=2
   # Node information file ends.
   
   Example of a node information file that specifies a PowerKVM Guest node that uses KVM management:
   
   # Node information file begins
   # This entry defines a PowerKVM Guest node.
   # Make sure the node 'vm01' is already created on Hypervisor
   vm01:
      mac=b8:ef:3f:28:31:15
      vmhost=pkvm1
   # Node information file ends.


The node information file includes the following items:

\ **__hostname__:**\   This is a mandatory item.

Description: The name of the node, where __hostname__ is automatically generated by the node name format. You can also input a fixed node name, for example "compute-node".

\ **mac=<mac-address**\ >  This is a mandatory item.

Description: Specify the MAC address for the NIC used by the provisionging node, where <mac-address> is the NICs MAC address.

\ **switches=<nic-name!switch-name!switch-port**\ >  This is a mandatory item, when define switch, switchport and node nic name relationship.

Description: Specify nic name, switch name and switch port to define node and switch relationship. We can define multi nic-switch-port relations here, looks like: switches=eth0!switch1!1,eth1!switch1,2

\ **slotid=<slot-id**\ >  This is a mandatory item while define a PureFlex node.

Description: The node position in the PureFlex Chassis.

\ **cec=<cec-name**\ >  This is a mandatory option for defining Power rack-mounted nodes.

Description: Specifies the name of a Power rack-mount central electronic complex (CEC).

\ **lparid=<lpar-id**\ >  This is a optional option for defining Power rack-mounted nodes.

Description: Specifies the LPAR ID of a Power rack-mounted node, where <lpar-id> is the ID number. The default value is 1 if it is not defined.

\ **ip=<ip-address**\ > This is an optional item.

Description: Specify the IP address used for provisioning a node, where <ip-address> is in the form xxx.xxx.xxx.xxx. If this item is not included, the IP address used to provision the node is generated automatically according to the Network Profile used by the node.

\ **nicips=<nics-ip**\ > This is an optional item.

Description: Lists the IP address for each network interface configuration (NIC) used by the node, excluding the provisioning network, where <nics-ip> is in the form <nic1>!<nic-ip1>,<nic2>!<nic-ip2>,.... For example, if you have 2 network interfaces configured, the nicips attribute should list both network interfaces:  nicips=eth1!10.10.10.11,bmc!192.168.10.3. If the nicips attribute is not specified, the IP addresses are generated automatically according to the network profile.

\ **rack=<rack-name**\ > This is an optional item.

Description: node location info. Specify the rack name which this node will be placed into. If not specify this item, there will be no node location info set for this node. this item must be specified together with height + unit.

\ **chasiss=<chassis-name**\ > This is an optional item.

Description: node location info, for blade(or PureFlex) only. Specify the chasiss name which this blade will be placed into. this item can not be specified together with rack.

\ **height=<chassis-height**\ > This is an optional item.

Description: node location info, for rack server only. Specify the server height number, in U. this item must be specified together with rack and unit.

\ **unit=<rack-server-unit-location**\ > This is an optional item.

Description: node location info, for rack server only. Specify the node's start unit number in rack, in U. this item must be specified together with rack and height.

\ **vmhost=<PowerKVM Hypervisior Host Name**\ >  This is a mandatory option for defining PowerKVM Guest nodes.

Description: Specifies the vmhost of a Power KVM Guest node, where <vmhost> is the host name of PowerKVM Hypervisior.

3. Import the nodes, by using the following commands. Note: If we want to import PureFlex X/P nodes, hardware profile must be set to a PureFlex hardware type.


.. code-block:: perl

   nodeimport file=/root/hostinfo.txt networkprofile=default_cn imageprofile=rhels6.3_packaged hostnameformat=compute-#NNN


4. After importing the nodes, the nodes are created and all configuration files used by the nodes are updated, including: /etc/hosts, DNS, DHCP.

5. Reboot the nodes. After the nodes are booted they are provisioned automatically.


********
SEE ALSO
********


nodepurge(1)|nodepurge.1, nodechprofile(1)|nodechprofile.1, noderefresh(1)|noderefresh.1

