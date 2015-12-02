Configuration for Diskful Installation
=======================================

1. Set script ``mlnxofed_ib_install`` as postbootscript ::

	chdef <node> -p postbootscripts="mlnxofed_ib_install -p /install/<path>/<MLNX_OFED_LINUX.iso>" 
	
2. Specify dependence package **[required for RHEL and SLES]**

  a) Copy a correct pkglist file **shipped by xCAT**  according your environment to the ``/install/custom/install/<ostype>/`` directory, these pkglist files are located under ``/opt/xcat/share/xcat/install/<ostype>/`` ::

	cp /opt/xcat/share/xcat/install/<ostype>/compute.<osver>.<arch>.pkglist \
	   /install/custom/install/<ostype>/compute.<osver>.<arch>.pkglist

  b) Edit your ``/install/custom/install/<ostype>/compute.<osver>.<arch>.pkglist`` and add one line 
  
   ``#INCLUDE:/opt/xcat/share/xcat/ib/netboot/<ostype>/ib.<osver>.<arch>.pkglist#``
  
   You can check directory ``/opt/xcat/share/xcat/ib/netboot/<ostype>/`` and choose one correct ``ib.<osver>.<arch>.pkglist`` according your environment.
 
	
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

  **[Note]**: Dpending on Mellanox OFED user manual,  if you don't perform firmware updates to network adapter hardware, no need to reboot the machine, just restart the driver by running ``/etc/init.d/openibd``. But in Rhels7.x, after installation, ``openibd`` restart failed if not reboot the machine. so **we strongly recommend reboot note again to avoid unexpected problem in RHELS7.x.** If you perform firmware updates, whatever operating system you used, **don't forget to reboot machine** . 

  After steps above, you can login target ndoe and find the Mellanox IB drives are located under ``/lib/modules/<kernel_version>/extra/mlnx-ofa_kernel``. 

  Issue ``ibstat`` command you can get the IB apater information ::
	
    [root@server ~]# ibstat
    CA 'mlx4_0'
        CA type: MT4099
        Number of ports: 2
        Firmware version: 2.11.500
        Hardware version: 0
        Node GUID: 0x5cf3fc000004ec02
        System image GUID: 0x5cf3fc000004ec05
        Port 1:
                State: Initializing
                Physical state: LinkUp
                Rate: 40 (FDR10)
                Base lid: 0
                LMC: 0
                SM lid: 0
                Capability mask: 0x02594868
                Port GUID: 0x5cf3fc000004ec03
                Link layer: InfiniBand
        Port 2:
                State: Down
                Physical state: Disabled
                Rate: 10
                Base lid: 0
                LMC: 0
                SM lid: 0
                Capability mask: 0x02594868
                Port GUID: 0x5cf3fc000004ec04
                Link layer: InfiniBand
