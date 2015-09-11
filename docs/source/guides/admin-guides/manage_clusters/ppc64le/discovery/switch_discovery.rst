.. include:: ../../common/discover/switch_discovery.rst

For switch based hardware discovery, the server are identified though the switches and switchposts they directly connect to. 

The environment scheduling
--------------------------

In this document, we use the following configuration as the example

MN info::

    MN Hostname: xcat1
    MN NIC info for Host network: eth1, 10.0.1.1/16
    MN NIC info for FSP/BMC network: eth2, 50.0.1.1/16
    Dynamic IP range for Hosts: 10.0.100.1-10.0.100.100
    Dynamic IP range for FSP/BMC: 50.0.100.1-50.0.100.100

Switch info::

    Switch name: switch1
    Switch username: xcat
    Switch password: passw0rd
    Switch IP Address: 10.0.201.1

CN info::

    CN Hostname: cn1
    Machine type/model: 8247-22L
    Serial: 10112CA
    Host IP Address: 10.0.101.1
    Host Root Password: cluster
    Desired FSP/BMC IP Address: 50.0.101.1
    DHCP assigned FSP/BMC IP Address: 50.0.100.1
    FSP/BMC username: ADMIN
    FSP/BMC Password: admin
    Switch info: switch1, port0

.. include:: config_environment.rst

Predefine Nodes
---------------

In order to differentiate a node from the other, the admin need to predefine node in xCAT database based on the switches information. So, 2 parts included.

Predefine Switches
``````````````````

The predefined switches will represent devices that the physical servers are connected to. xCAT need to access those switches to get server related information through SNMP v3.

So the admin need to make sure those switches are configured correctly with SNMP v3 enabled. <TD: The document that Configure Ethernet Switches>

Then, define switch info into xCAT::
    
    #nodeadd switch1 groups=switch,all
    #chdef switch1 ip=10.0.201.1
    #tabch switch=switch1 switches.snmpversion=3 switches.username=xcat switches.password=passw0rd switches.auth=sha

After that, add switch into DNS::

    #makehosts switch1
    #makedns -n

Predefine Server node
`````````````````````

After switches are defined, the server node can be predefined as network scheduled::

    #nodeadd cn1 groups=pkvm,all
    #chdef cn1 mgt=ipmi cons=ipmi ip=10.0.101.1 bmc=50.0.101.1 netboot=petitboot installnic=mac primarynic=mac
    #chdef cn1 switch=switch1 switchport=0

Add cn1 into DNS::

    #makehosts cn1
    #maekdns -n

.. include:: pbmc_discovery.rst

The discovered node definition
------------------------------

The server node definition will be like this after hardware discovery process::

  #lsdef cn1
  Object name: cn1
      arch=ppc64
      bmc=50.0.101.1
      cons=ipmi
      cpucount=192
      cputype=POWER8E (raw), altivec supported
      groups=pkvm,all
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
