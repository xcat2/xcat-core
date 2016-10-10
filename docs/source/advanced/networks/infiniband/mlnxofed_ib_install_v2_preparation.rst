Preparation
===========

Download MLNX_OFED ISO
----------------------

**xCAT only supports installation using the ISO format.** 

Download the Mellanox OFED ISO file `here (MLNX_OFED) <http://www.mellanox.com/page/products_dyn?product_family=26&mtag=linux_sw_drivers>`_.


Prepare Installation Script
---------------------------

The ``mlnxofed_ib_install.v2`` is a sample script intended to assist with the installation of the Mellanox OFED drivers.  The following support matrix documents the limited number of scenarios that have been verified: :doc:`support matrix </advanced/networks/infiniband/mlnxofed_ib_verified_scenario_matrix>`.

#. Copy the ``mlnxofed_ib_install.v2`` to ``/install/postscripts``, renaming to ``mlnxofed_ib_install``. ::

       cp /opt/xcat/share/xcat/ib/scripts/Mellanox/mlnxofed_ib_install.v2 \
          /install/postscripts/mlnxofed_ib_install

       # ensure the script has execute permission
       chmod +x /install/postscripts/mlnxofed_ib_install

#. Familarize the options available for the xCAT ``mlnxofed_ib_install`` script. 

   +---------+------------------+----------------------------------------------------------+
   | Option  | Required         | Description                                              |
   +=========+==================+==========================================================+
   |``-p``   | Yes              || The full path to the MLNX_OFED ISO image                |
   +---------+------------------+----------------------------------------------------------+
   |``-m``   | No               || Use this option to pass arguments to the Mellanox OFED  |
   |         |                  || installation script ``mlnxofedinstall``.                |
   |         |                  ||                                                         |
   |         |                  || The special keyword ``-end-`` must be added to the end  |
   |         |                  || of the string to mark the completion of the option list |
   |         |                  || option list.                                            |
   |         |                  ||                                                         |
   |         |                  || If nothing is specified, xCAT passes the the following  |
   |         |                  || ``--without-32bit --with out-fw-update --force``        |
   +---------+------------------+----------------------------------------------------------+
   |``-i``   | For diskless     || The image root path of the diskless image               |
   |         |                  ||                                                         |
   +---------+------------------+----------------------------------------------------------+
   |``-n``   | For diskless     || nodeset status, value is ``genimage``                   |
   |         |                  ||                                                         |
   +---------+------------------+----------------------------------------------------------+


   A very basic usage of the install script: ::

       /install/postscripts/mlnxofed_ib_install -p /install/<path-to>/<MLNX_OFED_LINUX.iso>


   To pass the ``--add-kernel-support`` option to ``mlnxofedinstall``, use the following command: ::

       /install/postscripts/mlnxofed_ib_install -p /install/<path-to>/<MLNX_OFED_LINUX.iso> \
           -m --without-32bit --without-fw-update --add-kernel-support --force -end- 

