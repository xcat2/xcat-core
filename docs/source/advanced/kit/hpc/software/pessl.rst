Parallel Engineering and Scientific Subroutine Library (PESSL)
==============================================================

xCAT software kits for PESSL for Linux is available on: [#]_

    * PESSL 4.2.0.0 and newer


Dependencies
------------

* PESSL has a dependency on the ESSL kit component

  When adding PESSL kit component and want ESSL installed, ensure that the ESSL kit component is already added to the osimage, or, use the ``-a | --adddeps`` option on ``addkitcomp`` to automatically assign the kit dependencies to the osimage.

  To add the ``pessl-computenode`` kit component to osimage ``rhels7.2-ppc64le-install-compute``: ::

    addkitcomp -a -i rhels7.2-ppc64le-install-compute \
        pessl-computenode-5.2.0-0-rhels-7.2-ppc64le



.. [#] If using an older release, refer to  `IBM HPC Stack in an xCAT Cluster <https://sourceforge.net/p/xcat/wiki/IBM_HPC_Stack_in_an_xCAT_Cluster/>`_
