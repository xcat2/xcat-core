Configuration for Diskful Installation
======================================

1. Set script ``mlnxofed_ib_install`` as postbootscript ::

	chdef <node> -p postbootscripts=mlnxofed_ib_install
	
2. Specify dependence package **[required for RHEL and SLES]**

  a) Copy the pkglist to the custom directory ::

	cp /opt/xcat/share/xcat/install/<ostype>/compute.<osver>.<arch>.pkglist \
	   /install/custom/install/<ostype>/compute.<osver>.<arch>.pkglist

  b) Edit your /install/custom/install/<ostype>/compute.<osver>.<arch>.pkglist and add one line::

	#INCLUDE:/opt/xcat/share/xcat/ib/netboot/<ostype>/ib.<osver>.<arch>.pkglist#

  c) Make the related osimage use the customized pkglist ::

	chdef -t osimage -o <osver>-<arch>-install-compute  \
	   pkglist=/install/custom/install/<ostype>/compute.<osver>.<arch>.pkglist

    Take RHEL 6.4 on x86_64 for example ::

        cp /opt/xcat/share/xcat/install/rh/compute.rhels6.x86_64.pkglist \
        /install/custom/install/rh/compute.rhels6.x86_64.pkglist
 
    Edit the ``/install/custom/install/rh/compute.rhels6.x86_64.pkglist`` and add below line   
    ``#INCLUDE:/opt/xcat/share/xcat/ib/netboot/rh/ib.rhels6.x86_64.pkglist#`` 
  
    Then ``/install/custom/install/rh/compute.rhels6.x86_64.pkglist`` looks like below ::
  
        #Please make sure there is a space between @ and group name
        #INCLUDE:/opt/xcat/share/xcat/ib/netboot/rh/ib.rhels6.x86_64.pkglist#
        ntp
        nfs-utils
        net-snmp
        rsync
        yp-tools
        openssh-server
        util-linux-ng

    Then modify related osimage ::
  
        chdef -t osimage -o rhels6.4-x86_64-install-compute  \
         pkglist=/install/custom/install/rh/compute.rhels6.x86_64.pkglist
		
3. Install node ::

	nodeset <node> osimage=<osver>-<arch>-install-compute
	rsetboot <node> net
	rpower <node> reset
