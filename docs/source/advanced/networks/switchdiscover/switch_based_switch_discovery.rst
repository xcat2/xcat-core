Switch-based Switch Discovery
=============================

Currently, xCAT supports switch based hardware discovery, the servers are identified through the switches and switch ports they are directly connected to.  Use same method, xcat introduced how to discovery switches use switch-based discovery within the user defined dynamic IP range.

Pre-requirement
~~~~~~~~~~~~~~~

In order to do switch-based switch discovery, the admin 

1.  Needs to manually setup and configure core-switch, SNMP v3 needs to be enabled in order for xCAT access to it. Example of core-switch definition:   

::

    lsdef switch-10-5-23-1
      Object name: switch-10-5-23-1
      groups=switch
      ip=10.5.23.1
      mac=ab:cd:ef:gh:dc
      mgt=switch
      nodetype=switch
      password=admin
      postbootscripts=otherpkgs
      postscripts=syslog,remoteshell,syncfiles
      protocol=telnet
      snmpauth=sha
      snmppassword=userpassword
      snmpusername=snmpadmin
      snmpversion=3
      switchtype=BNT
      usercomment=IBM
      username=root



2.  Then pre-define all the top-rack switches which connect to core-switch. 

::

    lsdef switch-192-168-5-22
      objtype=node
      groups=switch
      ip=192.168.5.22
      mgt=switch
      nodetype=switch
      switch=switch-10-5-23-1
      switchport=45
      switchtype=BNT


3.  Setup Dynamic ip range to network table for discovery switches to use.


Discover Switches
~~~~~~~~~~~~~~~~~

xCAT supports **switchdiscover** command to discover the switches that are attached to the subnets on xCAT management node.  Please refer http://xcat-docs.readthedocs.io/en/latest/advanced/networks/switchdiscover/switches_discovery.html for more info.  

For the switch-based switch discovery, we add ``–setup`` flag:  ::


    switchdiscover [noderange|--range ip_ranges][-s scan_methods] [--setup]


if ``–setup`` flag is specified, it will process following steps:

1.  Use snmp or nmap scan method to find all the switches in the dynamic ip ranges which specified by ``--range``, the available switches will be store to switch hash table with hostname, switchtype, vendor info and mac address.  


2.  Based on mac address for each switch defined in the hash table, call **find_mac** subroutine.   The **find_mac** subroutine will go thought the switch and switch port and find matched mac address.    

* If discovered switch didn't match to pre-define, it will log the message to indicate ``NO predefined switch matched``.
* If discovered switch matched with one of pre-defined switch, it will update the pre-defined switch with ::

    otherinterface=x.x.x.x (discovered ip)
    state=matched
    switchtype=type of switch
    usercomment=vendor information


3.  after switches matched, will call config files to set up static ip address, hostname and enable the snmpv3.  currently, BNT and Mellanox switches are supported.  The two config files are located in the ** /opt/xcat/share/xcat/scripts/config.BNT** and **/opt/xcat/share/xcat/scripts/config.Mellanox**.  the log message ``the switch type is not support for config`` if switchtype other than BNT and Mellanox.


Configure switches
~~~~~~~~~~~~~~~~~~

The **switchdiscover** command with ``–setup`` options will set up switches with static ip address, change the hostname from predefine switches and enable snmpv3 configuration.  For other switches configuration, please refer http://xcat-docs.readthedocs.io/en/latest/advanced/networks/ethernet_switches/ethernet_switches.html and http://xcat-docs.readthedocs.io/en/latest/advanced/networks/infiniband/switch_configuration.html

These two config files are located in the **/opt/xcat/share/xcat/scripts**.  The **switchdiscover** process will call the config files with ``--all`` option.  User can call this scripts to setup one of options manually. 

1.  **configBNT** is for configure BNT switches. 

::

     ./configBNT --help
     Usage:
       configBNT [-?│-h│--help]
       configBNT [--switches switchnames] [--all]
       configBNT [--switches switchnames] [--ip]
       configBNT [--switches switchnames] [--name ]
       configBNT [--switches switchnames] [--snmp] [--user snmp_user] [--password snmp_password] [--group snmp_group]
       configBNT [--switches switchnames] [--port port] [--vlan vlan]

2.   **configMellanox** is for configure Mellanox switch.   The script will configure ntp service on the switch with xCAT MN  and use rspconfig command to
    * enable ssh
    * enable snmp function on the switch
    * enable the snmp trap
    * set logging destination to xCAT MN

::

    ./configMellanox --help
    Usage:
        configMellonax [-?│-h│--help]
        configMellonax [--switches switchnames] [--all]
        configMellonax [--switches switchnames] [--ip]
        configMellonax [--switches switchnames] [--name]
        configMellonax [--switches switchnames] [--config]


switch status
~~~~~~~~~~~~~

**Matched** --- Discover switch is matched to pre-define switch, otherinterfaces attribute is updated to dhcp ip address, and mac address, switch type and usercomment also updated with vendor information for the predefined switch.

**ip_configed** --- switches are set up to static ip address based on pre-define switch ip address

**hostname_configed** -- switches host name changed based on pre-define switch hostname.

**switch_configed** -- snmpv3 is setup for the switches.  this should be finial status after run ``switchdiscover --setup`` command.

