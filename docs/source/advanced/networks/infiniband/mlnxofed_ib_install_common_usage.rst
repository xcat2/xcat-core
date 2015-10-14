.. BEGIN_Preparation_For_V2

Before start, here are some preparation and concept should be known.

Obtain the Mellanox OFED ISO file from `Mellanox official site <http://www.mellanox.com/page/products_dyn?product_family=26&mtag=linux_sw_drivers>`_ and put it under the /install directory following the xCAT directory structure: ``/install/post/otherpkgs/<osver>/<arch>/ofed``.

**[NOTE]** 

* Mellanox provides OFED files with **tarball** and **ISO** two format, but for XCAT, we just support **ISO** format right now. 
* Mellanox provides different OFED ISOs depending on operating system and machine architecture, named like MLNX_OFED_LINUX-<packver1>-<packver2>-<osver>-<arch>.iso, you should download correct one according your environment.

Copy Sample script **mlnxofed_ib_install.v2** into ``/install/postscripts`` and change name to **mlnxofed_ib_install** before using, such as ::

	cp /opt/xcat/share/xcat/ib/scripts/Mellanox/mlnxofed_ib_install.v2 /install/postscripts/mlnxofed_ib_install
	chmod +x /install/postscripts/mlnxofed_ib_install
	
Some options of mlnxofed_ib_install.v2 should be assigned values in the command line argument way when mlnxofed_ib_install.v2 is invoked.
These options are:

* **-ofeddir** : the directory where OFED ISO file is saved. this is the necessary option
* **-ofedname**: the name of OFED ISO file. this is the necessary option 
* **-passmlnxofedoptions**: The mlnxofed_ib_install.v2 invokes a script ``mlnxofedinstall`` shipped by Mellanox OFED iso. Use this option to pass arguments to the ``mlnxofedinstall``. You must include ``-end-`` at the completion of the options to distinguish the option list. if you don't pass any argument to ``mlnxofedinstall``, defualt value ``--without-32bit --without-fw-update --force`` will be passed to ``mlnxofedinstall`` by XCAT. 
* **-installroot**: the image root path. this is necessary attribute in diskless scenario
* **-nodesetstate**: nodeset status, the value is one of 'install', 'boot' and 'genimage'. this is necessary attribute in diskless scenario

For example, if you use MLNX_OFED_LINUX-3.1-1.0.0-ubuntu14.04-ppc64le.iso and save it under ``/install/post/otherpkgs/ubuntu14.04.3/ppc64le/ofed/`` , you want to pass ``--without-32bit --without-fw-update --add-kernel-support --force`` to ``mlnxofedinstall``. you can use like below ::

    mlnxofed_ib_install -ofeddir /install/post/otherpkgs/ubuntu14.04.3/ppc64le/ofed/ -passmlnxofedoptions --without-32bit --without-fw-update --add-kernel-support --force -end- -ofedname MLNX_OFED_LINUX-3.1-1.0.0-ubuntu14.04-ppc64le.iso

.. END_Preparation_For_V2

.. BEGIN_Diskfull_step_For_V2

Let's start configuration.

1. Set script ``mlnxofed_ib_install`` as postbootscript ::

	chdef <node> -p postbootscripts="mlnxofed_ib_install -ofeddir <the path of OFED ISO file> -passmlnxofedoptions <the args passed to mlnx> -end- -ofedname <OFED ISO file name>" 
	
**[Note]** step 2-4 are only needed by RHEL and SLES

2. Copy a correct pkglist file shipped by XCAT according your environment to the ``/install/custom/install/<ostype>/`` directory ::

	cp /opt/xcat/share/xcat/install/<ostype>/compute.<osver>.<arch>.pkglist /install/custom/install/<ostype>/compute.<osver>.<arch>.pkglist

3. Edit your ``/install/custom/install/<ostype>/compute.<osver>.<arch>.pkglist`` and add one line::

	#INCLUDE:/opt/xcat/share/xcat/ib/netboot/<ostype>/ib.<osver>.<arch>.pkglist#

**[NOTE]** You can check directory ``/opt/xcat/share/xcat/ib/netboot/<ostype>/`` and choose one correct ``ib.<osver>.<arch>.pkglist`` according your environment

4. Make sure the related osimage use the customized pkglist ::

	lsdef -t osimage -o <osver>-<arch>-install-compute

If not, change it ::

	chdef -t osimage -o <osver>-<arch>-install-compute  pkglist=/install/custom/install/<ostype>/compute.<osver>.<arch>.pkglist

