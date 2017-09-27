Configure VLAN Based on Ethernet Adapter
----------------------------------------

The following example set the xCAT properties for compute node ``cn1`` to create:

  * Compute node ``cn1`` has one physical NIC: eth0
  * Confgure 2 vlans: eth0.6 and eth0.7 based on eth0
  * Assign ip ``60.5.106.9`` to eth0.6 and ``70.5.106.9`` to eth0.7

Define the additional networks to xCAT
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Add/modify the networks ``net60`` and ``net70`` in the ``networks`` table ::

    chdef -t network net60 net=60.0.0.0 mask=255.0.0.0
    chdef -t network net70 net=70.0.0.0 mask=255.0.0.0

Define attributes in the ``nics`` table
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#. Compute node ``cn1`` has one physical NIC: ``eth0`` ::

    chdef cn1 nictypes.eth0=ethernet

#. Define vlan ``eth0.6`` and ``eth0.7`` based on ``eth0`` ::

    chdef cn1 nictypes.eth0.6=vlan nicdevices.eth0.6="eth0" nictypes.eth0.7=vlan nicdevices.eth0.7="eth0"
    chdef cn1 nicips.eth0.6=60.5.106.9 nicips.eth0.7=70.5.106.9

#. Define ``nicnetworks`` for ``eth0.6`` and ``eth0.7`` ::

    chdef cn1 nicnetworks.eth0.6=net60 nicnetworks.eth0.7=net70

#. Define ``nichostnamesuffixes`` for ``eth0.6`` and ``eth0.7`` in case ``makehosts`` to update ``/etc/hosts``, since the value for ``nichostnamesuffixes`` cannot contain ".", other characters are recommended instead of ".", like following: ::

    chdef cn1 nichostnamesuffixes.eth0.6=-eth0-6 nichostnamesuffixes.eth0.7=-eth0-7

Enable ``confignetwork`` to configure VLAN
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#. Add ``confignetwork`` into postscript list to execute on reboot ::

    chdef cn1 -p postscripts=confignetwork

#. If the compute node is already running, use ``updatenode`` command to run ``confignetwork`` postscript without rebooting the node ::

    updatenode cn1 -P confignetwork

Verify VLAN
~~~~~~~~~~~

Login to compute node cn1 and check VLAN options in ``ifcfg-eth0.6`` and ``ifcfg-eth0.7`` under ``/etc/sysconfig/network-scripts/`` ::

    VLAN=yes

Use ``ip addr`` command to check if ``eth0.6`` and ``eth0.7`` are there.
