Configure BOND, VLAN and BRIDGES
--------------------------------

The ``confignetwork`` postscript can be used to configure the network interfaces on the compute nodes to support VLAN, BONDs, and BRIDGES. In order for the ``confignetwork`` postscript to run successfully, the following attributes must be configured for the node in the ``nics`` table:

    * ``nicips``
    * ``nictypes``
    * ``nicnetworks``
    * ``nicdevices`` - resolves the relationship among the physical network interface devices

The following example set the xCAT properties for compute node ``cn1`` to achieve the following network configuration using the ``confignetwork`` postscript:

  * Compute node ``cn1`` has two physical NICs: ``eth2`` and ``eth3``  
  * Bond ``eth2`` and ``eth3`` as ``bond0`` 
  * From ``bond0``, create 2 VLANs: ``bond0.1`` and ``bond0.2``
  * Make bridge ``br1`` using ``bond0.1`` with IP (10.0.0.1)
  * Make bridge ``br2`` using ``bond0.2`` with IP (20.0.0.1)

Define attributes in the ``nics`` table
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Chose one of two methods described below:

#. Using the ``mkdef`` or ``chdef`` commands  

    a. Compute node ``cn1`` has two physical NICs: ``eth2`` and ``eth3`` ::
 
        chdef cn1 nictypes.eth2=ethernet nictypes.eth3=ethernet
   
    b. Define ``bond0`` and bond ``eth2`` and ``eth3`` as ``bond0`` ::

        chdef cn1 nictypes.bond0=bond \
                  nicdevices.bond0="eth2|eth3"

    c. From ``bond0``, create 2 VLANs: ``bond0.1`` and ``bond0.2`` ::
    
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

Define the additional networks to xCAT
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

If this is a new network being created on the compute nodes, an entry needs to be created into the xCAT database.

The ``nicnetworks`` attribute only defines the nic that uses the IP address.
Other information about the network should be defined in the ``networks`` table.

Use the ``chdef`` command to add/modify the networks in the ``networks`` table ::

    chdef -t network net10 net=10.0.0.0 mask=255.0.0.0
    chdef -t network net20 net=20.0.0.0 mask=255.0.0.0

Add ``confignetwork`` into the node's postscripts list
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Use the following command to add ``confignetwork`` into postscript list to execute on reboot: ::

    chdef cn1 -p postscripts=confignetwork

If the compute node is already running, use ``updatenode`` command to run ``confignetwork`` postscript without rebooting the node::

    updatenode cn1 -P confignetwork

