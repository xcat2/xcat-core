Preparation
===========

Obtain the Mellanox OFED ISO
----------------------------

Obtain the Mellanox OFED ISO file from `Mellanox official Download Page <http://www.mellanox.com/page/products_dyn?product_family=26&mtag=linux_sw_drivers>`_ and put it into one place under ``/install`` directory depending on your need.

**[NOTE]** 

* Mellanox provides OFED drivers in **tarball** and **ISO image** formats.  xCAT only supports the **iso** format at this time.
* Mellanox provides different OFED ISOs depending on operating system and machine architecture, named like MLNX_OFED_LINUX-<packver1>-<packver2>-<osver>-<arch>.iso, you should download correct one according to your environment.
* Mellanox has some updates and known issues for echo OFED, please read `InfiniBand/VPI Software Overview <http://www.mellanox.com/page/software_overview_ib>`_ to understand these information. 
* The Mellanox links offered above maybe outdate in future for Mellanox updates its web page, xCAT will keep updating for synchronization. If we don't update in time, please access `Mellanox web portal <http://www.mellanox.com>`_ to find ``Support/Education`` then ``InfiniBand/VPI Drivers`` lables.

Prepare Install Script
----------------------

**mlnxofed_ib_install.v2** is a sample script, its framework can help you install Mellanox drives easily. But in specific scenario, some detail need to be modified to meet requirement, such like dependency package list. It has been verified in limited scenarios and can work as solution in these scenarios. For these scenarions information please refer to :doc:`The Scenarios Have Been Verified </advanced/networks/infiniband/mlnxofed_ib_verified_scenario_matrix>`. 

Copy **mlnxofed_ib_install.v2** into ``/install/postscripts`` and change name to **mlnxofed_ib_install** ::

	cp /opt/xcat/share/xcat/ib/scripts/Mellanox/mlnxofed_ib_install.v2 \
	   /install/postscripts/mlnxofed_ib_install
	   
	chmod +x /install/postscripts/mlnxofed_ib_install
	
``mlnxofed_ib_install`` has some options, **'-p' is always needed**.
Below are the details of these options:

* **-p**: [required]--the directory where the OFED iso file is located
* **-m**: [optional]--the mlnxofed_ib_install invokes a script ``mlnxofedinstall`` shipped by Mellanox OFED iso. Use this option to pass arguments to the ``mlnxofedinstall``. You must include ``-end-`` at the completion of the options to distinguish the option list. if you don't pass any argument to ``mlnxofedinstall``, **defualt value** ``--without-32bit --without-fw-update --force`` will be passed to ``mlnxofedinstall`` by xCAT. 
* **-i**: [required for diskless]--the image root path
* **-n**: [required for diskless]--nodeset status, the value is 'genimage'

In general you can use ``mlnxofed_ib_install`` like below ::

    mlnxofed_ib_install -p /install/<path>/<MLNX_OFED_LINUX.iso>
	
If need to pass ``--without-32bit --without-fw-update --add-kernel-support --force`` to ``mlnxofedinstall``, refer to below command. ::

    mlnxofed_ib_install -p /install/<path>/<MLNX_OFED_LINUX.iso> \
	-m --without-32bit --without-fw-update --add-kernel-support --force -end- 

**[Note]** We recommend to update your firmware to the version Mellanox supported in its release notes to avoid unexpected problem when you install InfiniBand driver.

