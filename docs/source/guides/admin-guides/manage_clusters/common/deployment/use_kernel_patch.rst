Use new kernel patch
====================

This procedure assumes there are kernel RPM in /tmp, we take the osimage **rhels7.3-ppc64le-install-compute** as an example.
The RPM names below are only examples, substitute your specific level and architecture.

* **[RHEL]**

#. The RPM kernel package is usually named: kernel-<kernelver>.rpm. Append new kernel packages directory to osimage pkgdir ::

        mkdir -p /install/kernels/<kernelver>
        cp /tmp/kernel-*.rpm /install/kernels/<kernelver>
        createrepo /install/kernels/<kernelver>/
        chdef -t osimage rhels7.3-ppc64le-install-compute -p pkgdir=/install/kernels/<kernelver>

#. Inject the drivers from the new kernel RPMs into the initrd ::

        mkdef -t osdistroupdate kernelupdate dirpath=/install/kernels/<kernelver>/
        chdef -t osimage rhels7.3-ppc64le-install-compute osupdatename=kernelupdate
        chdef -t osimage rhels7.3-ppc64le-install-compute netdrivers=updateonly
        genitrd rhels7.3-ppc64le-install-compute --ignorekernelchk
        nodeset <CN> osimage=rhels7.3-ppc64le-install-compute --noupdateinitrd

#. Boot CN from net normally.
