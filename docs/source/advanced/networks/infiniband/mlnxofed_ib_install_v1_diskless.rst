Configuration for Diskless Installation
=======================================

1. Specify dependence package **[required for RHEL and SLES]**

  a) Copy the pkglist to the custom directory ::

	cp /opt/xcat/share/xcat/netboot/<ostype>/compute.<osver>.<arch>.pkglist \
         /install/custom/netboot/<ostype>/compute.<osver>.<arch>.pkglist

  b) Edit your ``/install/custom/netboot/<ostype>/<profile>.pkglist`` and add one line ``#INCLUDE:/opt/xcat/share/xcat/ib/netboot/<ostype>/ib.<osver>.<arch>.pkglist#``

2. Prepare postinstall scripts 

  a) Specify postinstall scripts::
 
	mkdir -p /install/custom/netboot/<ostype>/
	
	cp /opt/xcat/share/xcat/netboot/<ostype>/<profile>.postinstall \
	  /install/custom/netboot/<ostype>/
	  
	chmod +x /install/custom/netboot/<ostype>/<profile>.postinstall

  b) Edit ``/install/custom/netboot/<ostype>/<profile>.postinstall`` and add below line in the end: ::

	installroot=$1 ofeddir=/install/post/otherpkgs/<osver>/<arch>/ofed/  \
	NODESETSTATE=genimage mlnxofed_options=--force /install/postscripts/mlnxofed_ib_install


3. Set the related osimage use the customized pkglist and customized compute.postinsall

* [RHEL/SLES] ::

	chdef  -t osimage -o <osver>-<arch>-netboot-compute \
		pkglist=/install/custom/netboot/<ostype>/compute.<osver>.<arch>.pkglist \
		postinstall=/install/custom/netboot/<ostype>/<profile>.postinstall

* [Ubuntu] ::

	chdef  -t osimage -o <osver>-<arch>-netboot-compute \
		postinstall=/install/custom/netboot/<ostype>/<profile>.postinstall

4. Generate and package image for diskless installation ::

	genimage   <osver>-<arch>-netboot-compute 
	packimage  <osver>-<arch>-netboot-compute

5. Install node ::

	nodeset <nodename> osimage=<osver>-<arch>-netboot-compute 
	rsetboot <nodename> net
	rpower <nodename> reset
