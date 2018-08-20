Configure Bridge Based On Ethernet NIC
--------------------------------------

The following example set the xCAT properties for compute node ``cn1`` to create:

  * Compute node ``cn1`` has one physical NIC: eth1
  * User wants to confgure 1 bridge br1 based on eth1
  * Assign ip ``30.5.106.9`` to br0

Add network object into the networks table
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Add/modify the network ``net30`` in the ``networks`` table ::

    chdef -t network net30 net=30.0.0.0 mask=255.0.0.0

Define attributes in the ``nics`` table
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#. Compute node ``cn1`` has one physical NIC: ``eth1`` ::

    chdef cn1 nictypes.eth1=ethernet

#. Define bridge ``br1`` based on ``eth1`` ::

    chdef cn1 nictypes.br1=bridge nicdevices.br1="eth1"
    chdef cn1 nicips.br1=30.5.106.9

#. Define ``nicnetworks`` for ``br1`` ::

    chdef cn1 nicnetworks.br1=net30

Enable ``confignetwork`` to configure bridge
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#. If add ``confignetwork`` into the node's postscripts list, ``confignetwork`` will be executed during OS deployment on compute node ::

    chdef cn1 -p postscripts=confignetwork

#. Or if the compute node is already running, use ``updatenode`` command to run ``confignetwork`` postscript ::

    updatenode cn1 -P confignetwork

Verify Bridge
~~~~~~~~~~~~~

Login to compute node cn1 and check configure files in ``ifcfg-br1`` under ``/etc/sysconfig/network-scripts/`` ::

    TYPE=Bridge
    STP=on

Check ``ifcfg-eth1`` under ``/etc/sysconfig/network-scripts/`` ::

    BRIDGE=br1

Use ``ip addr`` command to check if ``br1``, ``eth0.6`` and ``eth0.7`` are correct.
