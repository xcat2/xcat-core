Configure Aliases
-----------------

The following example sets the xCAT properties for compute node ``cn1`` to create:

  * Compute node ``cn1`` with one physical NIC: ``eth2``
  * User wants to configure aliases ``aliases1-1`` and ``aliases1-2``
  * Assign ip ``11.1.0.100`` to ``aliases1-1`` and ``12.1.0.100`` to ``aliases1-2``

Add network object into the networks table
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Add/modify the networks in the ``networks`` table ::

    chdef -t network -o 11_1_0_0-255_255_0_0 net=11.1.0.0 mask=255.255.0.0
    chdef -t network -o 12_1_0_0-255_255_0_0 net=12.1.0.0 mask=255.255.0.0

Define attributes in the ``nics`` table
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~


#. Compute node ``cn1`` has one physical NICs: ``eth2`` ::

    chdef cn1 nictypes.eth2=ethernet

#. Define ``nicips``, ``nicaliases``, ``nichostnamesuffixes`` ::

    chdef cn1 nicips.eth2="11.1.0.100|12.1.0.100" nicaliases.eth2="aliases1-1|aliases1-2" nichostnamesuffixes.eth2="-eth2|-eth2-1"

#. Define ``nicnetworks`` ::

    chdef cn1 nicnetworks.eth2="11_1_0_0-255_255_0_0|12_1_0_0-255_255_0_0"

Update /etc/hosts
~~~~~~~~~~~~~~~~~

#. Update the ``/etc/hosts`` file ::

    makehosts cn1

#. Check the ``/etc/hosts`` file ::

    11.1.0.100 cn1-eth2 cn1-eth2.cluster.com aliases1-1
    12.1.0.100 cn1-eth2-1 cn1-eth2-1.cluster.com aliases1-2

Enable ``confignetwork`` to configure aliases
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#. Add ``confignetwork`` into the node's postscripts list, ``confignetwork`` will be executed during OS deployment on compute node ::

    chdef cn1 -p postscripts=confignetwork

#. Or if the compute node is already running, use ``updatenode`` command to run ``confignetwork`` postscript ::

    updatenode cn1 -P confignetwork

Check the result
~~~~~~~~~~~~~~~~

Check if eth2 is configured correctly ::

    xdsh cn1 "ip addr show eth2"

