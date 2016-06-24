detect_dhcpd
============

::

    Usage: detect_dhcpd -i interface [-m macaddress] [-t timeout] [-V]

    This command can be used to detect the dhcp server in a network for a specific mac address.
    
    Options:
        -i interface:  The interface which facing the target network.
        -m macaddress: The mac that will be used to detect dhcp server. Recommend to use the real mac
                       of the node that will be netboot. If no specified, the mac of interface which 
                       specified by -i will be used.
        -t timeout:    The time to wait to detect the dhcp messages. The default value is 10s.
    
Author:  Wang, Xiao Peng
