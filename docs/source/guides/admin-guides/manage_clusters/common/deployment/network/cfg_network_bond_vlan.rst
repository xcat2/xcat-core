Configure VLAN Based on Bond Adapters
-------------------------------------

The following example sets the xCAT properties for compute node ``cn1`` to create:

  * Compute node ``cn1`` with two physical NICs: ``eth2`` and ``eth3``
  * Bond eth2 and eth3 as ``bond0``
  * Create bridge ``bond0.1`` based on ``bond0``
  * Assign ip ``40.0.0.1`` to the bridge interface ``bond0.1``

Add network object into the networks table
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Add/modify the network ``net40`` in the ``networks`` table ::

    chdef -t network net40 net=40.0.0.0 mask=255.0.0.0

Define attributes in the ``nics`` table
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#. Compute node ``cn1`` has two physical NICs: ``eth2`` and ``eth3`` ::

    chdef cn1 nictypes.eth2=ethernet nictypes.eth3=ethernet

#. Define ``bond0`` and bond ``eth2`` and ``eth3`` as ``bond0`` ::

    chdef cn1 nictypes.bond0=bond nicdevices.bond0="eth2|eth3"

#. Define VLAN ``bond0.1`` based on ``bond0`` ::

    chdef cn1 nicips.bond0.1=40.0.0.1 nictypes.bond0.1=vlan

#. Define ``nicnetworks`` for ``bond0.1`` ::

    chdef cn1 nicnetworks.bond0.1=net40

#. Define ``nichostnamesuffixes`` for ``bond0.1`` in case ``makehosts`` to update ``/etc/hosts``, since the value for ``nichostnamesuffixes`` cannot contain ".", other characters are recommended instead of ".", like following: ::

    chdef cn1 nichostnamesuffixes.bond0.1=-bond0-1

Enable ``confignetwork`` to configure bridge
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#. If adding ``confignetwork`` into the node's postscripts list, ``confignetwork`` will be executed during OS deployment on compute node ::

    chdef cn1 -p postscripts=confignetwork

#. Or if the compute node is already running, use ``updatenode`` command to run ``confignetwork`` postscript ::

    updatenode cn1 -P confignetwork

Verify VLAN
~~~~~~~~~~~

Login to compute node cn1 and check ``ifcfg-bond0.1`` under ``/etc/sysconfig/network-scripts/`` ::

   DEVICE="bond0.1"
   BOOTPROTO="static"
   IPADDR="40.0.0.1"
   NETMASK="255.0.0.0"
   NAME="bond0.1"
   ONBOOT="yes"
   USERCTL=no
   VLAN=yes

Use ``ip addr`` command to check if ``br0`` and ``bond0`` are correct.
