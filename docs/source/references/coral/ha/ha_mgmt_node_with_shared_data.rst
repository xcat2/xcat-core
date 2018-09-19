.. _ha_mgmt_node_with_shared_data:


HA Solution Overview
====================

While a xCAT management node ``xcatmn1`` is running as a primary management node, another node - ``xcatmn2`` can be configured to act as primary management node in case ``xcatmn1`` becomes unavailable. The process is manual and requires disabling primary ``xcatmn1`` and activating backup ``xcatmn2``. Both nodes require access to shared storage described below. Use of Virtual IP is also requred.

An interactive sample script `xcatha.py <https://github.com/xcat2/xcat-extensions/blob/master/HA/xcatha.py>`_ is availabe to guide through the steps of disabling and activation of xCAT management nodes. ``Dryrun`` option in that scrip allows viewing the actions without executing them.

Configure and Activate Primary xCAT Management Node
===================================================

Disable And Stop All Related Services on Primary xCAT Management Node
`````````````````````````````````````````````````````````````````````

Before configuring Virtual IP and shared data, make sure to stop related services. Since primary management node may become unavailable at any time, all related services should be configured to not auto start at boot time.

Use ``xcatha.py -d`` to disable and stop all related services: ::

    ./xcatha.py -d
    2018-06-22 03:43:51,600 - INFO - [xCAT] Shutting down services:
    ... goconserver
    ... conserver
    ... ntpd
    ... dhcpd
    ... named
    ... xcatd
    ... postgresql
    Continue? [[Y]es/[N]o/[D]ryrun]:
    Y
    ... ...
    [xCAT] Disabling services from starting on reboot:
    ... goconserver
    ... conserver
    ... ntpd
    ... dhcpd
    ... named
    ... xcatd
    ... postgresql
    Continue? [[Y]es/[N]o/[D]ryrun]:
    Y

Configure Virtual IP
````````````````````

Existing xCAT management node IP should be configured as Virtual IP address, the Virtual IP address should be non-persistent, it needs to be re-configured right after the management node is rebooted. This non-persistent Virtual IP address is designed to avoid ip address conflict when the original primary management node is recovered with this Virtual IP address configured. Since the Virtual IP is non-persistent, the network interface should have a persistent IP address.

#. Configure another IP on primary management node for network interface as static IP, for example, ``10.5.106.70``:

    #. Configure ``10.5.106.70`` as static IP::

        ip addr add 10.5.106.70/8 dev eth0

    #. Edit ``ifcfg-eth0`` file as::

        DEVICE="eth0"
        BOOTPROTO="static"
        NETMASK="255.0.0.0"
        IPADDR="10.5.106.70"
        ONBOOT="yes"

    #. If want to take new static ip effect immediately, login ``xcatmn1`` using ``10.5.106.70``, and restart network service, then add original static IP on primary management node ``10.5.106.7`` as Virtual IP ::

        ssh 10.5.106.70 -l root
        service network restart
        ip addr add 10.5.106.7/8  brd + dev eth0 label eth0:0

#. Add ``10.5.106.70`` into ``postgresql`` configuration file on primary management node

    #. Add ``10.5.106.70`` into ``/var/lib/pgsql/data/pg_hba.conf``::

        host    all          all        10.5.106.7/32      md5

    #. Add ``10.5.106.70`` into ``listen_addresses`` variable in ``/var/lib/pgsql/data/postgresql.conf``::

        listen_addresses = 'localhost,10.5.106.7,10.5.106.70'

#. Modify provision network entry ``mgtifname`` as ``eth0:0`` on primary management node::

    tabedit networks
    "10_0_0_0-255_0_0_0","10.0.0.0","255.0.0.0","eth0:0","10.0.0.103",,"<xcatmaster>",,,,,,,,,,,"1500",,

Configure Shared Data
`````````````````````

The following xCAT directory structure should be accessible from primary xCAT management node::

    /etc/xcat
    /install
    ~/.xcat
    /var/lib/pgsql
    /tftpboot

Synchronize ``/etc/hosts``
``````````````````````````

Since the ``/etc/hosts`` is used by xCAT commands, the ``/etc/hosts`` should be synchronized between the primary management node and bakup management node.

Synchronize Clock
`````````````````

It is recommended that the clocks are synchrinized between the primary management node and bakup management node.

Activate Primary xCAT Management Node
`````````````````````````````````````

