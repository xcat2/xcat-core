Configure BOND/VLAN/BRIDGE
===========================

The ``nics`` table and the ``confignetwork`` script can be used to automatically configure network interfaces (VLAN, BOND, BRIDGE) on the redhat nodes.

To use ``confignetwork``, ``nicips``, ``nictypes``, ``nicnetworks`` and ``nicdevice`` attributes in ``nics`` table should be configured.

``nicdevice`` resolves relationships among physical_nics/BOND/VLAN/BRIDGE.

To use the nics table and confignetwork postscript to configure VLAN/BOND/BRIDGE on one or more nodes, here gives an example: 

    a. Physical nics are eth2 and eth3 
    b. Bonding eth2 and eth3 as bond0 
    c. From bond0, make 2 vlans: bond0.1 and bond0.2
    d. Making bridge br1 using bond0.1, making bridge br2 using bond0.2, br1 ip is 10.0.0.1, br2 ip is 20.0.0.1

You should execute these steps:

Define configuration information for the BOND/VLAN/BRIDGE Adapters in the nics table
-------------------------------------------------------------------------------------

There are 3 ways to complete this operation.

#. Using the ``mkdef`` or ``chdef`` commands  

    a. add nicdevice to define nics relationship ::
 
        chdef cn1 nicdevice.br1=bond0.1 nicdevice.br2=bond0.2 nicdevice.bond0.1=bond0 nicdevice.bond0.2=bond0 nicdevice.bond0="eth2|eth3"

    b. add nictypes and nicnetworks ::
    
        chdef cn1 nictypes.eth2=ethernet nictypes.eth3=ethernet nictypes.bond0=bond nictypes.bond0.1=vlan nictypes.bond0.2=vlan nictypes.br1=bridge nictypes.br2=bridge nicips.br1=10.0.0.1 nicips.br2=20.0.0.1 nicnetworks.br1="net10" nicnetworks.br2="net20"

#. Using an xCAT stanza file

    - Prepare a stanza file ``<filename>.stanza`` with content similiar to the following: ::

        # <xCAT data object stanza file>
        cn1:
          objtype=node
          arch=x86_64
          groups=kvm,vm,all
          nicdevice.br1=bond0.1 
          nicdevice.br2=bond0.2 
          nicdevice.bond0.1=bond0 
          nicdevice.bond0.2=bond0 
          nicdevice.bond0=eth2|eth3
          nictypes.eth2=ethernet 
          nictypes.eth3=ethernet 
          nictypes.bond0=bond 
          nictypes.bond0.1=vlan 
          nictypes.bond0.2=vlan 
          nictypes.br1=bridge 
          nictypes.br2=bridge 
          nicips.br1=10.0.0.1 
          nicips.br2=20.0.0.1 
          nicnetworks.br1="net10" 
          nicnetworks.br2="net20"

    - Using the ``mkdef -z`` option, define the stanza file to xCAT: ::

        cat <filename>.stanza | mkdef -z

#. Using ``tabedit`` to edit the ``nics`` database table directly

    The ``tabedit`` command opens the specified xCAT database table in a vi like editor and allows the user to edit any text and write the changes back to the database table.

    *WARNING* Using the ``tabedit`` command is not the recommended method because it is tedious and error prone.

    After changing the content of the ``nics`` table, here is the result from ``tabdump nics`` ::

        # tabdump nics
        #node,nicips,nichostnamesuffixes,nichostnameprefixes,nictypes,niccustomscripts,nicnetworks,nicaliases,nicextraparams,nicdevice,comments,disable
        "cn1","br1!10.0.0.1,br2!20.0.0.1",,,"br1!bridge,eth2!ethernet,eth3!ethernet,bond0.2!vlan,bond0!bond,br2!bridge,bond0.1!vlan",,"br1!net10,br2!net20",,,"br1!bond0.1,bond0!eth2|eth3,bond0.2!bond0,bond0.1!bond0,br2!bond0.2",,

Add confignetwork into the node's postscripts list
-----------------------------------------------

Using below command to add confignetwork into the node's postscripts list ::

    chdef cn1 -p postscripts=confignetwork

Add network object into the networks table
------------------------------------------

The ``nicnetworks`` attribute only defines the nic that uses the IP address.
Other information about the network should be defined in the ``networks`` table.

Use the ``tabedit`` command to add/modify the networks in the ``networks`` table ::

    #netname,net,mask,mgtifname,gateway,dhcpserver,tftpserver,nameservers,ntpservers,logservers,dynamicrange,staticrange,staticrangeincrement,nodehostname,ddnsdomain,vlanid,domain,comments,disable
    "net10","10.0.0.0","255.0.0.0","eth0",,,,,,,,,,,,,,,
    "net20","20.0.0.0","255.0.0.0","eth1",,,,,,,,,,,,,,,





