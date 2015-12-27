Configuration for Diskless Installation
=======================================

1. Specify dependence package **[required for RHEL and SLES]**

  a) Copy a correct pkglist file **shipped by xCAT** according your environment to the ``/install/custom/netboot/<ostype>/`` directory ::

	cp /opt/xcat/share/xcat/netboot/<ostype>/compute.<osver>.<arch>.pkglist \
	   /install/custom/netboot/<ostype>/compute.<osver>.<arch>.pkglist

  b) Edit your ``/install/custom/netboot/<ostype>/<profile>.pkglist`` and add below line
    ``#INCLUDE:/opt/xcat/share/xcat/ib/netboot/<ostype>/ib.<osver>.<arch>.pkglist#``

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

  a) Specify a correct postinstall script **shipped by xCAT** ::
  
	mkdir -p /install/custom/netboot/<ostype>/
	
	cp /opt/xcat/share/xcat/netboot/<ostype>/<profile>.postinstall \
	   /install/custom/netboot/<ostype>/
	   
	chmod +x /install/custom/netboot/<ostype>/<profile>.postinstall

    Take RHEL 6.4 on x86_64 for example ::
	
        mkdir -p /install/custom/netboot/rh/
        cp /opt/xcat/share/xcat/netboot/rh/compute.rhels6.x86_64.postinstall \
	       /install/custom/netboot/rh/
        chmod +x /install/custom/netboot/rh/compute.rhels6.x86_64.postinstall
		
  b) Edit ``/install/custom/netboot/<ostype>/<profile>.postinstall`` and add below line in the end ::

        /install/postscripts/mlnxofed_ib_install \
        -p /install/<path>/<MLNX_OFED_LINUX.iso> -i $1 -n genimage


    **[Note]** If you want to customized kernel version (i.e the kernel version of the diskless image you want to generate is different with the kernel version of you management node), you need to pass ``--add-kernel-support`` attribute to Mellanox. the line added into ``<profile>.postinstall`` should like below ::
  
        /install/postscripts/mlnxofed_ib_install \
        -p /install/<path>/<MLNX_OFED_LINUX.iso> -m --add-kernel-support -end- -i $1 -n genimage
  
    Below steps maybe helpful for you to do judgment if you belong to this situation.
  
    Get the kernel version of your management node ::
  
        uname -r
  
    Get the kernel version of target image. take generating a diskless image of rhels7.0 on x86_64 for example ::
  
        [root@server]# lsdef -t osimage rhels7.0-x86_64-install-compute  -i pkgdir
        Object name: rhels7.0-x86_64-install-compute
        pkgdir=/install/rhels7.0/x86_64

        [root@server]#  ls -l /install/rhels7.0/x86_64/Packages/ |grep kernel*
        .......
        -r--r--r-- 1 root root 30264588 May  5  2014 kernel-3.10.0-123.el7.x86_64.rpm
        .......
		
3. Set the related osimage using the customized pkglist and compute.postinsall

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

  After installation, you can login target ndoe and issue ``ibstat`` command to verify if your IB driver works well. if everything is fine, you can get the IB apater information ::
	
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
