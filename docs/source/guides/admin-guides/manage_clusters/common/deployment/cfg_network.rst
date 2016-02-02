Advanced Networking Configuration
=================================

The ``confignetwork`` postscript can be used to configure the network interfaces on the compute nodes to support VLAN, BONDs, and BRIDGES. In order to use the ``confignetwork`` postscript, the following attributes must be configured for the node in the ``nics`` table:

    * ``nicips``
    * ``nictypes``
    * ``nicnetworks``
    * ``nicdevices`` - resolves the relationship among the physical network intereface devices

The following example set the xCAT properties for compute node ``cn1`` to achieve the following network configuration using the ``confignetwork`` postscript:

  * Compute node ``cn1`` has two physical NICs: eth2 and eth3  
  * Bond eth2 and eth3 as ``bond0`` 
  * From ``bond0``, create 2 VLANs: ``bond0.1`` and ``bond0.2``
  * Make bridge ``br1`` using ``bond0.1`` with IP (10.0.0.1)
  * Make bridge ``br2`` using ``bond0.2`` with IP (20.0.0.1)

Define attributes in the ``nics`` table
---------------------------------------

#. Using the ``mkdef`` or ``chdef`` commands  

    a. Compute node ``cn1`` has two physical NICs: ``eth2`` and ``eth3`` ::
 
        chdef cn1 nictypes.eth2=ethernet nictypes.eth3=ethernet
   
    b. Define ``bond0`` and bond ``eth2`` and ``eth3`` as ``bond0`` ::

        chdef cn1 nictypes.bond0=bond \
                  nicdevices.bond0="eth2|eth3"

    c. Fom ``bond0``, create 2 VLANs: ``bond0.1`` and ``bond0.2`` ::
    
        chdef cn1 nictypes.bond0.1=vlan \
                  nictypes.bond0.2=vlan \
                  nicdevices.bond0.1=bond0 \
                  nicdevices.bond0.2=bond0

    d. Create bridge ``br1`` using ``bond0.1`` with IP (10.0.0.1) ::

        chdef cn1 nictypes.br1=bridge \
                  nicdevices.br1=bond0.1 \
                  nicips.br1=10.0.0.1 \
                  nicnetworks.br1="net10"

    e. Create bridge ``br2`` using ``bond0.2`` with IP (20.0.0.1) ::

        chdef cn1 nictypes.br2=bridge \
                  nicdevices.br2=bond0.2 \
                  nicips.br2=20.0.0.1 \
                  nicnetworks.br2="net20"

#. Using an xCAT stanza file

    - Prepare a stanza file ``<filename>.stanza`` with content similiar to the following: ::

        # <xCAT data object stanza file>
        cn1:
          objtype=node
          arch=x86_64
          groups=kvm,vm,all
          nicdevices.br1=bond0.1 
          nicdevices.br2=bond0.2 
          nicdevices.bond0.1=bond0 
          nicdevices.bond0.2=bond0 
          nicdevices.bond0=eth2|eth3
          nictypes.eth2=ethernet 
          nictypes.eth3=ethernet 
          nictypes.bond0=bond 
          nictypes.bond0.1=vlan 
          nictypes.bond0.2=vlan 
          nictypes.br1=bridge 
          nictypes.br2=bridge 
          nicips.br1=10.0.0.1 
          nicips.br2=20.0.0.1 
          nicnetworks.br1=net10
          nicnetworks.br2=net20

    - Using the ``mkdef -z`` option, define the stanza file to xCAT: ::

        cat <filename>.stanza | mkdef -z

#. Using ``tabedit`` to edit the ``nics`` database table directly

    The ``tabedit`` command opens the specified xCAT database table in a ``vi`` like editor and allows the user to edit any text and write the changes back to the database table.

    After changing the content of the ``nics`` table, here is the result from ``tabdump nics`` ::

        # tabdump nics
        #node,nicips,nichostnamesuffixes,nichostnameprefixes,nictypes,niccustomscripts,nicnetworks,nicaliases,nicextraparams,nicdevices,comments,disable
        "cn1","br1!10.0.0.1,br2!20.0.0.1",,,"br1!bridge,eth2!ethernet,eth3!ethernet,bond0.2!vlan,bond0!bond,br2!bridge,bond0.1!vlan",,"br1!net10,br2!net20",,,"br1!bond0.1,bond0!eth2|eth3,bond0.2!bond0,bond0.1!bond0,br2!bond0.2",,

Add network object into the networks table
------------------------------------------

The ``nicnetworks`` attribute only defines the nic that uses the IP address.
Other information about the network should be defined in the ``networks`` table.

Use the ``chdef`` command to add/modify the networks in the ``networks`` table ::

    chdef -t network net10 net=10.0.0.0 mask=255.0.0.0 mgtifname=eth0
    chdef -t network net20 net=20.0.0.0 mask=255.0.0.0 mgtifname=eth1

Add ``confignetwork`` into the node's postscripts list
------------------------------------------------------

Using below command to add ``confignetwork`` into the node's postscripts list ::

    chdef cn1 -p postscripts=confignetwork


During OS deployment on compute node, ``confignetwork`` will be run in postscript. 
If the compute node has OS, use ``updatenode`` command to run ``confignetwork`` ::

    updatenode cn1 -P confignetwork





