Use Customized Scripts To Configure NIC
---------------------------------------

If using customized script to configure NIC, ``niccustomscripts`` for the specified nic in ``nics`` table should be configured. In the customized scripts, it can use data from xCAT DB, These data are parsed as global value from ``/xcatpost/mypostscript`` in compute node. Here is a simple example :

  #. Compute node ``cn1`` with one physical NIC: ``eth1``
  #. Put customized script ``cfgeth1`` under xCAT MN ``/install/postscripts``
  #. Configure ``niccustomscripts`` in ``nics`` table ::
      chdef cn1 niccustomscripts.eth1=cfgeth1

  #. The script ``cfgeth1`` uses data from xCAT DB, for example, it uses network ``net50`` from ``networks`` table ::

      chdef -t network net50 net=50.0.0.0 mask=255.0.0.0

     **Notes:** The network ``net50`` is parsed as ``NETWORKS_LINE1`` in ``/xcatpost/mypostscript`` as following, so script ``cfgeth1`` can use global value ``NETWORKS_LINE1`` directly ::

      NETWORKS_LINE1='netname=net50||net=50.0.0.0||mask=255.0.0.0||mgtifname=||gateway=||dhcpserver=||tftpserver=||nameservers=||ntpservers=||logservers=||dynamicrange=||staticrange=||staticrangeincrement=||nodehostname=||ddnsdomain=||vlanid=||domain=||disable=||comments='

  #. When ``confignetwork`` is running in ``cn1``, ``confignetwork`` will execute ``cfgeth1`` to configure eth1, so adding ``confignetwork`` into the node's postscripts list. During OS deployment on compute node, ``confignetwork`` postscript will be executed. ::

      chdef cn1 -p postscripts=confignetwork

  #. Or if the compute node is already running, use ``updatenode`` command to run ``confignetwork`` postscript without rebooting the node::

      updatenode cn1 -P confignetwork

  #. Use ``xdsh cn1 "ip addr show eth1"`` to check the NIC

  #. Check ``ifcfg-eth1`` under ``/etc/sysconfig/network-scripts/``

