.. _ha_mgmt_node_with_shared_data:

Prerequisite
============

User has xCAT management node ``xcatmn1`` with ``postgresql`` database, and there are production data in this management node. The xCAT management IP is ``10.5.106.7`` on ``eth0``. It can be the primary MN. User prepare another node ``xcatmn2`` with IP ``10.5.106.5`` on ``eth0``. 

Configure xCAT Primary Management Node
======================================

Export Cluster Data
```````````````````

Use ``xcat-inventory`` to export the cluster data and save as ``xcatmn1.yaml``. This data file can be used to compare with that data from standby MN node ::

    xcat-inventory export --format yaml -f /tmp/xcatmn1.yaml

Disable And Stop All Related Services
`````````````````````````````````````

Before configure VIP and shared data, make sure stop related services. Since primary MN node may break down at any time, all related services should be configured disable from auto starting at boot time.

Use ``xcatha.py -d`` interactive mode to disable and stop all related services: ::

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

Configure VIP
`````````````

The xCAT management IP should be configured as Virtual IP address, the Virtual IP address can be any unused ip address that all the compute nodes and service nodes could reach. The Virtual IP address should be non-persistent, it needs to be re-configured right after the management node is rebooted. This non-persistent Virtual IP address is designed to avoid ip address conflict when the crashed previous primary management is recovered with the Virtual IP address configured. Since the VIP is non-persistent, the network interface should have a persistent IP address. 

#. Configure another IP for network interface as static IP, for example, ``10.5.106.70``:

    #. Configure ``10.5.106.70`` as static ip::

        ip addr add 10.5.106.70/8 dev eth0
  
    #. Edit ``ifcfg-eth0`` file as::

        DEVICE="eth0"
        BOOTPROTO="static"
        NETMASK="255.0.0.0"
        IPADDR="10.5.106.70"
        ONBOOT="yes"

    #. If want to take new static ip effect immediately, login ``xcatmn1`` using ``10.5.106.70``, and restart network service, then add original IP ``10.5.106.7`` as VIP ::

        ssh 10.5.106.70 -l root
        service network restart
        ip addr add 10.5.106.7/8  brd + dev eth0 label eth0:0

#. Add ``10.5.106.70`` into ``postgresql`` configuration file

    #. Add ``10.5.106.70`` into ``/var/lib/pgsql/data/pg_hba.conf``::

        host    all          all        10.5.106.7/32      md5 

    #. Add ``10.5.106.70`` into ``listen_addresses`` variable in ``/var/lib/pgsql/data/postgresql.conf``:: 

        listen_addresses = 'localhost,10.5.106.7,10.5.106.70'

#. Modify provision network entry ``mgtifname`` as ``eth0:0``::
    
    tabedit networks
    "10_0_0_0-255_0_0_0","10.0.0.0","255.0.0.0","eth0:0","10.0.0.103",,"<xcatmaster>",,,,,,,,,,,"1500",, 

Configure Shared Data
`````````````````````

The following xCAT directory structure should be on the shared data::

    /etc/xcat
    /install
    ~/.xcat
    /var/lib/pgsql
    /tftpboot

If some directories are not in shared data, make these directories in shared data, take ``/etc/xcat``, ``/var/lib/pgsql`` and ``/tftpboot`` as an example, ``/HA`` is original shared data directory: ::

    cp -r /etc/xcat /HA/
    cp -r /tftpboot /HA/
    cp -r /var/lib/pgsql /HA/
    mv /etc/xcat /etc/xcat.bak
    mv /tftpboot /tftpboot.bak
    mv /var/lib/pgsql /HA/
    ln -s /HA/xcat /etc/xcat
    ln -s /HA/tftpboot /tftpboot
    ln -s /HA/pgsql /var/lib/pgsql
    chown -R postgres:postgres pgsql

