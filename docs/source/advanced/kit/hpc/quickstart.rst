Quick Start Guide
=================

This quick start is provided to guide users through the steps required to install the IBM High Performance Computing (HPC) software stack on a cluster managed by xCAT. (*NOTE:* xCAT provides XLC and XLF partial kits, but all other HPC kits are provided by the HPC products teams, xCAT may not have any knowledges of their dependencies and requirements)  

The following software kits will be used to install the IBM HPC software stack on to a RedHat Enterprise Linux 7.2 operating system running on ppc64le architecture. 

    * ``xlc-13.1.3-0-ppc64le.tar.bz2`` [1]_
    * ``xlf-15.1.3-0-ppc64le.tar.bz2`` [1]_
    * ``pperte-2.3.0.0-1547a-ppc64le.tar.bz2``
    * ``pperte-2.3.0.2-s002a-ppc64le.tar.bz2``
    * ``essl-5.4.0-0-ppc64le.tar.bz2``
    * ``pessl-5.2.0-0-ppc64le.tar.bz2``
    * ``ppedev-2.2.0-0.tar.bz2``

.. [1] This guide assumes that the **complete** software kit is available for all the products listed below. For the IBM XL compilers, follow the :doc:`IBM XL Compiler </advanced/kit/hpc/software/compilers>` documentation to obtain the software and create the **complete** kit before proceeding.

1. Using the ``addkit`` command, add each software kit package into xCAT: ::
  
    addkit xlc-13.1.3-0-ppc64le.tar.bz2,xlf-15.1.3-0-ppc64le.tar.bz2
    addkit pperte-2.3.0.0-1547a-ppc64le.tar.bz2,pperte-2.3.0.2-s002a-ppc64le.tar.bz2
    addkit pessl-5.2.0-0-ppc64le.tar.bz2,essl-5.4.0-0-ppc64le.tar.bz2
    addkit ppedev-2.2.0-0.tar.bz2

   The ``lskit`` command can be used to view the kits after adding to xCAT.


