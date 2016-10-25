Discovering Switches
--------------------

Use switchdiscover command to discover the switches that are attached to the neighboring subnets on xCAT management node. ::

    switchdiscover [noderange|--range ip_ranges][-s scan_methods][-r|-x|-z][-w]

where the scan_methods can be **nmap**, **snmp", or **lldp** . The default is **nmap**. (**nmap** comes from most os distribution.)

To discover switches over the IP range 10.4.25.0/24 and 192.168.0.0/24, use the following command: ::

    # switchdiscover --range 10.4.25.0/24,192.168.0.0/24
    Discovering switches using nmap...
    ip              name                    vendor                  mac
    ------------    ------------            ------------            ------------
    192.168.0.131   switch_192_168_0_131    Mellanox Technologie    00:02:C9:AA:00:53
    10.4.25.1       switch_10_4_25_1        Juniper networks        2C:6B:F5:00:11:22

If -w flag is specified, the command will write the discovered switches into xCAT databases. If the command above was executed with **-w** the following switch objects would be created: ::

    # lsdef switch_name
    Object name: switch_name
    groups=switch
    ip=switch_ip
    mgt=switch
    nodetype=switch
    switchtype=switch_vendor

The **Ip** address is stored in the hosts table. You can run the following command to add the IP addresses in the **/etc/hosts** ::

    makehosts

The discovery process works with the following four kind of switches: ::

    Mellanox (IB and Ethernet switches)
    Cisco
    BNT
    Juniper

The ``switchdiscover`` command can display the output in xml format, stanza forma and normal list format. See the man pages for this command for details.

