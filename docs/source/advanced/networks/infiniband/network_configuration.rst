IB Network Configuration
========================

XCAT provided two sample postscripts - configiba.1port and configiba.2ports to configure the IB adapter before XCAT 2.8, these tow scripts still work **but will be in maintenance mode**. 

A new postscript ``/install/postscripts/configib`` is shipped with XCAT 2.8, the ``configib`` postscript works with the new "nics" table and ``confignic`` postscript which is introduced in XCAT 2.8 also. XCAT recommends you to use new ``configib`` script from now on.

IB Interface is a kind of additional adapters for XCAT, so the process of configuring Mellanox IB interface complies with the process of :doc:`Configure Additional Network Interfaces <../../../../guides/admin-guides/manage_clusters/ppc64le/diskful/customize_image/cfg_second_adapter>`.

Below are an simple example to configure Mellanox IB in ubuntu14.4.1 on p8le

If your target Mellanox IB adapter has 2 ports, and you plan to give port ib0 4 different IPs, 2 are IPV4 (20.0.0.3 and 30.0.0.3) and another 2 are IPV6 (1:2::3 and 2:2::3).

1. Define your networks in networks table ::

	chdef -t network -o ib0ipv41 net=20.0.0.0 mask=255.255.255.0 mgtifname=ib0 
	chdef -t network -o ib0ipv42 net=30.0.0.0 mask=255.255.255.0 mgtifname=ib0
	chdef -t network -o ib0ipv61 net=1:2::/64 mask=/64 mgtifname=ib0 gateway=1:2::2
	chdef -t network -o ib0ipv62 net=2:2::/64 mask=/64 mgtifname=ib0 gateway=

2. Define IPs for ib0 ::

	chdef <node> nicips.ib0="20.0.0.3|30.0.0.3|1:2::3|2:2::3" nicnetworks.ib0="ib0ipv41|ib0ipv42|ib0ipv61|ib0ipv62" nictypes.ib0="Infiniband"

3. Configure ib0

Configure during node installation ::

	chdef <node> -p postscripts="confignics --ibaports=2"
	nodeset <node> osimage=<osimagename>
	rsetboot <node> net
	rpower <node> reset

Configure on a node which has have operating system  ::

	updatenode <node> -P "confignics --ibaports=2"

