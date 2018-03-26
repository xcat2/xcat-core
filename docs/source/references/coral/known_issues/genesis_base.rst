xCAT Genesis Base
=================

*Note*: Please rebuild ``xCAT-genesis-base`` with ``xCAT-genesis-builder`` version equal and newer than *2.13.10* before updating xCAT *2.13.10* and higher.

xCAT ships a ``xCAT-genesis-base`` package as part of xcat-deps.  This is a light-weight diskless linux image based on Fedora (Fedora26, currently) that is used by xCAT to do hardware discovery.

To support the Power9 hardware, changes are made to the kernel in the Red Hat Enterprise distribution that are not yet available in the Fedora kernels.  Without that support, running the scripts in xCAT discovery caused segmentation faults described in this issue: https://github.com/xcat2/xcat-core/issues/3870

Work-around
-----------

xCAT cannot ship a kernel based on RHEL distribution, so the customer needs to build a version of the ``xCAT-genesis-base`` on-site using a server running Red Hat Enterprise Linux.

1. Download the latest timestamp version of the ``xCAT-genesis-builder`` RPM provided here: http://xcat.org/files/xcat/xcat-dep/2.x_Linux/beta/
   
2. Install the ``xCAT-genesis-builder`` RPM on a node that is installed with the RHEL version being deployed. 

3. Build the ``xCAT-genesis-base`` RPM: ::

    /opt/xcat/share/xcat/netboot/genesis/builder/buildrpm

4. Install this package on top of the xCAT install and execute: ``mknb ppc64``

