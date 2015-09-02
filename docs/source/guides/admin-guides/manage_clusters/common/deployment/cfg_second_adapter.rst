Configure Secondary Network Adapter
===================================

Introduction
------------
The **nics** table and the **confignics** postscript can be used to automatically configure additional **ethernet** and **Infiniband** adapters on nodes as they are being deployed. ("Additional adapters" means adapters other than the primary adapter that the node is being installed/booted over.)

The way the confignics postscript decides what IP address to give the secondary adapter is by checking the nics table, in which the nic configuration information is stored.

To use the nics table and confignics postscript to define a secondary adapter on one or more nodes, follow these steps:


Define configuration information for the Secondary Adapters in the nics table
-----------------------------------------------------------------------------

There are 3 ways to complete this operation.

**First way is use command line input. below is a example**
::
    [root@ls21n01 ~]# mkdef cn1 groups=all nicips.eth1="11.1.89.7|12.1.89.7" nicnetworks.eth1="net11|net12" nictypes.eth1="Ethernet"
    1 object definitions have been created or modified.
    
    [root@ls21n01 ~]# chdef cn1 nicips.eth2="13.1.89.7|14.1.89.7" nicnetworks.eth2="net13|net14" nictypes.eth2="Ethernet"
    1 object definitions have been created or modified.

**Second way is using stanza file**

prepare your stanza file <filename>.stanza. the content of <filename>.stanza like below:
::
    # <xCAT data object stanza file>
    cn1:
      objtype=node
      arch=x86_64
      groups=kvm,vm,all
      nichostnamesuffixes.eth1=-eth1-1|-eth1-2
      nichostnamesuffixes.eth2=-eth2-1|-eth2-2
      nicips.eth1=11.1.89.7|12.1.89.7
      nicips.eth2=13.1.89.7|14.1.89.7
      nicnetworks.eth1=net11|net12
      nicnetworks.eth2=net13|net14
      nictypes.eth1=Ethernet
      nictypes.eth2=Ethernet

define configuration information by <filename>.stanza
::
    cat <filename>.stanza | mkdef -z

**Third way is use 'tabedit' to edit the nics table directly**

The 'tabedit' command opens the specified table in the user's editor(such as VI), allows user to edit any text, and then writes changes back to the database table.	But it's tedious and error prone, so don't recommended this way. if using this way, notices the **nicips**, **nictypes** and **nicnetworks** attributes are required.

Here is a sample nics table content:
::
    [root@ls21n01 ~]# tabdump nics
    #node,nicips,nichostnamesuffixes,nictypes,niccustomscripts,nicnetworks,nicaliases,comments,disable
    "cn1","eth1!11.1.89.7|12.1.89.7,eth2!13.1.89.7|14.1.89.7","eth1!-eth1-1|-eth1-2,eth2!-eth2-1|-eth2-2,"eth1!Ethernet,eth2!Ethernet",,"eth1!net11|net12,eth2!net13|net14",,,

After you have define configuration information by any way above, you can run below command to put configuration information into /etc/hosts:
::
    makehosts cn1

Then /etc/hosts will looks like:
::
    11.1.89.7 cn1-eth1-1 cn1-eth1-1.ppd.pok.ibm.com
    12.1.89.7 cn1-eth1-2 cn1-eth1-2.ppd.pok.ibm.com
    13.1.89.7 cn1-eth2-1 cn1-eth2-1.ppd.pok.ibm.com
    14.1.89.7 cn1-eth2-2 cn1-eth2-2.ppd.pok.ibm.com	

Add confignics into the node's postscripts list
-----------------------------------------------

Using below command to add confignics into the node's postscripts list
::
    chdef cn1 -p postscripts=confignics

By default, confignics does not configure the install nic. if need, using flag "-s" to allow the install nic to be configured.
::
    chdef cn1 -p prostscripts="confignics -s"

Option "-s" write the install nic's information into configuration file for persistance. All install nic's data defined in nics table will be written also.


Add network object into the networks table
------------------------------------------

The nicnetworks attribute only defined the network object name which used by the ip address. Other information about the network should be define in the networks table. Can use tabedit to add/ modify the networks objects.
::
    #netname,net,mask,mgtifname,gateway,dhcpserver,tftpserver,nameservers,ntpservers,logservers,dynamicrange,staticrange,staticrangeincrement,nodehostname,ddnsdomain,vlanid,domain,comments,disable
    ...
    "net11", "11.1.89.0", "255.255.255.0", "eth1",,,,,,,,,,,,,,,
    "net12", "12.1.89.0", "255.255.255.0", "eth1",,,,,,,,,,,,,,,
    "net13", "13.1.89.0", "255.255.255.0", "eth2",,,,,,,,,,,,,,,
    "net14", "14.1.89.0", "255.255.255.0", "eth2",,,,,,,,,,,,,,,

Option -r to remove the undefined NICS
---------------------------------------
If the compute node's nics were configured by confignics, and the nics configuration changed in the nics table, can use "confignics -r" to remove the undefined nics. For example: On the compute node the eth0, eth1 and eth2 were configured
::
    # ifconfig
    eth0      Link encap:Ethernet  HWaddr 00:14:5e:d9:6c:e6
    ...
    eth1      Link encap:Ethernet  HWaddr 00:14:5e:d9:6c:e7
    ...
    eth2      Link encap:Ethernet  HWaddr 00:14:5e:d9:6c:e8
    ...

Delete the eth2 definition in nics table with chdef command. Run
::
    updatenode <noderange> -P "confignics -r" to remove the undefined eth2 on the compute node.

The complete result is:
::
    # ifconfig
    eth0      Link encap:Ethernet  HWaddr 00:14:5e:d9:6c:e6
    ...
    eth1      Link encap:Ethernet  HWaddr 00:14:5e:d9:6c:e7
    ...

Deleting the install nic will import some strange problems. So confignics -r can not delete the install nic.











