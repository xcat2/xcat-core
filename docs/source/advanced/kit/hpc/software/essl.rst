Engineering and Scientific Subroutine Library (ESSL)
====================================================

xCAT software kits for ESSL for Linux is available on: [#]_

    * ESSL 5.2.0.1 and newer

Dependencies
------------

* ESSL has a dependency on the XLC/XLF compilers

  When adding the ESSL kit component to the osimage, ensure that the compiler kit component is already added to the osimage, or, use the ``-a | --adddeps`` option on ``addkitcomp`` to automatically assign the kit dependencies to the osimage.


  To add the ``essl-computenode`` kit component to osimage ``rhels7.2-ppc64le-install-compute``: ::

    addkitcomp -a -i rhels7.2-ppc64le-install-compute \
        essl-computenode-3264rte-5.4.0-0-rhels-7.2-ppc64le

Reference
---------
  Refer to ESSL installation guide for more information: http://www.ibm.com/support/knowledgecenter/SSFHY8_5.4.0/com.ibm.cluster.essl.v5r4.essl300.doc/am5il_xcatinstall.htm


.. [#] If using an older release, refer to  `IBM HPC Stack in an xCAT Cluster <https://sourceforge.net/p/xcat/wiki/IBM_HPC_Stack_in_an_xCAT_Cluster/>`_

