Configure Bridge Based on Bond Adapters
---------------------------------------

The following example sets the xCAT properties for compute node ``cn1`` to create:

  * Compute node ``cn1`` with two physical NICs: ``eth2`` and ``eth3``
  * Bond eth2 and eth3 as ``bond0``
  * Create bridge ``br0`` based on ``bond0``
  * Assign ip ``40.0.0.1`` to the bridge interface ``br0``

Add network object into the networks table
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Add/modify network data in the ``networks`` table ::

    chdef -t network net40 net=40.0.0.0 mask=255.0.0.0

Define attributes in the ``nics`` table
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#. Compute node ``cn1`` has two physical NICs: ``eth2`` and ``eth3`` ::

    chdef cn1 nictypes.eth2=ethernet nictypes.eth3=ethernet

#. Define ``bond0`` and bond ``eth2`` and ``eth3`` as ``bond0`` ::

    chdef cn1 nictypes.bond0=bond nicdevices.bond0="eth2|eth3"

#. Define ``br0`` based on ``bond0`` ::

    chdef cn1 nicips.br0=40.0.0.1 nictypes.br0=bridge

#. Define ``nicnetworks`` for ``br0`` ::

    chdef cn1 nicnetworks.br0=net40

Enable ``confignetwork`` to configure bridge
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#. If adding ``confignetwork`` into the node's postscripts list, ``confignetwork`` will be executed during OS deployment on compute node ::

    chdef cn1 -p postscripts=confignetwork

#. Or if the compute node is already running, use ``updatenode`` command to run ``confignetwork`` postscript ::

    updatenode cn1 -P confignetwork

Verify bridge
~~~~~~~~~~~~~

Login to compute node cn1 and check bonding options in ``/etc/sysconfig/network-scripts/ifcfg-bond0`` file ::

    DEVICE="bond0"
    BOOTPROTO="none"
    NAME="bond0"
    BONDING_MASTER="yes"
    ONBOOT="yes"
    USERCTL="no"
    TYPE="Bond"
    BONDING_OPTS="mode=802.3ad miimon=100"
    DHCLIENTARGS="-timeout 200"
    BRIDGE=br0

Check ``ifcfg-br0`` under ``/etc/sysconfig/network-scripts/`` ::

   DEVICE="br0"
   BOOTPROTO="static"
   IPADDR="40.0.0.1"
   NETMASK="255.0.0.0"
   NAME="br0"
   ONBOOT="yes"
   STP="on"
   TYPE="Bridge"

Use ``ip addr`` command to check if ``br0`` and ``bond0`` are correct.