2. Using the ``addkitcomp`` command, add the kitcomponent to the target osimage.  

   The order that the kit components are added to the osimage is important due to dependencies that kits may have with one another, a feature to help catch potential issues ahead of time.  There are a few different types of dependencies: 

      * **internal kit dependencies** - kit components within the software kit have dependencies.  For example, the software has a dependency on it's license component.  The ``-a`` option will automatically resolve internal kit dependencies.
      * **external kit dependencies** - a software kit depends on another software provided in a separate kit.  The dependency kit must be added first.  ``addkitcomp`` will complain if it cannot resolve the dependency. 
      * **runtime dependencies** - the software provided in the kit has rpm requirements for external 3rd party RPMs not shipped with the kit.  The administrator needs to configure these before deploying the osimage and ``addkitcomp`` cannot detect this dependencies. 

  In the following examples, the ``rhels7.2-ppc64le-install-compute`` osimage is used and the ``-a`` option is specified to resolve internal dependencies. 

    #. Add the **XLC** kitcomponents to the osimage:  ::

        addkitcomp -a -i rhels7.2-ppc64le-install-compute \
            xlc.compiler-compute-13.1.3-0-rhels-7.2-ppc64le


    #. Add the **XLF** kitcomponents to the osimage:  ::
  
        addkitcomp -a -i rhels7.2-ppc64le-install-compute \
            xlf.compiler-compute-15.1.3-0-rhels-7.2-ppc64le


    #. Add the PE RTE GA, **pperte-1547a**, kitcomponents to the osimage:  ::

        addkitcomp -a -i rhels7.2-ppc64le-install-compute \
            pperte-login-2.3.0.0-1547a-rhels-7.2-ppc64le

        addkitcomp -a -i rhels7.2-ppc64le-install-compute \
            pperte-compute-2.3.0.0-1547a-rhels-7.2-ppc64le

        addkitcomp -a -i rhels7.2-ppc64le-install-compute \
            min-pperte-compute-2.3.0.0-1547a-rhels-7.2-ppc64le


    #. Add the PE RTE PTF2, **pperte-s002a**, kitcomponents to the osimage. 

       The PTF2 update requires the ``pperte-license`` component, which is provided by the GA software kit.  The ``addkitcomp -n`` option allows for multiple versions of the same kit component to be installed into the osimage.  If only the PTF2 version is intended to be installed, you can skip the previous step for adding the GA ppetre kit component, but the GA software kit must have been added to xCAT with the ``addkit`` command in order to resolve the license dependency.  ::

        addkitcomp -a -n -i rhels7.2-ppc64le-install-compute \ 
            pperte-login-2.3.0.2-s002a-rhels-7.2-ppc64le

        addkitcomp -a -n -i rhels7.2-ppc64le-install-compute \
            pperte-compute-2.3.0.2-s002a-rhels-7.2-ppc64le

        addkitcomp -a -n -i rhels7.2-ppc64le-install-compute \
            min-pperte-compute-2.3.0.2-s002a-rhels-7.2-ppc64le


    #. Add the **ESSL** kitcomponents to the osimage.  

       The ESSL software kit has an *external dependency* to the ``libxlf`` which is provided in the XLF software kit.  Since it's already added in the above step, there is no action needed here.

       If CUDA toolkit is being used, ESSL has a runtime dependency on the CUDA rpms.  The adminstrator needs to create the repository for the CUDA 7.5 toolkit or a runtime error will occur when provisioning the node.  See the :doc:`/advanced/gpu/nvidia/repo/index` section for more details about setting up the CUDA repository on the xCAT management node. ::

        #
        # Assuming that the cuda repo has been configured at:
        # /install/cuda-7.5/ppc64le/cuda-core
        #
        chdef -t osimage rhels7.2-ppc64le-install-compute \
            pkgdir=/install/rhels7.2/ppc64le,/install/cuda-7.5/ppc64le

        addkitcomp -a -i rhels7.2-ppc64le-install-compute \
            essl-computenode-6464rte-5.4.0-0-rhels-7.2-ppc64le

        addkitcomp -a -i rhels7.2-ppc64le-install-compute \
            essl-computenode-3264rte-5.4.0-0-rhels-7.2-ppc64le

        addkitcomp -a -i rhels7.2-ppc64le-install-compute \
            essl-computenode-5.4.0-0-rhels-7.2-ppc64le

        addkitcomp -a -i rhels7.2-ppc64le-install-compute \
            essl-loginnode-5.4.0-0-rhels-7.2-ppc64le

        addkitcomp -a -i rhels7.2-ppc64le-install-compute \
            essl-computenode-3264rtecuda-5.4.0-0-rhels-7.2-ppc64le

      If the system doesn't have GPU and the CUDA toolkit is not needed,  the adminstrator should not add the following kit components that requires the CUDA packages: ``essl-loginnode-5.4.0-0-rhels-7.2-ppc64le``, ``essl-computenode-3264rte-5.4.0-0-rhels-7.2-ppc64le`` and ``essl-computenode-3264rtecuda-5.4.0-0-rhels-7.2-ppc64le``.  Check the ESSL installation guide: http://www.ibm.com/support/knowledgecenter/SSFHY8_5.4.0/com.ibm.cluster.essl.v5r4.essl300.doc/am5il_xcatinstall.htm 

    #. Add the **Parallel ESSL** kitcomponents to osimage.  

       **Note:** ESSL kitcomponents are required for the PESSL.  ::

        addkitcomp -a -i rhels7.2-ppc64le-install-compute \
            pessl-loginnode-5.2.0-0-rhels-7.2-ppc64le

        addkitcomp -a -i rhels7.2-ppc64le-install-compute \
            pessl-computenode-5.2.0-0-rhels-7.2-ppc64le

        addkitcomp -a -i rhels7.2-ppc64le-install-compute \
            pessl-computenode-3264rtempich-5.2.0-0-rhels-7.2-ppc64le
 

    #. Add the **PE DE** kitcomponents to osimage:  ::

        addkitcomp -a -i rhels7.2-ppc64le-install-compute \
            ppedev.login-2.2.0-0-rhels-7.2-ppc64le

        addkitcomp -a -i rhels7.2-ppc64le-install-compute \
            ppedev.compute-2.2.0-0-rhels-7.2-ppc64le
    

