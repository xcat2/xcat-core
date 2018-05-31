.. _setup_ha_mgmt_node_with_shared_data_auto:

Setup xCAT HA MN Node With Shared Data
======================================

This documentation illustrates how to use ``xcatha.py`` script to setup xCAT primary and standby management nodes to provide high availability management capability, using shared data between the two management nodes. 

If you wish to manually setup xCAT primary and standby management nodes, see the following advanced documentation :doc:`Setup HA Mgmt Node With Shared Data <setup_ha_mgmt_node_with_shared_data>`

xCAT ships a script `xcatha.py <https://github.com/xcat2/xcat-extensions/tree/master/HA/xcatha.py>`_ to setup a xCAT HA management node and execute failover. 

User Scenarios
==============

Use case
--------

As a xCAT user, I have ``host1`` and ``host2`` with the same shared data directory, I want to configure xCAT HA management nodes.

The following scenarios are **examples** to ``setup/failover`` xCAT HA management nodes.

Pre-requirements for User
-------------------------

User should prepare the followings before setup shared data based xCAT HA management node:

    #. Two nodes, for example: ``host1`` and ``host2``

    #. Setup shared data location (for example ``/HA``) accessible from both ``host1`` and ``host2`` nodes.

    #. Virtual IP, for example: ``10.5.106.50``

    #. The NIC that the virtual IP address attaches to, for example: ``eth0:0``

    #. Virtual IP's hostname, for example: ``hamn``

    #. Net mask for virtual IP (it is optional, default value is ``255.255.255.0``): ``255.0.0.0``

    #. Optional database type, supported choices are ``postgresql`` or ``mysql`` or ``sqlite``, default is ``postgresql``

Setup xCAT HA Management Node
-----------------------------

This section use ``xcatha.py`` to setup xCAT management node to the following work:

    #. Configure VIP and its hostname

    #. Copy xCAT data into shared data directory, and make symbolic links from xCAT directory to share data directories::

        /install -> /HA/install
        /etc/xcat -> /HA/etc/xcat
        /root/.xcat -> /HA/root/.xcat
        /var/lib/pgsql -> /HA/var/lib/pgsql
        /tftpboot -> /HA/tftpboot

    #. Install xCAT from `xcat.org <http://xcat.org>`_ if xCAT is not installed

    #. Switch DB to target type

    #. Deactivate this MN

        #. Stop the following services and configure them not to start on reboot::

            console service(conserver, goconserver)
            dhcpd
            named
            xcatd
            database (postgresql)

        #. remove symbolic links from xCAT directory to share data directories

        #. remove VIP and its hostname

The following scenarios are examples to setup xCAT HA management nodes.

Scenario 1: xCAT is not installed on 2 xCAT MN nodes
````````````````````````````````````````````````````

``host1`` is installed as xCAT primary MN, ``host2`` is installed as xCAT standby MN. They can access `xcat.org <http://xcat.org/>`_

    #. Copy `xcatha.py <https://github.com/xcat2/xcat-extensions/tree/master/HA/xcatha.py>`_ on ``host1``, execute ``xcatha.py`` to setup and configure ``host1`` using ``VIP`` and ``hostname`` as xCAT standby MN::

        python xcatha.py -s -p /HA -v 10.5.106.50 -i eth0:0 -n hamn -m 255.0.0.0 -t postgresql

    #. Copy ``xcatha.py`` on ``host2``, execute ``xcatha.py`` to setup and configure ``host2`` using ``VIP` and ``hostname`` as xCAT standby MN::

        python xcatha.py -s -p /HA -v 10.5.106.50 -i eth0:0 -n hamn -m 255.0.0.0 -t postgresql

    #. Activate ``host1`` as xCAT primary active MN::
      
        python xcatha.py -a -p /HA -v 10.5.106.50 -i eth0:0 -m 255.0.0.0 -t postgresql

Scenario 2: user has xCAT MN host1, he wants to add new node host2 as xCAT standby MN node
``````````````````````````````````````````````````````````````````````````````````````````

    #. The original xCAT MN ``host1`` IP ``10.5.106.50`` becomes virtual IP, user should add another IP like ``10.5.106.5`` for the NIC ``eth0``. Copy `xcatha.py <https://github.com/xcat2/xcat-extensions/tree/master/HA/xcatha.py>`_ on ``host1``, setup ``host1`` as standby MN::

        python xcatha.py -s -p /HA -v 10.5.106.50 -i eth0:0 -n hamn -m 255.0.0.0 -t postgresql

    #. Copy ``xcatha.py`` on ``host2``, execute ``xcatha.py`` to setup and configure ``host2`` as a xCAT standby MN::
        
        python xcatha.py -s -p /HA -v 10.5.106.50 -i eth0:0 -n hamn -m 255.0.0.0 -t postgresql

    #. Activate ``host1`` as xCAT primary active MN::
  
        python xcatha.py -a -p /HA -v 10.5.106.50 -i eth0:0 -m 255.0.0.0 -t postgresql 

Failover
--------

There are two kinds of failover, planned failover and unplanned failover. In a planned failover, you can do necessary cleanup work on the previous primary management node before failover to the previous standby management node. In a unplanned failover, the previous management node probably is not functioning at all, you can simply shutdown the system.

This section use ``xcatha.py`` to failover ``activate|deactivate`` the ``primary|standby`` MN node. 

#. During ``activate`` process, ``xcatha.py`` will to the following work:

    #. Configure VIP and its hostname

    #. Make symbolic link to share data directories::

        /install -> /HA/install
        /etc/xcat -> /HA/etc/xcat
        /root/.xcat -> /HA/root/.xcat
        /var/lib/pgsql -> /HA/var/lib/pgsql
        /tftpboot -> /HA/tftpboot

    #. Start following services::

        database (postgresql)
        xcatd
        named service (makedns -n)
        DHCP service (makedhcp -n, makedhcp -a)
        Console server 

#. During ``deactivate`` process, ``xcatha.py`` will to the following work:

    #. Stop following services::

        console service (conserver, goconserver)
        dhcpd
        named 
        xcatd
        database (postgresql)

    #. remove symbolic link

    #. remove VIP and its hostname 

Scenario 1: active xCAT MN host1 has problems, but OS is still accessible
`````````````````````````````````````````````````````````````````````````

This Scenario can execute a planned failover.

    #. Execute ``xcatha.py`` on ``host1`` to deactivate ``host1`` as non-active xcat MN node::

        python xcatha.py -d -v 10.5.106.50 -i eth0:0

    #. Execute ``xcatha.py`` on ``host2`` to activate ``host2`` as active xcat MN node::

        python xcatha.py -a -p /HA -v 10.5.106.50 -i eth0:0 -m 255.0.0.0 -t postgresql

Scenario 2: active xCAT MN host1 is not accessible
``````````````````````````````````````````````````

Reboot this xCAT MN node ``host1``, after it boots:

    #. if we can access to its OS, we can execute a planned failover, the steps are the same with above **Secenairo 1: active xCAT MN host1 is broken and we can access to its OS**.

    #. if we cannot access to ``host1`` OS 

        #. Execute ``xcatha.py`` on ``host2`` to activate ``host2`` as active xcat MN node::

            python xcatha.py -a -p /HA -v 10.5.106.50 -i eth0:0 -m 255.0.0.0 -t postgresql

        #. Recommend recover ``host1``.
