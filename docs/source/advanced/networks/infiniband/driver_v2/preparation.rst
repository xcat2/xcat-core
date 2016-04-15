Preparation
===========

#. Obtain the Mellanox OFED ISO [#]_ file from `Mellanox OpenFabrics Enterprise Distribution for Linux <http://www.mellanox.com/page/products_dyn?product_family=26&mtag=linux_sw_drivers>`_.  

   This example will put the ISO file for 3.2-2.0 into ``/install/ib_mlnxofed/3.2-2.0/``.


#. Copy ``mlnxofed_ib_install.v2`` to ``/install/postscripts`` and rename to ``mlnxofed_ib_install`` ::

    cp /opt/xcat/share/xcat/ib/scripts/Mellanox/mlnxofed_ib_install.v2 \
        /install/postscripts/mlnxofed_ib_install
	   
#. Use the following command to install using defaults: ::

    mlnxofed_ib_install -p /install/ib_mlnxofed/3.2-2.0/MLNX_OFED_LINUX-3.2-2.0.0.0-<os>-<arch>.iso

.. [#] Mellanox provides OFED drivers in *tgz* and *ISO* formats.  xCAT only supports the **ISO** format at this time. 

Advanced Options 
----------------

``mlnxofed_ib_install`` has some options, **'-p' is always needed**.
Below are the details of these options:

* **-p**: [required]--the directory where the OFED iso file is located
* **-m**: [optional]--the mlnxofed_ib_install invokes a script ``mlnxofedinstall`` shipped by Mellanox OFED iso. Use this option to pass arguments to the ``mlnxofedinstall``. You must include ``-end-`` at the completion of the options to distinguish the option list. if you don't pass any argument to ``mlnxofedinstall``, **defualt value** ``--without-32bit --without-fw-update --force`` will be passed to ``mlnxofedinstall`` by xCAT. 
* **-i**: [required for diskless]--the image root path
* **-n**: [required for diskless]--nodeset status, the value is 'genimage'

In general you can use ``mlnxofed_ib_install`` like below ::

    mlnxofed_ib_install -p /install/<path>/<MLNX_OFED_LINUX.iso>
	
If need to pass ``--without-32bit --without-fw-update --add-kernel-support --force`` to ``mlnxofedinstall``, refer to below command ::

    mlnxofed_ib_install -p /install/<path>/<MLNX_OFED_LINUX.iso> \
	-m --without-32bit --without-fw-update --add-kernel-support --force -end- 