3. The updated osimage now contains the configuration to install using xCAT software kits: ::

     lsdef -t osimage rhels7.2-ppc64le-install-compute 
        Object name: rhels7.2-ppc64le-install-compute
        exlist=/install/osimages/rhels7.2-ppc64le-install-compute-kits/kits/KIT_COMPONENTS.exlist
        imagetype=linux
        kitcomponents=xlc.license-compute-13.1.3-0-rhels-7.2-ppc64le,xlc.rte-compute-13.1.3-0-rhels-7.2-ppc64le,xlc.compiler-compute-13.1.3-0-rhels-7.2-ppc64le,xlf.license-compute-15.1.3-0-rhels-7.2-ppc64le,xlf.rte-compute-15.1.3-0-rhels-7.2-ppc64le,xlf.compiler-compute-15.1.3-0-rhels-7.2-ppc64le,pperte-license-2.3.0.0-1547a-rhels-7.2-ppc64le,pperte-login-2.3.0.0-1547a-rhels-7.2-ppc64le,pperte-compute-2.3.0.0-1547a-rhels-7.2-ppc64le,min-pperte-compute-2.3.0.0-1547a-rhels-7.2-ppc64le,pperte-login-2.3.0.2-s002a-rhels-7.2-ppc64le,pperte-compute-2.3.0.2-s002a-rhels-7.2-ppc64le,min-pperte-compute-2.3.0.2-s002a-rhels-7.2-ppc64le,essl-license-5.4.0-0-rhels-7.2-ppc64le,essl-computenode-3264rte-5.4.0-0-rhels-7.2-ppc64le,essl-computenode-6464rte-5.4.0-0-rhels-7.2-ppc64le,essl-computenode-5.4.0-0-rhels-7.2-ppc64le,essl-loginnode-5.4.0-0-rhels-7.2-ppc64le,essl-computenode-3264rtecuda-5.4.0-0-rhels-7.2-ppc64le,ppedev.license-2.2.0-0-rhels-7.2-ppc64le,ppedev.login-2.2.0-0-rhels-7.2-ppc64le,ppedev.compute-2.2.0-0-rhels-7.2-ppc64le,pessl-license-5.2.0-0-rhels-7.2-ppc64le,pessl-loginnode-5.2.0-0-rhels-7.2-ppc64le,pessl-computenode-5.2.0-0-rhels-7.2-ppc64le,pessl-computenode-3264rtempich-5.2.0-0-rhels-7.2-ppc64le
        osarch=ppc64le
        osdistroname=rhels7.2-ppc64le
        osname=Linux
        osvers=rhels7.2
        otherpkgdir=/install/post/otherpkgs/rhels7.2/ppc64le
        otherpkglist=/install/osimages/rhels7.2-ppc64le-install-compute-kits/kits/KIT_DEPLOY_PARAMS.otherpkgs.pkglist,/install/osimages/rhels7.2-ppc64le-install-compute-kits/kits/KIT_COMPONENTS.otherpkgs.pkglist
        pkgdir=/install/rhels7.2/ppc64le,/install/cuda-7.5/ppc64le
        pkglist=/opt/xcat/share/xcat/install/rh/compute.rhels7.pkglist
        postbootscripts=KIT_pperte-login-2.3.0.0-1547a-rhels-7.2-ppc64le_pperte_postboot,KIT_pperte-compute-2.3.0.0-1547a-rhels-7.2-ppc64le_pperte_postboot,KIT_min-pperte-compute-2.3.0.0-1547a-rhels-7.2-ppc64le_pperte_postboot,KIT_pperte-login-2.3.0.2-s002a-rhels-7.2-ppc64le_pperte_postboot,KIT_pperte-compute-2.3.0.2-s002a-rhels-7.2-ppc64le_pperte_postboot,KIT_min-pperte-compute-2.3.0.2-s002a-rhels-7.2-ppc64le_pperte_postboot
        profile=compute
        provmethod=install
        template=/opt/xcat/share/xcat/install/rh/compute.rhels7.tmpl

4. The osimage is now ready to deploy to the compute nodes. 
