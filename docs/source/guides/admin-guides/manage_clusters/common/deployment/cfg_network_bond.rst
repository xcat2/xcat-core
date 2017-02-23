Configure Two Bonded Adapters
-----------------------------

The following example set the xCAT properties for compute node ``cn1`` to create:

  * Compute node ``cn1`` has two physical NICs: eth2 and eth3  
  * Bond eth2 and eth3 as ``bond0`` 

Define attributes in the ``nics`` table
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~


#. Using the ``mkdef`` or ``chdef`` commands  

    a. Compute node ``cn1`` has two physical NICs: ``eth2`` and ``eth3`` ::
 
        chdef cn1 nictypes.eth2=ethernet nictypes.eth3=ethernet
   
    b. Define ``bond0`` and bond ``eth2`` and ``eth3`` as ``bond0`` ::

        chdef cn1 nictypes.bond0=bond \
                  nicdevices.bond0="eth2|eth3"

Add network object into the networks table
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Use the ``chdef`` command to add/modify the networks in the ``networks`` table ::

    chdef -t network net40 net=20.0.0.0 mask=255.0.0.0 mgtifname=eth1
    chdef cn1 nicnetworks.bond0=net40

Add ``confignetwork`` into the node's postscripts list
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Use command below to add ``confignetwork`` into the node's postscripts list ::

    chdef cn1 -p postscripts=confignetwork


During OS deployment on compute node, ``confignetwork`` postscript will be executed. 
If the compute node is already running, use ``updatenode`` command to run ``confignetwork`` postscript without rebooting the node::

    updatenode cn1 -P confignetwork


Verify bonding mode
~~~~~~~~~~~~~~~~~~~

Login to compute node cn1 and check bonding options in ``/etc/sysconfig/network-scripts/ifcfg-bond0`` file ::

   BONDING_OPTS="mode=802.3ad xmit_hash_policy=layer2+3"

The ``mode=802.3ad`` requires additional configuration on the switch. ``mode=2`` can be used for bonding without additional switch configuration. If changes are made to ``/etc/sysconfig/network-scripts/ifcfg-bond0`` file, restart network service ::

   systemctl restart network.service
