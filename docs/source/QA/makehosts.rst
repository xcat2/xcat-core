DNS, Hostname, Alias
====================

Q: When there are multiple NICs, how to generate ``/etc/hosts`` records?
------------------------------------------------------------------------

When there are multiple NICs, and you want to use ``confignetwork`` to configure these NICs, suggest to use ``hosts`` table to configure the installation NIC (``installnic``) and to use ``nics`` table to configure secondary NICs.  Refer to the following example to generate ``/etc/hosts`` records.

**Best practice example**:

    * There are 2 networks in different domains: ``mgtnetwork`` and ``pubnetwork``
    * ``mgtnetwork`` is xCAT management network
    * There are 2 adapters in system node1: ``eth0`` and ``eth1``
    * Add installnic ``eth0`` ``10.5.106.101`` record in ``/etc/hosts``, its alias is ``mgtnic``
    * hostnames ``node1-pub`` and ``node1.public.com`` are for nic ``eth1``, IP is ``192.168.30.101``

**Steps**:

    #. Add networks entry in ``networks`` table: ::

        chdef -t network mgtnetwork net=10.0.0.0 mask=255.0.0.0 domain=cluster.com
        chdef -t network pubnetwork net=192.168.30.0 mask=255.255.255.0 domain=public.com

    #. Create ``node1`` with installnic IP ``10.5.106.101``, its alias is ``mgtnic``: ::

        chdef node1 ip=10.5.106.101 hostnames=mgtnic groups=all

    #. Configure ``eth1`` in ``nics`` table: ::

        chdef node1 nicips.eth1=192.168.30.101 nichostnamesuffixes.eth1=-pub nicaliases.eth1=node1.public.com nictypes.eth1=Ethernet nicnetworks.eth1=pubnetwork

    #. Check ``node1`` definition: ::

        lsdef node1
            Object name: node1
             groups=all
             ip=10.5.106.101
             hostnames=mgtnic
             nicaliases.eth1=node1.public.com
             nichostnamesuffixes.eth1=-pub
             nicips.eth1=192.168.30.101
             nicnetworks.eth1=pubnetwork
             nictypes.eth1=Ethernet
             postbootscripts=otherpkgs
             postscripts=syslog,remoteshell,syncfiles

    #. Execute ``makehosts -n`` to generate ``/etc/hosts`` records: ::

        makehosts -n

    #. Check results in ``/etc/hosts``: ::

        10.5.106.101 node1 node1.cluster.com mgtnic
        192.168.30.101 node1-pub node1.public.com

    #. Edit ``/etc/resolv.conf``, xCAT management node IP like ``10.5.106.2`` is nameserver: ::

        search cluster.com public.com
        nameserver 10.5.106.2

    #. Execute ``makedns -n`` to configure DNS


Q: How to configure aliases?
----------------------------

There are 3 methods to configure aliases:

#. Use ``hostnames`` in ``hosts`` table to configure aliases for the installnic.
#. If you want to use script ``confignetwork`` to configure secondary NICs, suggest to use ``aliases`` in ``nics`` table to configure aliases.  Refer to :doc:`Configure Aliases <../guides/admin-guides/manage_clusters/common/deployment/network/cfg_network_aliases>`
#. If you want to generate aliases records in ``/etc/hosts`` for secondary NICs and you don't want to use the script ``confignetwork`` to configure these NICs, suggest to use ``otherinterfaces`` in ``hosts`` table to configure aliases.  Refer to following example:

    * If you want to add ``node1-hd`` ``20.1.1.1`` in ``hosts`` table, and don't use ``confignetwork`` to configure it, you can add ``otherinterfaces`` like this: ::

        chdef node1 otherinterfaces="node1-hd:20.1.1.1"

    * After executing ``makehosts -n``, you can get records in ``/etc/hosts`` like following: ::

        20.1.1.1 node1-hd

**Note**: If suffixes or aliases for the same IP are configured in both ``hosts`` table and ``nics`` table, will cause conflicts. ``makehosts`` will use values from ``nics`` table. The values from ``nics`` table will over-write that from ``hosts`` table to create ``/etc/hosts`` records.

Q: How to handle the same short hostname in different domains?
--------------------------------------------------------------

You can follow the best practice example.

**Best practice example**:

    * There are 2 networks in different domains: ``mgtnetwork`` and ``pubnetwork``
    * ``mgtnetwork`` is xCAT management network
    * Generate 2 records with the same hostname in ``/etc/hosts``, like: ::

        10.5.106.101 node1.cluster.com
        192.168.20.101 node1.public.com

    * Nameserver is xCAT management node IP

**Steps**:

    #. Add networks entry in ``networks`` table: ::

        chdef -t network mgtnetwork net=10.0.0.0 mask=255.0.0.0 domain=cluster.com
        chdef -t network pubnetwork net=192.168.30.0 mask=255.255.255.0 domain=public.com

    #. Create ``node1`` with ``ip=10.5.106.101``, xCAT can manage and install this node: ::

        chdef node1 ip=10.5.106.101 groups=all

    #. Create ``node1-pub`` with ``ip=192.168.30.101``, this node is only used to generate ``/etc/hosts`` records for public network, can use ``_unmanaged`` group name to label it: ::

        chdef node1-pub ip=192.168.30.101 hostnames=node1.public.com groups=_unmanaged

    #. Execute ``makehosts -n`` to generate ``/etc/hosts`` records: ::

        makehosts -n

    #. Check results in ``/etc/hosts``: ::

        10.5.106.101 node1 node1.cluster.com
        192.168.30.101 node1-pub node1.public.com

    #. Edit ``/etc/resolv.conf``, for example, xCAT management node IP is 10.5.106.2 : ::

        search cluster.com public.com
        nameserver 10.5.106.2

    #. Execute ``makedns -n`` to configure DNS

Q: When to use ``hosts`` table and ``nics`` table?
--------------------------------------------------

``hosts`` table is used to store IP addresses and hostnames of nodes. ``makehosts`` use these data to create ``/etc/hosts`` records. ``nics`` table is used to stores secondary NICs details. Some scripts like ``confignetwork`` use data from ``nics`` table to configure secondary NICs. ``makehosts`` also use these data to create ``/etc/hosts`` records for each NIC.
