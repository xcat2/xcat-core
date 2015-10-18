IB Network Configuration
========================

xCAT provides a script ``configib`` to help configure the Infiniband adapters on the compute nodes.

The Infiniband adapter is considered an additional interface for xCAT. The process for configuring Infiniband adapters complies with the process  of :doc:`Configure Additional Network Interfaces <../../../../guides/admin-guides/manage_clusters/ppc64le/diskful/customize_image/cfg_second_adapter>`.

Below are an simple example to configure Mellanox IB in Ubuntu 14.04.1 on Power8 LE

If your target Mellanox IB adapter has 2 ports, and you plan to give port ib0 4 different IPs, 2 are IPV4 (20.0.0.3 and 30.0.0.3) and another 2 are IPV6 (1:2::3 and 2:2::3).

1. Define your networks in networks table ::

	chdef -t network -o ib0ipv41 net=20.0.0.0 mask=255.255.255.0 mgtifname=ib0 
	chdef -t network -o ib0ipv42 net=30.0.0.0 mask=255.255.255.0 mgtifname=ib0
	chdef -t network -o ib0ipv61 net=1:2::/64 mask=/64 mgtifname=ib0 gateway=1:2::2
	chdef -t network -o ib0ipv62 net=2:2::/64 mask=/64 mgtifname=ib0 gateway=

2. Define IPs for ib0 ::

	chdef <node> nicips.ib0="20.0.0.3|30.0.0.3|1:2::3|2:2::3"  \
	nicnetworks.ib0="ib0ipv41|ib0ipv42|ib0ipv61|ib0ipv62" nictypes.ib0="Infiniband"

3. Configure ib0

* To configure during node installation ::

	chdef <node> -p postscripts="confignics --ibaports=2"
	nodeset <node> osimage=<osimagename>
	rsetboot <node> net
	rpower <node> reset

* To configure on a node which has had operating system  ::

	updatenode <node> -P "confignics --ibaports=2"

