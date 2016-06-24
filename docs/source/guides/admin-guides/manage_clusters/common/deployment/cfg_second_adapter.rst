Configure Additional Network Interfaces
=======================================

The **nics** table and the **confignics** postscript can be used to automatically configure additional network interfaces (mutltiple ethernets adapters, InfiniBand, etc) on the nodes as they are being deployed.

The way the confignics postscript decides what IP address to give the secondary adapter is by checking the nics table, in which the nic configuration information is stored.

To use the nics table and confignics postscript to define a secondary adapter on one or more nodes, follow these steps:


Define configuration information for the Secondary Adapters in the nics table
-----------------------------------------------------------------------------

There are 3 ways to complete this operation.

1. Using the ``mkdef`` and ``chdef`` commands  ::

    # mkdef cn1 groups=all nicips.eth1="11.1.89.7|12.1.89.7" nicnetworks.eth1="net11|net12" nictypes.eth1="Ethernet"
    1 object definitions have been created or modified.
    
    # chdef cn1 nicips.eth2="13.1.89.7|14.1.89.7" nicnetworks.eth2="net13|net14" nictypes.eth2="Ethernet"
    1 object definitions have been created or modified.

2. Using an xCAT stanza file

   - Prepare a stanza file ``<filename>.stanza`` with content similiar to the following: ::

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

    - Using the ``mkdef -z`` option, define the stanza file to xCAT: ::

        # cat <filename>.stanza | mkdef -z

3. Using ``tabedit`` to edit the ``nics`` database table directly

   The ``tabedit`` command opens the specified xCAT database table in a vi like editor and allows the user to edit any text and write the changes back to the database table. 

   *WARNING* Using the ``tabedit`` command is not the recommended method because it is tedious and error prone. 

   After changing the content of the ``nics`` table, here is the result from ``tabdump nics`` ::

        # tabdump nics
        #node,nicips,nichostnamesuffixes,nictypes,niccustomscripts,nicnetworks,nicaliases,comments,disable
        "cn1","eth1!11.1.89.7|12.1.89.7,eth2!13.1.89.7|14.1.89.7","eth1!-eth1-1|-eth1-2,eth2!-eth2-1|-eth2-2,"eth1!Ethernet,eth2!Ethernet",,"eth1!net11|net12,eth2!net13|net14",,,


After you have defined the configuration information in any of the ways above, run the ``makehosts`` command to add the new configuration to the ``/etc/hosts`` file.  ::

    # makehosts cn1

    # cat /etc/hosts
    11.1.89.7 cn1-eth1-1 cn1-eth1-1.ppd.pok.ibm.com
    12.1.89.7 cn1-eth1-2 cn1-eth1-2.ppd.pok.ibm.com
    13.1.89.7 cn1-eth2-1 cn1-eth2-1.ppd.pok.ibm.com
    14.1.89.7 cn1-eth2-2 cn1-eth2-2.ppd.pok.ibm.com	


Add confignics into the node's postscripts list
-----------------------------------------------

Using below command to add confignics into the node's postscripts list ::

    chdef cn1 -p postscripts=confignics

By default, confignics does not configure the install nic. if need, using flag "-s" to allow the install nic to be configured.  ::

    chdef cn1 -p prostscripts="confignics -s"

Option "-s" write the install nic's information into configuration file for persistance. All install nic's data defined in nics table will be written also.


Add network object into the networks table
------------------------------------------

The ``nicnetworks`` attribute only defines the nic that uses the IP address.  
Other information about the network should be defined in the ``networks`` table.  

Use the ``tabedit`` command to add/modify the networks in the``networks`` table ::

    tabdump networks
    #netname,net,mask,mgtifname,gateway,dhcpserver,tftpserver,nameservers,ntpservers,logservers,dynamicrange,staticrange,staticrangeincrement,nodehostname,ddnsdomain,vlanid,domain,comments,disable
    ...
    "net11", "11.1.89.0", "255.255.255.0", "eth1",,,,,,,,,,,,,,,
    "net12", "12.1.89.0", "255.255.255.0", "eth1",,,,,,,,,,,,,,,
    "net13", "13.1.89.0", "255.255.255.0", "eth2",,,,,,,,,,,,,,,
    "net14", "14.1.89.0", "255.255.255.0", "eth2",,,,,,,,,,,,,,,

Option -r to remove the undefined NICS
--------------------------------------

If the compute node's nics were configured by ``confignics`` and the nics configuration changed in the nics table, user the ``confignics -r`` to remove the undefined nic.  

For example, if on a compute node the ``eth0``, ``eth1``, and ``eth2`` nics were configured: ::
    # ifconfig
    eth0      Link encap:Ethernet  HWaddr 00:14:5e:d9:6c:e6
    ...
    eth1      Link encap:Ethernet  HWaddr 00:14:5e:d9:6c:e7
    ...
    eth2      Link encap:Ethernet  HWaddr 00:14:5e:d9:6c:e8
    ...

Delete the eth2 definition in nics table using the ``chdef`` command. 
Then run the following to remove the undefined ``eth2`` nic on the compute node: ::

    # updatenode <noderange> -P "confignics -r"

The result should have ``eth2`` disabled: ::

    # ifconfig
    eth0      Link encap:Ethernet  HWaddr 00:14:5e:d9:6c:e6
    ...
    eth1      Link encap:Ethernet  HWaddr 00:14:5e:d9:6c:e7
    ...

Deleting the ``installnic`` will result in strange problems, so ``confignics -r`` will not delete the nic set as the ``installnic``.
