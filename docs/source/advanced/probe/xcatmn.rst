xcatmn
======

**xcatmn** can be used to check if xcat has been installed correctly and is ready for use.

**Note**: For several check items(eg. tftp service, dns service, http service), 'tftp', 'nslookup' and 'wget' are need. If not installed, a warning message will be displayed..

Command is as below ::

    xcatprobe xcatmn -i <install_nic> [-V]

* **-i**: [Required] Specify the network interface name of provision network on management node.
* **-V**: Output more information for debug.

For example, run command on Management Node ::

    xcatprobe xcatmn -i eth0

Output will be similar to: ::

    # xcatprobe xcatmn -i eth0
    [MN]: Sub process 'xcatd: SSL listener' is running                                                                [ OK ]
    [MN]: Sub process 'xcatd: DB Access' is running                                                                   [ OK ]
    [MN]: Sub process 'xcatd: UDP listener' is running                                                                [ OK ]
    [MN]: Sub process 'xcatd: install monitor' is running                                                             [ OK ]
    [MN]: Sub process 'xcatd: Discovery worker' is running                                                            [ OK ]
    [MN]: Sub process 'xcatd: Command log writer' is running                                                          [ OK ]
    [MN]: xcatd is listening on port 3001                                                                             [ OK ]
    [MN]: xcatd is listening on port 3002                                                                             [ OK ]
    [MN]: 'lsxcatd -a' works                                                                                          [ OK ]
    [MN]: The value of 'master' in 'site' table is an IP address                                                      [ OK ]
    [MN]: NIC enp0s1 exists on current server                                                                         [ OK ]
    [MN]: Get IP address of NIC eth0                                                                                  [ OK ]
    [MN]: The IP *.*.*.* of eth0 equals the value of 'master' in 'site' table                                         [ OK ]
    [MN]: IP *.*.*.* of NIC eth0 is a static IP on current server                                                     [ OK ]
    [MN]: *.*.*.* belongs to one of networks defined in 'networks' table                                              [ OK ]
    [MN]: There is domain definition in 'site' table                                                                  [ OK ]
    [MN]: There is a configuration in 'passwd' table for 'system' for node provisioning                               [ OK ]
    [MN]: There is /install directory on current server                                                               [ OK ]
    [MN]: There is /tftpboot directory on current server                                                              [ OK ]
    [MN]: The free space of '/' is less than 12 G                                                                     [ OK ]
    [MN]: SELinux is disabled on current server                                                                       [ OK ]
    [MN]: Firewall is closed on current server                                                                        [ OK ]
    [MN]: HTTP service is ready on *.*.*.*                                                                            [ OK ]
    [MN]: TFTP service is ready on *.*.*.*                                                                            [ OK ]
    [MN]: DNS server is ready on *.*.*.*                                                                              [ OK ]
    [MN]: The size of /var/lib/dhcpd/dhcpd.leases is less than 100M                                                   [ OK ]
    [MN]: DHCP service is ready on *.*.*.*                                                                            [ OK ]
    ======================do summary=====================
    [MN]: Check on MN PASS.                                                                                           [ OK ]

**[MN]** means that the verification is performed on the Management Node. Overall status of ``PASS`` or ``FAILED`` will be displayed after all items are verified..

Service Nodes are checked automatically for hierarchical clusters.

For Service Nodes, the output will contain ``[SN:nodename]`` to distinguish different Service Nodes.
