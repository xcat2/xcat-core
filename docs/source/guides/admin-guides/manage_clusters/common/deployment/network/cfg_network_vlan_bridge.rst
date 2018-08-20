Configure Bridge Based on VLAN
------------------------------

The following example set the xCAT properties for compute node ``cn1`` to create:

  * Compute node ``cn1`` has one physical NIC: eth0
  * Define 2 vlans: eth0.6 and eth0.7 based on eth0
  * Define 2 bridge br1 and br2
  * Assign ip ``60.5.106.9`` to br1 and ``70.5.106.9`` to br2

Define attributes in the ``nics`` table
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#. Using the ``mkdef`` or ``chdef`` commands

    a. Compute node ``cn1`` has one physical NIC: ``eth0`` ::

        chdef cn1 nictypes.eth0=ethernet

    b. Define vlan ``eth0.6`` and ``eth0.7`` based on ``eth0`` ::

        chdef cn1 nictypes.eth0.6=vlan nicdevices.eth0.6="eth0" nictypes.eth0.7=vlan nicdevices.eth0.7="eth0"

    c. Define bridge ``br1`` and ``br2`` ::

        chdef cn1 nicips.br1=60.5.106.9 nicips.br2=70.5.106.9 nictypes.br1=bridge nictypes.br2=bridge

Add network object into the networks table
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Use the ``chdef`` command to add/modify the networks in the ``networks`` table ::

    chdef -t network net60 net=60.0.0.0 mask=255.0.0.0
    chdef -t network net70 net=70.0.0.0 mask=255.0.0.0
    chdef cn1 nicnetworks.br1=net60 nicnetworks.br2=net70

Add ``confignetwork`` into the node's postscripts list
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Use command below to add ``confignetwork`` into the node's postscripts list ::

    chdef cn1 -p postscripts=confignetwork


During OS deployment on compute node, ``confignetwork`` postscript will be executed.
If the compute node is already running, use ``updatenode`` command to run ``confignetwork`` postscript without rebooting the node::

    updatenode cn1 -P confignetwork

Verify Bridge
~~~~~~~~~~~~~

Login to compute node cn1 and check ``ifcfg-br1`` and ``ifcfg-br2`` under ``/etc/sysconfig/network-scripts/`` like ::

    BOOTPROTO="static"
    IPADDR="60.5.106.9"
    NETMASK="255.0.0.0"
    NAME="br1"
    ONBOOT="yes"
    STP="on"
    TYPE="Bridge"

Use ``ip addr`` command to check if ``br1``, ``br2``, ``eth0.6`` and ``eth0.7``.