Use ``xcatha.py`` interactive activate ``xcatmn1``::

    ./xcatha.py -a
    [Admin] Verify VIP 10.5.106.7 is configured on this node
    Continue? [[Y]es/[N]o]:
    Y
    [Admin] Verify that the following is configured to be saved in shared storage and accessible from this node:
    ... /install
    ... /etc/xcat
    ... /root/.xcat
    ... /var/lib/pgsql
    ... /tftpboot
    Continue? [[Y]es/[N]o]:
    Y
    [xCAT] Starting up services:
    ... postgresql
    ... xcatd
    ... named
    ... dhcpd
    ... ntpd
    ... conserver
    ... goconserver
    Continue? [[Y]es/[N]o/[D]ryrun]:
    Y
    2018-06-24 22:13:09,428 - INFO - ===> Start all services stage <===
    2018-06-24 22:13:10,559 - DEBUG - systemctl start postgresql [Passed]
    2018-06-24 22:13:13,298 - DEBUG - systemctl start xcatd [Passed]
        domain=cluster.com
    2018-06-24 22:13:13,715 - DEBUG - lsdef -t site -i domain|grep domain [Passed]
    Handling bybc0607 in /etc/hosts.
    Handling localhost in /etc/hosts.
    Handling bybc0609 in /etc/hosts.
    Handling localhost in /etc/hosts.
    Getting reverse zones, this may take several minutes for a large cluster.
    Completed getting reverse zones.
    Updating zones.
    Completed updating zones.
    Restarting named
    Restarting named complete
    Updating DNS records, this may take several minutes for a large cluster.
    Completed updating DNS records.
    DNS setup is completed
    2018-06-24 22:13:17,320 - DEBUG - makedns -n [Passed]
    Renamed existing dhcp configuration file to  /etc/dhcp/dhcpd.conf.xcatbak

    Warning: No dynamic range specified for 10.0.0.0. If hardware discovery is being used, a dynamic range is required.
    2018-06-24 22:13:17,811 - DEBUG - makedhcp -n [Passed]
    2018-06-24 22:13:18,746 - DEBUG - makedhcp -a [Passed]
    2018-06-24 22:13:18,800 - DEBUG - systemctl start ntpd [Passed]
    2018-06-24 22:13:19,353 - DEBUG - makeconservercf [Passed]
    2018-06-24 22:13:19,449 - DEBUG - systemctl start conserver [Passed]

Activate Backup xCAT Management Node to be Primary Management Node
==================================================================

#. Install xCAT on backup xCAT management node ``xcatmn2`` with local disk

#. Switch to ``PostgreSQL`` database

#. Disable and deactivate services using ``xcatha.py -d`` on both ``xcatmn2`` and ``xcatmn1``

#. Remove Virtual IP from primary xCAT Management Node ``xcatmn1``::

    ip addr del 10.5.106.7/8 dev eth0:0

#. Configure Virtual IP on ``xcatmn2``

#. Add Virtual IP into ``/etc/hosts`` file ::

    10.5.106.7 xcatmn1 xcatmn1.cluster.com

#. Connect the following xCAT directories to shared data on ``xcatmn2``::

    /etc/xcat
    /install
    ~/.xcat
    /var/lib/pgsql
    /tftpboot

#. Add static management node network interface IP ``10.5.106.5`` into ``PostgreSQL`` configuration file

    #. Add ``10.5.106.5`` into ``/var/lib/pgsql/data/pg_hba.conf``::

        host    all          all        10.5.106.5/32      md5

    #. Add ``10.5.106.5`` into ``listen_addresses`` variable in ``/var/lib/pgsql/data/postgresql.conf``::

        listen_addresses = 'localhost,10.5.106.7,10.5.106.70,10.5.105.5'

#. Use ``xcatha.py -a`` to start all related services on ``xcatmn2``

#. Modify provision network entry ``mgtifname`` as ``eth0:0``::

    tabedit networks
    "10_0_0_0-255_0_0_0","10.0.0.0","255.0.0.0","eth0:0","10.0.0.103",,"<xcatmaster>",,,,,,,,,,,"1500",,

Unplanned failover: primary xCAT management node is not accessible
``````````````````````````````````````````````````````````````````
If primary xCAT management node becomes not accessible before being deactivated and backup xCAT management node is activated, it is recommended that the primary node is disconnected from the network before being rebooted. This will ensure that when services are started on reboot, they do not interfere with the same services running on the backup xCAT management node.
