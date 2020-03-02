Configure Ethernet Network Interface
------------------------------------

The following example sets the xCAT properties for compute node ``cn1`` to create:

  * Compute node ``cn1`` with two physical NICs: ``eth0`` and ``eth1``
  * Management network is ``11.1.89.0``, application network is ``13.1.89.0``
  * The install NIC is eth0, and application NIC is eth1
  * Assign static ip ``11.1.89.7/24`` to eth0
  * Assign static ip ``13.1.89.7/24`` to eth1

Add/update networks into the xCAT DB
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Add/update additional networks ``net11`` and ``net13`` into ``networks`` table::

    chdef -t network net11 net=11.1.89.0 mask=255.255.255.0
    chdef -t network net13 net=13.1.89.0 mask=255.255.255.0

**Note:** MTU can be customized as ``mtu`` in ``networks`` table for specified network.

Define Adapters in the nics table
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#. Provision ip is coming from DHCP, there is no need to configure install nic into ``nics`` table. Provision ip can be configured in node definition, but it is not required. ::

    chdef cn1 ip=11.1.89.7

#. Data NIC ``eth1`` is not install NIC, configure ``eth1`` into ``nics`` table  ::

    chdef cn1 nicips.eth1="13.1.89.7" nicnetworks.eth1="net13" nictypes.eth1="Ethernet" nichostnamesuffixes.eth1=-eth1

Update /etc/hosts
~~~~~~~~~~~~~~~~~

#. Run the ``makehosts`` command to add the new configuration to the ``/etc/hosts`` file.  ::

    makehosts cn1

#. Check ``/etc/hosts`` ::

    cat /etc/hosts
    11.1.89.7 cn1 cn1.cluster.com
    13.1.89.7 cn1-eth1 cn1-eth1.cluster.com

Configure adapters with static IPs
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#. Execute ``confignetwork -s`` to configure both provision ip ``11.1.89.7`` and application data ip ``13.1.89.7`` as static

    a. Add ``confignetwork -s`` into postscript list to execute on reboot ::

        chdef cn1 -p postscripts="confignetwork -s"

    b. If the compute node is already running, use ``updatenode`` command to run ``confignetwork -s`` postscript without rebooting the node ::

        updatenode cn1 -P "confignetwork -s"

#. If install NIC is not configured in ``nics`` table, and only configure all other NIC's data defined in ``nics`` table, execute ``confignetwork`` without ``-s``

    a. Add ``confignetwork`` into postscript list to execute on reboot ::

        chdef cn1 -p postscripts="confignetwork"

    b. If the compute node is already running, use ``updatenode`` command to run ``confignetwork`` postscript without rebooting the node ::

        updatenode cn1 -P "confignetwork"

.. note:: Option ``-s`` writes the install NIC's information into configuration file for persistence. All other NIC's data defined in ``nics`` table will be written also. Without option ``-s``, ``confignetwork`` only configures all NIC's data defined in ``nics`` table.

Check result
~~~~~~~~~~~~

#. Use ``xdsh cn1 "ip addr"`` to check ``eth0`` and ``eth1``

#. Check ``ifcfg-eth0`` and ``ifcfg-eth1`` under ``/etc/sysconfig/network-scripts/``
