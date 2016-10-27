.. include:: ../../common/discover/switch_discovery.rst

For switch based hardware discovery, the servers are identified through the switches and switchposts they are directly connected to. 

.. include:: schedule_environment.rst

Switch info::

    Switch name: switch1
    Switch username: xcat
    Switch password: passw0rd
    Switch IP Address: 10.0.201.1
    Switch port for Compute Node: port0

.. _Setup-dhcp:

.. include:: config_environment.rst

Predefined Nodes
----------------

In order to differentiate one node from another, the admin needs to predefine node in xCAT database based on the switches information. This consists of two parts:

#. :ref:`Predefine Switches <predefined_switches_label>`
#. :ref:`Predefine Server Node <predefined_server_nodes_label>`


.. _predefined_switches_label:

Predefine Switches

The predefined switches will represent devices that the physical servers are connected to. xCAT need to access those switches to get server related information through SNMP v3.

So the admin need to make sure those switches are configured correctly with SNMP v3 enabled. <TODO: The document that Configure Ethernet Switches>

Then, define switch info into xCAT::
    
    nodeadd switch1 groups=switch,all
    chdef switch1 ip=10.0.201.1
    tabch switch=switch1 switches.snmpversion=3 switches.username=xcat switches.password=passw0rd switches.auth=sha

Add switch into DNS using the following commands::

    makehosts switch1
    makedns -n

.. _predefined_server_nodes_label:

Predefine Server node

After switches are defined, the server node can be predefined with the following commands::

    nodeadd cn1 groups=powerLE,all
    chdef cn1 mgt=ipmi cons=ipmi ip=10.0.101.1 bmc=50.0.101.1 netboot=petitboot installnic=mac primarynic=mac
    chdef cn1 switch=switch1 switchport=0

In order to do BMC configuration during the discovery process, set ``runcmd=bmcsetup``. ::

    chdef cn1 chain="runcmd=bmcsetup"

Set the target `osimage` into the chain table to automatically provision the operating system after the node discovery is complete. ::

    chdef cn1 -p chain="osimage=<osimage_name>"

For more information about chain, refer to :doc:`Chain <../../../../../advanced/chain/index>` 

Add cn1 into DNS::

    makehosts cn1
    maekdns -n

.. include:: pbmc_discovery_with_bmcdiscover.rst

Verify node definition
----------------------

The following is an example of the server node definition after hardware discovery::


  #lsdef cn1
  Object name: cn1
      arch=ppc64
      bmc=50.0.101.1
      cons=ipmi
      cpucount=192
      cputype=POWER8E (raw), altivec supported
      groups=powerLE,all
      installnic=mac
      ip=10.0.101.1
      mac=6c:ae:8b:02:12:50
      memory=65118MB
      mgt=ipmi
      mtm=8247-22L
      netboot=petitboot
      postbootscripts=otherpkgs
      postscripts=syslog,remoteshell,syncfiles
      primarynic=mac
      serial=10112CA
      supportedarchs=ppc64
      switch=switch1
      switchport=0
