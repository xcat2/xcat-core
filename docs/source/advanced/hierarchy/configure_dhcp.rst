Configure DHCP
==============

Add the relevant networks into the DHCP configuration, refer to: :ref:`Setup-dhcp`

Add the defined nodes into the DHCP configuration, refer to:
`XCAT_pLinux_Clusters/#configure-dhcp <http://localhost/fake_todo>`_

In the large cluster, the size of dhcp lease file "/var/lib/dhcpd/dhcpd.leases" on the DHCP server will grow over time. At around 100MB in size, the DHCP server will take a long time to respond to DHCP requests from clients and cause DHCP timeouts: ::
 
   ...
   Mar  2 01:59:10 c656ems2 dhcpd: DHCPDISCOVER from 00:0a:f7:73:7d:d0 via eth0
   Mar  2 01:59:10 c656ems2 dhcpd: DHCPOFFER on 9.114.39.101 to 00:0a:f7:73:7d:d0 via eth0
   Mar  2 01:59:10 c656ems2 dhcpd: DHCPREQUEST for 9.114.39.101 (9.114.39.157) from 00:0a:f7:73:7d:d0 via eth0
   Mar  2 01:59:10 c656ems2 dhcpd: DHCPACK on 9.114.39.101 to 00:0a:f7:73:7d:d0 via eth0
   Mar  2 01:59:10 c656ems2 dhcpd: DHCPDECLINE of 9.114.39.101 from 00:0a:f7:73:7d:d0 via eth0: not found
   Mar  2 01:59:10 c656ems2 dhcpd: DHCPDISCOVER from 00:0a:f7:73:7d:d0 via eth0
   Mar  2 01:59:10 c656ems2 dhcpd: DHCPOFFER on 9.114.39.101 to 00:0a:f7:73:7d:d0 via eth0
   Mar  2 01:59:10 c656ems2 dhcpd: DHCPREQUEST for 9.114.39.101 (9.114.39.157) from 00:0a:f7:73:7d:d0 via eth0
   Mar  2 01:59:10 c656ems2 dhcpd: DHCPACK on 9.114.39.101 to 00:0a:f7:73:7d:d0 via eth0
   Mar  2 01:59:10 c656ems2 dhcpd: DHCPDECLINE of 9.114.39.101 from 00:0a:f7:73:7d:d0 via eth0: not found
   Mar  2 01:59:10 c656ems2 dhcpd: DHCPDISCOVER from 00:0a:f7:73:7d:d0 via eth0
   Mar  2 01:59:10 c656ems2 dhcpd: DHCPOFFER on 9.114.39.101 to 00:0a:f7:73:7d:d0 via eth0
   Mar  2 01:59:10 c656ems2 dhcpd: DHCPREQUEST for 9.114.39.101 (9.114.39.157) from 00:0a:f7:73:7d:d0 via eth0
   Mar  2 01:59:10 c656ems2 dhcpd: DHCPACK on 9.114.39.101 to 00:0a:f7:73:7d:d0 via eth0
   Mar  2 01:59:10 c656ems2 dhcpd: DHCPDECLINE of 9.114.39.101 from 00:0a:f7:73:7d:d0 via eth0: not found
   ...

The solution is simply to restart the dhcpd service or run ``makedhcp -n``.

