Configuration for Diskless Installation
=======================================

1. Specify dependence package **[required for RHEL and SLES]**

  a) Copy a correct pkglist file **shipped by xCAT** according your environment to the ``/install/custom/netboot/<ostype>/`` directory ::

	cp /opt/xcat/share/xcat/netboot/<ostype>/compute.<osver>.<arch>.pkglist \
         /install/custom/netboot/<ostype>/compute.<osver>.<arch>.pkglist

  b) Edit your ``/install/custom/netboot/<ostype>/<profile>.pkglist`` and add one line ``#INCLUDE:/opt/xcat/share/xcat/ib/netboot/<ostype>/ib.<osver>.<arch>.pkglist#``

    Take RHEL 6.4 on x86_64 for example ::

        cp /opt/xcat/share/xcat/netboot/rh/compute.rhels6.x86_64.pkglist \
        /install/custom/netboot/rh/compute.rhels6.x86_64.pkglist
 
    Edit the ``/install/custom/netboot/rh/compute.rhels6.x86_64.pkglist`` and add below line   
    ``#INCLUDE:/opt/xcat/share/xcat/ib/netboot/rh/ib.rhels6.x86_64.pkglist#`` 
  
    Then ``/install/custom/netboot/rh/compute.rhels6.x86_64.pkglist`` looks like below ::

        #INCLUDE:/opt/xcat/share/xcat/ib/netboot/rh/ib.rhels6.x86_64.pkglist#
        bash 
        nfs-utils
        openssl
        dhclient 
        .....


2. Prepare postinstall scripts 

  a) Specify postinstall script **shipped by xCAT** ::
 
	mkdir -p /install/custom/netboot/<ostype>/
	
	cp /opt/xcat/share/xcat/netboot/<ostype>/<profile>.postinstall \
	  /install/custom/netboot/<ostype>/
	  
	chmod +x /install/custom/netboot/<ostype>/<profile>.postinstall

    Take RHEL 6.4 on x86_64 for example ::
	
        mkdir -p /install/custom/netboot/rh/
        cp /opt/xcat/share/xcat/netboot/rh/compute.rhels6.x86_64.postinstall \
	       /install/custom/netboot/rh/
        chmod +x /install/custom/netboot/rh/compute.rhels6.x86_64.postinstall
		
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
