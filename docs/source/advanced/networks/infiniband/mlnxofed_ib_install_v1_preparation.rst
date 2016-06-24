Preparation
===========

Obtain the Mellanox OFED ISO file from `Mellanox official site <http://www.mellanox.com/page/products_dyn?product_family=26&mtag=linux_sw_drivers>`_  and mount it onto suggested target location on the xCAT MN according your OS and ARCH: ::

    mkdir -p /install/post/otherpkgs/<osver>/<arch>/ofed
	
    mount -o loop MLNX_OFED_LINUX-<packver1>-<packver2>-<osver>-<arch>.iso \
      /install/post/otherpkgs/<osver>/<arch>/ofed

Take sles11 sp1 for x86_64 as an example ::

	mkdir -p /install/post/otherpkgs/sles11.1/x86_64/ofed/
	
	mount -o loop MLNX_OFED_LINUX-1.5.3-3.0.0-sles11sp1-x86_64.iso \
	  /install/post/otherpkgs/sles11.1/x86_64/ofed/

	  
Take Ubuntu14.4.1 for Power8 LE as an example ::

	mkdir -p /install/post/otherpkgs/ubuntu14.04.1/ppc64el/ofed
	
	mount -o loop MLNX_OFED_LINUX-2.3-1.0.1-ubuntu14.04-ppc64le.iso \
	  /install/post/otherpkgs/ubuntu14.04.1/ppc64el/ofed


**[NOTE]** 

* Mellanox provides OFED files with **tarball** and **ISO** two format, but for xCAT, we just support **ISO** format right now. 

Copy Sample script **mlnxofed_ib_install** shipped by xCAT into ``/install/postscripts`` before using, such as ::

	cp /opt/xcat/share/xcat/ib/scripts/Mellanox/mlnxofed_ib_install \
	    /install/postscripts/mlnxofed_ib_install
	
The **mlnxofed_ib_install** invokes a script ``mlnxofedinstall`` shipped by Mellanox OFED ISO. If you want to pass the argument to ``mlnxofedinstall``, you set the argument to the environment variable ``mlnxofed_options`` which could be read by **mlnxofed_ib_install**. For example: PPE requires the 32-bit version of libibverbs, but the default **mlnxofed_ib_install** will remove all the old ib related packages at first including the 32-bit version of libibverbs. In this case, you can set the environment variable ``mlnxofed_options=--force`` when running the **mlnxofed_ib_install**. For diskful, you should put the environment variable ``mlnxofed_options=--force`` in mypostscript.tmpl. myposcript.tmpl is in ``/opt/xcat/share/xcat/templates/mypostscript/`` by default. When customize it, you should copy it into ``/install/postscripts/myposcript.tmpl`` ::

    mlnxofed_options='--force'
    export  mlnxofed_options


	