5. Install node ::

	nodeset <node> osimage=<osver>-<arch>-install-compute
	rsetboot <node> net
	rpower <node> reset

.. END_Diskfull_step_For_V2

.. BEGIN_Diskless_step_For_V2

Let's start configuration.

**[Note]** step 1 is only need by RHEL and SLES

1. Copy a correct pkglist file shipped by XCAT according your environment to the ``/install/custom/netboot/<ostype>/`` directory ::

	cp /opt/xcat/share/xcat/netboot/<ostype>/compute.<osver>.<arch>.pkglist /install/custom/netboot/<ostype>/compute.<osver>.<arch>.pkglist

Edit your ``/install/custom/netboot/<ostype>/<profile>.pkglist`` and add: ::

	#INCLUDE:/opt/xcat/share/xcat/ib/netboot/<ostype>/ib.<osver>.<arch>.pkglist#

Take sles11 sp1 on x86_64 for example, Edit the ``/install/custom/netboot/sles11.1/x86_64/compute/compute.sles11.1.x86_64.pkglist`` and add: ::

	#INCLUDE:/opt/xcat/share/xcat/ib/netboot/sles/ib.sles11.1.x86_64.pkglist#

2. Prepare postinstall scripts ::

	mkdir -p /install/custom/netboot/<ostype>/
	cp /opt/xcat/share/xcat/netboot/<ostype>/<profile>.postinstall /install/custom/netboot/<ostype>/
	chmod +x /install/custom/netboot/<ostype>/<profile>.postinstall
	
Edit ``/install/custom/netboot/<ostype>/<profile>.postinstall`` and add: ::

    /install/postscripts/mlnxofed_ib_install -ofeddir <the path of OFED ISO file> -ofedname <OFED ISO file name> -nodesetstate genimage  -installroot $1
		
3. Set the related osimage using the customized pkglist and compute.postinsall ::

	chdef  -t osimage -o <osver>-<arch>-netboot-compute \
		pkglist=/install/custom/netboot/<ostype>/compute.<osver>.<arch>.pkglist \
		postinstall=/install/custom/netboot/<ostype>/<profile>.postinstall

**[Note]** Ubuntu doesn't need pkglist attribute.

4. Generate and package image for diskless installation ::

	genimage   <osver>-<arch>-netboot-compute 
	packimage  <osver>-<arch>-netboot-compute

5. Install node ::

	nodeset <nodename> osimage=<osver>-<arch>-netboot-compute 
	rsetboot <nodename> net
	rpower <nodename> reset

.. END_Diskless_step_For_V2

.. BEGIN_Preparation_For_V1

Obtain the Mellanox OFED ISO file from `Mellanox official site <http://www.mellanox.com/page/products_dyn?product_family=26&mtag=linux_sw_drivers>`_  and mount it onto suggested target location on the XCAT MN according your OS and ARCH: ::

    mkdir -p /install/post/otherpkgs/<osver>/<arch>/ofed
    mount -o loop MLNX_OFED_LINUX-<packver1>-<packver2>-<osver>-<arch>.iso /install/post/otherpkgs/<osver>/<arch>/ofed

Take sles11 sp1 for x86_64 as an example ::

	mkdir -p /install/post/otherpkgs/sles11.1/x86_64/ofed/
	mount -o loop MLNX_OFED_LINUX-1.5.3-3.0.0-sles11sp1-x86_64.iso /install/post/otherpkgs/sles11.1/x86_64/ofed/
		
Take Ubuntu14.4.1 for p8le as an example ::

	mkdir -p /install/post/otherpkgs/ubuntu14.04.1/ppc64el/ofed
	mount -o loop MLNX_OFED_LINUX-2.3-1.0.1-ubuntu14.04-ppc64le.iso /install/post/otherpkgs/ubuntu14.04.1/ppc64el/ofed

**[NOTE]** 

* Mellanox provides OFED files with **tarball** and **ISO** two format, but for XCAT, we just support **ISO** format right now. 

Copy Sample script **mlnxofed_ib_install** shipped by XCAT into ``/install/postscripts`` before using, such as ::

	cp /opt/xcat/share/xcat/ib/scripts/Mellanox/mlnxofed_ib_install /install/postscripts/mlnxofed_ib_install
	