Activate Primary MN
```````````````````
Use ``xcatha.py -a`` to start all related services: ::

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

synchronize ``/etc/hosts``
``````````````````````````

Since the ``/etc/hosts`` is very important for xCAT commands, the ``/etc/hosts`` will be synchronized between the primary management node and standby management node. Here is an example of the crontab entries for synchronizing the /etc/hosts::

    0 2 * * * /usr/bin/rsync -Lprogtz /etc/hosts xcatmn2:/etc/

Verification
````````````

#. Run ``xcatprobe xcatmn`` to find no fatal error. 
#. Provision an existed compute node like ``cn1`` successfully.

Setup And Configure xCAT Standby Management Node
================================================

Setup Standby Management Node
`````````````````````````````

Install xCAT on ``xcatmn2`` refer to :ref:`Installation Guide for Red Hat Enterprise Linux <rhel_install_guide>` 

Switch to ``PostgreSQL`` refer to :ref:`postgresql_reference_label`

Configure Hostname
``````````````````

#. Add VIP into ``/etc/hosts`` file ::

    10.5.106.7 xcatmn1 xcatmn1.cluster.com

Synchronize Clock
`````````````````

Synchronize the clock the same with primary MN ``xcatmn1``, if ``xcatmn1`` use NTP server ``10.0.0.103``, add the following line in ``/etc/ntp.conf`` on ``xcatmn2``::

    server 10.0.0.103
 
Manually synchronize clock::
  
    ntpdate -u 10.0.0.103

Deactivate the Standby Management Node
``````````````````````````````````````

Run ``xcatha.py -d`` to deactivate the MN ``xcatmn2``

Failover
========
There are two kinds of failover, planned failover and unplanned failover. In a planned failover, you can do necessary cleanup work on the previous primary management node before failover to the previous standby management node. In a unplanned failover, the previous management node probably is not functioning at all, you can simply shutdown the system.

Planned failover: active xCAT MN xcatmn1 has problems, but OS is still accessible
`````````````````````````````````````````````````````````````````````````````````

Deactivate Primary MN
'''''''''''''''''''''

    #. Use ``xcatha.py -d`` to deactivate the primary MN
    #. Remove VIP from primary MN ::

        ip addr del 10.5.106.7/8 dev eth0:0

Activate Standby MN
'''''''''''''''''''

    #. Configure VIP refer to `Configure VIP`_
    #. Configure shared data refer to `Configure Shared Data`_
    #. Add standby MN network interface IP ``10.5.106.5`` into ``PostgreSQL`` configuration file

        #. Add ``10.5.106.5`` into ``/var/lib/pgsql/data/pg_hba.conf``::

            host    all          all        10.5.106.5/32      md5

        #. Add ``10.5.106.5`` into ``listen_addresses`` variable in ``/var/lib/pgsql/data/postgresql.conf``::

            listen_addresses = 'localhost,10.5.106.7,10.5.106.70,10.5.105.5'

    #. Use ``xcatha.py -a`` to activate the standby MN
    #. Modify provision network entry ``mgtifname`` as ``eth0:0``::

        tabedit networks
        "10_0_0_0-255_0_0_0","10.0.0.0","255.0.0.0","eth0:0","10.0.0.103",,"<xcatmaster>",,,,,,,,,,,"1500",,


Unplanned failover: active xCAT MN xcatmn1 is not accessible
````````````````````````````````````````````````````````````

Reboot this xCAT MN node ``xcatmn1``, after it boots:

#. If we can access to its OS, we can execute a planned failover, the steps are the same with above `Planned failover: active xCAT MN xcatmn1 has problems, but OS is still accessible`_.

#. If we cannot access to xcatmn1 OS

    #. Activate Standby MN ``xcatmn2`` as `Activate Standby MN`_ 
    #. Recommend recover ``xcatmn1``

Verification on new active MN
`````````````````````````````

#. Check Data consistent

    #. Use ``xcat-inventory`` to export ``xcatmn2`` cluster data::

        xcat-inventory export --format yaml -f /tmp/xcatmn2.yaml

    #. Make diff::

        diff xcatmn1.yaml xcatmn2.yaml 

#. Run ``xcatprobe xcatmn -i eth0:0`` to find no fatal error

#. Provision an existed compute node like ``cn1`` successfully.
