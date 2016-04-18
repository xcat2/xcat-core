Known Issues
============


Known Issue 1
-------------

After you install mellanox derives in rhels7.2 successfully by xCAT, maybe you have new requirement to upgrade your operating system to higher version. In this case you probably hit such problem the IB adaptor drives shipped by operating system is higher than the Mellanox drives you have installed. That means the the Mellanox drives will be replaced by the drives shipped by operating system. If it's not the result you expect, you hope keep the Mellanox drives after operating system upgraded, please add below statement into ``/etc/yum.conf`` in your target node after you install mellanox derives successfully for the first time. ::
 
    exclude=dapl* libib* ibacm infiniband* libmlx* librdma* opensm* ibutils*


Known Issue 2
-------------

If you want to use ``--add-kernel-support`` attribute in sles12.1 and ppc64le scenario, you will find some dependency packages are not shipped by SLES Server DVDs, such like ``python-devel``, it's shipped in SDK DVDs. xCAT doesn't ship specific pkglist to support such scenario. If you have such requirement, please used ``otherpkglist`` and ``otherpkgs`` attributes to prepare dependency packages repository ahead. If you need help about ``otherpkglist`` and ``otherpkgs``attributes, please refer to :doc:`Add Additional Software Packages </guides/admin-guides/manage_clusters/ppc64le/diskful/customize_image/additional_pkg>`. 


 
