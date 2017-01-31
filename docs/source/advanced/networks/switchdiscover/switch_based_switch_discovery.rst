Switch-based Switch Discovery
=============================

Currently, xCAT supports switch based hardware discovery, the servers are identified through the switches and switch ports they are directly connected to.  A similar method can be used to discover switches using switch-based discovery within the user defined dynamic IP range. 

Pre-requirement
~~~~~~~~~~~~~~~

In order to do switch-based switch discovery, the admin 

1.  Needs to manually setup and configure core-switch, SNMP v3 needs to be enabled in order for xCAT access to it. **username** and **userpassword** attributes are for the remote login. It can be for **ssh** or **telnet**. If it is for **telnet**, set protocol to “telnet”. If the **username** is blank, the **username** and **password** will be retrieved from the passwd table with “switch” as the key. SNMP attributes will used for SNMPv3 communication.  **nodetype** has to be set to "switch" to differentiate between switch-based node discovery or switch-based switch discovery. Refer to switches table attributes.  Example of core-switch definition:  ::

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

2. Predefine all top-rack switches which connect to core-switch.  The attribute **ip** is static IP address for the switch.  When ``switchdiscover --setup`` command is issued, this IP address will replace dhcp IP address on the switch. **nodetype=switch** needs to be set to differentiate between switch-based node discovery or switch-based switch discovery during discovery process.  the attribute **switch** is hostname of core-switch and **switchport** is the port number in the core-switch that top-rack switch is connected to.  ::

    lsdef switch-192-168-5-22
      objtype=node
      groups=switch
      ip=192.168.5.22
      mgt=switch
      nodetype=switch
      switch=switch-10-5-23-1
      switchport=45
      switchtype=BNT


3.  Add switches to /etc/hosts for hostname lookup and xdsh command.  ::

       makehosts switch-192-168-5-23
       makehosts switch-192-168-5-22


4.  Setup Dynamic IP range in network table for discovered switches to use. ::

      # tabdump networks
      #netname,net,mask,mgtifname,gateway,dhcpserver,tftpserver,nameservers,ntpservers,logservers,dynamicrange,staticrange,staticrangeincrement,nodehostname,ddnsdomain,vlanid,domain,mtu,comments,disable
      "192_168_0_0-255_255_0_0","192.168.0.0","255.255.0.0","enP4p1s0f2","<xcatmaster>",,"192.168.3.29",,,,"192.168.5.150-192.168.5.170",,,,,,,,,


dhcp should be restarted after seting up dynamic IP range.


Discover Switches
~~~~~~~~~~~~~~~~~

xCAT supports **switchdiscover** command to discover the switches that are attached to the subnets on xCAT management node.  Refer to :doc:`/advanced/networks/switchdiscover/switches_discovery` for more info.

For the switch-based switch discovery, we add **–setup** flag:  ::


    switchdiscover [noderange|--range ip_ranges][-s scan_methods] [--setup]


if **--setup** flag is specified, the command will perform following steps:

1.  Use snmp or nmap scan methods to find all switches in the dynamic IP ranges specified by --range, the available switches will be stored in switch hash table with hostname, switchtype, vendor info and mac address.  


2.  Based on mac address for each switch defined in the hash table, call **find_mac** subroutine.   The **find_mac** subroutine will go thought the switch and switch ports and find matched mac address.    

* If discovered switch didn't find any predefined switch matches, it will log the message ``NO predefined switch matched``.
* If discovered switch matched with one of pre-defined switch, it will update the predefined switch with ::

    otherinterface=x.x.x.x (discovered ip)
    state=matched
    switchtype=type of switch
    usercomment=vendor information


3.  After switches are matched, the command will call config files to set up static IP address, hostname and enable the snmpv3.  Currently, BNT and Mellanox switches are supported.  The two config files are located in the **/opt/xcat/share/xcat/scripts/config.BNT** and **/opt/xcat/share/xcat/scripts/config.Mellanox**.  the log message ``the switch type is not support for config`` is displayed if switchtype is something other than BNT or Mellanox.

4.  After discovery process, the predefined node attribute in the xCATdb will be updated. 

::

    lsdef switch-192-168-5-22
       groups=switch
       ip=192.168.5.22
       mac=a8:97:dc:02:92:00
       mgt=switch
       nodetype=switch
       password=admin
       postbootscripts=otherpkgs
       postscripts=syslog,remoteshell,syncfiles
       protocol=telnet
       snmpauth=sha
       snmppassword=xcatadminpassw0rd@snmp
       snmpusername=xcatadmin
       snmpversion=3
       status=hostname_configed
       statustime=08-31-2016 15:35:49
       supportedarchs=ppc64
       switch=switch-10-5-23-1
       switchport=45
       switchtype=BNT
       usercomment=IBM Networking Operating System RackSwitch G8052
       username=root



Configure switches
~~~~~~~~~~~~~~~~~~

The **switchdiscover** command with ``--setup`` flag will set up switches with static IP address, change the hostname from predefine switches and enable snmpv3 configuration.  For other switches configuration, refer to :doc:`/advanced/networks/ethernet_switches/ethernet_switches` and :doc:`/advanced/networks/infiniband/switch_configuration`. 

These two config files are located in the **/opt/xcat/share/xcat/scripts** directory.  The **switchdiscover** process will call the config files with ``--all`` option.  User can call these scripts to setup one of options manually. 

1.  **configBNT** is for configure BNT switches.  ::

     ./configBNT --help
     Usage:
       configBNT [-?│-h│--help]
       configBNT [--switches switchnames] [--all]
       configBNT [--switches switchnames] [--ip]
       configBNT [--switches switchnames] [--name ]
       configBNT [--switches switchnames] [--snmp] [--user snmp_user] [--password snmp_password] [--group snmp_group]
       configBNT [--switches switchnames] [--port port] [--vlan vlan]

2.   **configMellanox** is for configuring Mellanox switch.  The script will configure ntp service on the switch with xCAT MN  and will use rspconfig command to

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


Switch Status
~~~~~~~~~~~~~

During the switch-based switch discovery process, there are four states displayed.  User may only see **switch_configed** status on node definition if discovery process succefully finished.  

**Matched** --- Discovered switch is matched to predefine switch, **otherinterfaces** attribute is updated to dhcp IP address, and mac address, **switch type** and **usercomment** also updated with vendor information for the predefined switch.

**ip_configed** --- switch is set up to static IP address based on predefine switch IP address.  If failure to set up IP address, the status will stay as **Matched**.

**hostname_configed** -- switch host name is changed based on predefine switch hostname. If failure to change hostname on the switch, the status will stay as **ip_configed**.

**switch_configed** -- snmpv3 is setup for the switches.  This should be finial status after running ``switchdiscover --setup`` command. If failure to setup snmpv3,  the status will stay as **hostname_configed**.

