Configuration for Diskful Installation
=======================================

1. Set script ``mlnxofed_ib_install`` as postbootscript ::

	chdef <node> -p postbootscripts="mlnxofed_ib_install -p /install/<path>/<MLNX_OFED_LINUX.iso>" 
	
2. Specify dependence package **[required for RHEL and SLES]**

  a) Copy a correct pkglist file shipped by xCAT according your environment to the ``/install/custom/install/<ostype>/`` directory ::

	cp /opt/xcat/share/xcat/install/<ostype>/compute.<osver>.<arch>.pkglist \
	   /install/custom/install/<ostype>/compute.<osver>.<arch>.pkglist

  b) Edit your ``/install/custom/install/<ostype>/compute.<osver>.<arch>.pkglist`` and add below line::

	#INCLUDE:/opt/xcat/share/xcat/ib/netboot/<ostype>/ib.<osver>.<arch>.pkglist#

  c) Make the related osimage use the customized pkglist ::

	chdef -t osimage -o <osver>-<arch>-install-compute  \
	    pkglist=/install/custom/install/<ostype>/compute.<osver>.<arch>.pkglist

3. Install node ::

	nodeset <node> osimage=<osver>-<arch>-install-compute
	rsetboot <node> net
	rpower <node> reset