The **mlnxofed_ib_install** invokes a script ``mlnxofedinstall`` shipped by Mellanox OFED ISO. If you want to pass the argument to ``mlnxofedinstall``, you set the argument to the environment variable ``mlnxofed_options`` which could be read by **mlnxofed_ib_install**. For example: PPE requires the 32-bit version of libibverbs, but the default **mlnxofed_ib_install** will remove all the old ib related packages at first including the 32-bit version of libibverbs. In this case, you can set the environment variable ``mlnxofed_options=--force`` when running the **mlnxofed_ib_install**. For diskfull, you should put the environment variable ``mlnxofed_options=--force`` in mypostscript.tmpl. myposcript.tmpl is in ``/opt/xcat/share/xcat/templates/mypostscript/`` by default. When customize it, you should copy it into ``/install/postscripts/myposcript.tmpl`` ::

	mlnxofed_options='--force'
	export  mlnxofed_options

.. END_Preparation_For_V1

.. BEGIN_Diskfull_step_For_V1

Let's start configuration.

1. Set script ``mlnxofed_ib_install`` as postbootscript ::

	chdef <node> -p postbootscripts=mlnxofed_ib_install
	
**[Note]** step 2-4 are only needed by RHEL and SLES

2. Copy the pkglist to the custom directory ::

	cp /opt/xcat/share/xcat/install/<ostype>/compute.<osver>.<arch>.pkglist /install/custom/install/<ostype>/compute.<osver>.<arch>.pkglist

3. Edit your /install/custom/install/<ostype>/compute.<osver>.<arch>.pkglist and add ::

	#INCLUDE:/opt/xcat/share/xcat/ib/netboot/<ostype>/ib.<osver>.<arch>.pkglist#

4. Make sure the related osimage use the customized pkglist ::

	lsdef -t osimage -o <osver>-<arch>-install-compute

If not, change it ::

	chdef -t osimage -o <osver>-<arch>-install-compute  pkglist=/install/custom/install/<ostype>/compute.<osver>.<arch>.pkglist

5. Install node ::

	nodeset <node> osimage=<osver>-<arch>-install-compute
	rsetboot <node> net
	rpower <node> reset

.. END_Diskfull_step_For_V1

.. BEGIN_Diskless_step_For_V1

Let's start configuration.

**[Note]** step 1 is only need by RHEL and SLES

1. Copy the pkglist to the custom directory ::

	cp /opt/xcat/share/xcat/netboot/<ostype>/compute.<osver>.<arch>.pkglist \
		/install/custom/netboot/<ostype>/compute.<osver>.<arch>.pkglist

Edit your ``/install/custom/netboot/<ostype>/<profile>.pkglist`` and add: ::

	#INCLUDE:/opt/xcat/share/xcat/ib/netboot/<ostype>/ib.<osver>.<arch>.pkglist#

Take sles11 sp1 on x86_64 for example, Edit the ``/install/custom/netboot/sles11.1/x86_64/compute/compute.sles11.1.x86_64.pkglist`` and add: ::

	#INCLUDE:/opt/xcat/share/xcat/ib/netboot/sles/ib.sles11.1.x86_64.pkglist#

2. Prepare postinstall scripts ::

	mkdir -p /install/custom/netboot/<ostype>/
	cp /opt/xcat/share/xcat/netboot/<ostype>/<profile>.postinstall /install/custom/netboot/<ostype>/
	chmod +x /install/custom/netboot/<ostype>/<profile>.postinstall
	
Edit ``/install/custom/netboot/<ostype>/<profile>.postinstall`` and add: ::

    installroot=$1 ofeddir=/install/post/otherpkgs/<osver>/<arch>/ofed/ NODESETSTATE=genimage  mlnxofed_options=--force /install/postscripts/mlnxofed_ib_install
		
3. Set the related osimage use the customized pkglist and customized compute.postinsall ::

	chdef  -t osimage -o <osver>-<arch>-netboot-compute \
		pkglist=/install/custom/netboot/<ostype>/compute.<osver>.<arch>.pkglist \
		postinstall=/install/custom/netboot/<ostype>/<profile>.postinstall

**[Note]** Ubuntu doesn't need pkglist attribute.

4. Generate and package image for diskless installation ::

	genimage   <osver>-<arch>-netboot-compute 
	packimage  <osver>-<arch>-netboot-compute

5. Install node ::

	nodeset <nodename> osimage=<osver>-<arch>-netboot-compute 
	rsetboot <nodename> net
	rpower <nodename> reset

	
.. END_Diskless_step_For_V1