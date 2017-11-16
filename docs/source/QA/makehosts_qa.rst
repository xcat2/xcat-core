DNS,hostname and alias Q/A list
-------------------------------

Q: How to generate ``/etc/hosts`` records when some nics need to be configured by scripts later and other nics only need to add hostnames in ``/etc/hosts``?
````````````````````````````````````````````````````````````````````````````````````````````````````````````````````````````````````````````````````````````

**Best practice example**:

    * There are 2 networks in different domains: ``mgtnetwork`` and ``pubnetwork``
    * ``mgtnetwork`` is xCAT management network
    * There are 4 adapters in system node1: ``ib0``, ``eth0``, ``eth1`` and ``bond0``
    * Add installnic ``eth0`` ``10.5.106.101`` record in ``/etc/hosts``
    * Add ``ib0`` ``10.100.0.101`` record in ``/etc/hosts``
    * hostnames ``node1-grg`` and ``node1.public.com`` are for nic ``eth1``, ip is ``192.168.30.101``
    * ``ib0`` and ``eth1`` will be configured by ``confignetwork`` script
    * ``bond0`` is already configured, but need add ``node1-bond`` ``20.1.1.1`` in ``/etc/hosts``
    * Add ``node1-hb`` with ip ``192.168.0.1`` in ``/etc/hosts``

**Steps**:

    #. Add networks entry in ``networks`` table: ::

        chdef -t network mgtnetwork net=10.0.0.0 mask=255.0.0.0 domain=cluster.com
        chdef -t network pubnetwork net=192.168.30.0 mask=255.255.255.0 domain=public.com

    #. Create ``node1`` with installnic ip ``10.5.106.101``: ::

        chdef node1 ip=10.5.106.101 groups=all

    #. Configure ``ib0`` in ``nics`` table, since it will be configured by ``confignetwork`` later: ::

        chdef node1 nicips.ib0=10.100.0.101 nichostnamesuffixes.ib0=-ib0 nictypes.ib0=Infiniband nicnetworks.ib0=mgtnetwork

    #. Configure ``eth1`` in ``nics`` table, since it will be configured by ``confignetwork`` later: ::

        chdef node1 nicips.eth1=192.168.30.101 nichostnamesuffixes.eth1=-grg nicaliases.eth1=node1.public.com nictypes.eth1=Ethernet nicnetworks.eth1=pubnetwork

    #. Configure ``bond0`` and ``node1-hd`` in ``hosts`` table, since only need add records in ``/etc/hosts`` for them: ::

        chdef node1 otherinterfaces="node1-bond0:20.1.1.1,node1-hd:192.168.0.1"

    #. Check ``node1`` definition: ::

        lsdef node1
            Object name: node1
             groups=all
             ip=10.5.106.101
             nicaliases.eth1=node1.public.com
             nichostnamesuffixes.ib0=-ib0
             nichostnamesuffixes.eth1=-grg
             nicips.ib0=10.100.0.101
             nicips.eth1=192.168.30.101
             nicnetworks.ib0=mgtnetwork
             nicnetworks.eth1=pubnetwork
             nictypes.ib0=Infiniband
             nictypes.eth1=Ethernet
             otherinterfaces=node1-bond0:20.1.1.1,node1-hd:192.168.0.1
             postbootscripts=otherpkgs
             postscripts=syslog,remoteshell,syncfiles

    #. Execute ``makehosts -n`` to generate ``/etc/hosts`` records: ::

        makehosts -n

    #. Check results in ``/etc/hosts``: ::

        10.5.106.101 node1 node1.cluster.com
        20.1.1.1 node1-bond0 node1-bond0.cluster.com
        192.168.0.1 node1-hd node1-hd.cluster.com
        192.168.30.101 node1-pub node1.public.com
        10.100.0.101 node1-ib0 node1-ib0.cluster.com

    #. Edit ``/etc/resolv.conf``: ::

        search cluster.com public.com
        nameserver 10.5.106.2

    #. Execute ``makedns -n`` to configure DNS

Q: When to use ``hosts`` table and ``nics`` table?
``````````````````````````````````````````````````

``hosts`` table is used to store IP addresses and hostnames of nodes. ``makehosts`` use these data to create ``/etc/hosts`` records. ``nics`` table is used to stores secondary NICs details. Some scripts like ``confignetwork`` use data from ``nics`` table to configure secondary NICs. ``makehosts`` also use these data to create ``/etc/hosts`` records for each NIC.

Q: Where to store hostnames aliases and  otherinterfaces aliases?
`````````````````````````````````````````````````````````````````

``hostnames`` in ``hosts`` table are hostname aliases added to ``/etc/hosts`` for the installnic ip. ``otherinterfaces`` in ``hosts`` table are other IP addresses to add for this node, it is only used by ``makehosts`` command to generate ``/etc/hosts`` records for other IP addresses. ``aliases`` in ``nics`` table are comma-separated list of hostname aliases for each NIC.

If only need to generate ``/etc/hosts`` records for some IP addresses, suggest to use ``hostnames`` and ``otherinterfaces`` in ``hosts`` table. If need to configure other nics using script like ``confignetwork``, suggest to use ``aliases`` in ``nics`` table.

**Note**: If the same IP or suffixes/alias are configured in both ``hosts`` table and ``nics`` table, ``makehosts`` will use values from ``nics`` table. The values from ``nics`` table will over-write that from ``hosts`` table to create ``/etc/hosts`` records.

Q: How to generate ``/etc/hosts`` and DNS records with the same hostname in different domains?
``````````````````````````````````````````````````````````````````````````````````````````````

**Best practice example**:

    * There are 2 networks in different domains: ``mgtnetwork`` and ``pubnetwork``
    * ``mgtnetwork`` is xCAT management network
    * Generate 2 records with the same hostname in ``/etc/hosts``, like: ::
   
        10.5.106.101 node1.cluster.com
        192.168.20.101 node1.public.com

    * Nameserver is 10.5.106.2

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

    #. Edit ``/etc/resolv.conf``: ::

        search cluster.com public.com
        nameserver 10.5.106.2

    #. Execute ``makedns -n`` to configure DNS
