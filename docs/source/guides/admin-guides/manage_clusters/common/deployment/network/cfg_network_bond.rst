Configure Bond using two Ethernet Adapters
------------------------------------------

The following example sets the xCAT properties for compute node ``cn1`` to create:

  * Compute node ``cn1`` with two physical NICs: ``eth2`` and ``eth3``
  * Bond eth2 and eth3 as ``bond0``
  * Assign ip ``40.0.0.1`` to the bonded interface ``bond0``

Add network object into the networks table
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Add the network ``net40`` in the ``networks`` table ::

    chdef -t network net40 net=40.0.0.0 mask=255.0.0.0

Define attributes in the ``nics`` table
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#. Compute node ``cn1`` has two physical NICs: ``eth2`` and ``eth3`` ::

    chdef cn1 nictypes.eth2=ethernet nictypes.eth3=ethernet

#. Define ``bond0`` and bond ``eth2`` and ``eth3`` as ``bond0`` ::

    chdef cn1 nictypes.bond0=bond nicdevices.bond0="eth2|eth3"
    chdef cn1 nicips.bond0=40.0.0.1

#. Define ``nicnetworks`` for ``bond0`` ::

    chdef cn1 nicnetworks.bond0=net40

Enable ``confignetwork`` to configure bond
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#. If adding ``confignetwork`` into the node's postscripts list, ``confignetwork`` will be executed during OS deployment on compute node ::

    chdef cn1 -p postscripts=confignetwork

#. Or if the compute node is already running, use ``updatenode`` command to run ``confignetwork`` postscript ::

    updatenode cn1 -P confignetwork

Verify bonding mode
~~~~~~~~~~~~~~~~~~~

Login to compute node cn1 and check bonding options in ``/etc/sysconfig/network-scripts/ifcfg-bond0`` file ::

   BONDING_OPTS="mode=802.3ad xmit_hash_policy=layer2+3"


* ``mode=802.3ad`` requires additional configuration on the switch.
* ``mode=2`` can be used for bonding without additional switch configuration.
