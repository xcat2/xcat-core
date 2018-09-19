Python framework
================

When testing the scale up of xCAT commands against OpenBMC REST API, it was evident that the Perl framework of xCAT did not scale well and was not sending commands to the BMCs in a true parallel fashion.

The team investigated the possibility of using Python framework.  This support is implemented using Python 2.x framework.

.. toctree::
   :maxdepth: 2

   install/index.rst
   performance.rst
