IB Driver Preparation and Installation
======================================

XCAT provides one sample postscript to help you install the **Mellanox OpenFabrics Enterprise Distribution** (OFED) Infiniband Driver. This shell script is ``/opt/xcat/share/xcat/ib/scripts/Mellanox/mlnxofed_ib_install``. You can use this script directly or just refer to it then change it to satisfy your own environment. From xCAT2.11, XCAT offers a new version of mlnxofed_ib_install(i.e. mlnxofed_ib_install.v2).  From the perspective of function, the v2 is forward compatible with v1. But the v2 has different usage interface from v1. it becomes more flexible. we still ship v1 with XCAT **but stop support it from xCAT2.11**. We recommend to use mlnxofed_ib_install.v2.

.. toctree::
   :maxdepth: 2

   mlnxofed_ib_install_v2_usage.rst
   mlnxofed_ib_install_v1_usage.rst
   