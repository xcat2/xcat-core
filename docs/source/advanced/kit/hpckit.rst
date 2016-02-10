IBM HPC Product Software Kits
-----------------------------

Obtaining the Kits
``````````````````

Complete kits for some product software is shipped on the product distribution media. For other software, only partial kits may be available. The partial product kits are available from the FixCentral download site.  For the IBM XLF and XLC Compilers,  xCAT ships Ubuntu partial Kits on Sourceforge. the current redhat7.2 partial Kits, it ships on xcat.org: http://xcat.org/files/kits/hpckits/2.11/rhels7.2/ppc64le/


General Instructions for all HPC Kits
`````````````````````````````````````

This is a quick overview of the commands will use to add kits to the xCAT cluster and use them in the Linux OS images.

  * Obtain the IBM HPC product kits
  * If kits are partial kits, needs to build complete kits by combining the partial kit with the product packages ::

      buildkit addpkgs <kit.NEED_PRODUCT_PKGS.tar.bz2> --pkgdir <product package directory>

  * Add each kit to the xCAT database ::

      addkit <product_kit_tarfile>

    This will automatically unpack the tarfile, copy its contents to the correct locations for xCAT, and create the corresponding kit, kitcomponent, and kitrepo objects in the xCAT database.
  * List the product kitcomponents that are available for the OS image ::

      lsdef -t kitcomponent | grep <product>

  * Kit components are typically named based on server role, product version, OS version, and optionally if it is for a minimal image (minimal images exclude documentation, includes, and other optional files to reduce the diskless image size). To list the details of a particular kit component ::

     lsdef -t kitcomponent -o <kitcomponent name> -l

  * The OS image must be defined with a supported serverrole in order to add a kit component to the image. To query the role assigned to an image ::

     lsdef -t osimage -o <image> -i serverrole

   And to change the serverrole of an image ::

     chdef -t osimage -o <image> serverrole=<role>

  * To add or update a kitcomponent in an osimage, first check if the kitcomponent is compatible with the image ::

     chkkitcomp -i <image>  <kitcomponent name>

   If compatible, add the component to that image ::

     addkitcomp -i <image> <kitcomponent name>


   This will add various files for otherpkgs, postinstall, and postbootscripts to the OS image definition. To view some of these ::

     lsdef -t osimage -l <image>

  * If this is a diskless OS image, rebuild, pack, and deploy the image ::

     genimage <image>
     packimage <image> OR #liteimg <image>
     nodeset <noderange> osimage=<image>
     rpower <noderange>

  * If this is a diskful OS image, the new HPC kitcomponent software may be installed either when do a new node deployment or by using the updatenode command.

Parallel Environment Runtime Edition (PE RTE)
`````````````````````````````````````````````

PE RTE software kits are available for Linux PE RTE 1.3 and newer releases on System x.
For Linux PE RTE 1.2 and older releases on System x, and for PE RTE on AIX or on System p, use the xCAT HPC Integration Support Documentation.

No special procedures are required for using the PE RTE kit. If received an incomplete kit, simply follow the previously documented process for adding the product packages and building the complete kit.

**Handle the conflict between PE RTE kit and Mellanox OFED driver install script**

PPE requires the 32-bit version of libibverbs, but the default mlnxofed_ib_install which provides by xCAT to install Mellanox OFED IB driver will remove all the old ib related packages at first including the 32-bit version of libibverbs. In this case, need to set the environment variable ``mlnxofed_options=--force`` when running the mlnxofed_ib_install. 

**Installing multiple versions of PE RTE**

Starting with PE RTE 1.2.0.10, the PE RTE packages are designed so that when user upgrade the product to a newer version or release, the files from the previous version remain in the osimage along with the new version of the product.

Normally only have one version of a kitcomponent present in the xCAT osimage. When run addkitcomp to add a newer version of the kitcomponent, xCAT will first remove the old version of the kitcomponent before adding the new one. If updating a previously built diskless image or an existing diskful node with a newer version of PE RTE, run addkitcomp to add the new PE RTE kitcomponent, xCAT will replace the previous kitcomponent with the new one. For example, if current compute osimage has PE RTE 1.3.0.1 and want to upgrade to PE RTE 1.3.0.2 ::

      lsdef -t osimage -o compute -i kitcomponents
         kitcomponents = pperte_compute-1.3.0.1-0-rhels-6-x86_64
      addkitcomp -i compute pperte_compute-1.3.0.2-0-rhels-6-x86_64
      lsdef -t osimage -o compute -i kitcomponents
         kitcomponents = pperte_compute-1.3.0.2-0-rhels-6-x86_64

And, running a new genimage for the previously built compute diskless image will upgrade the pperte-1.3.0.1 rpm to pperte-1.3.0.2, and will install the new ppe_rte_1302 rpm without removing the previous ppe_rte_1301 rpm.

To remove the previous version of the PE RTE product files from the osimage, need to manaully remove the rpms. In the example above, this would be something like: ::

      chroot /install/netboot/rhels6/x86_64/compute/rootimg rpm -e ppe_rte_1302

If building a new diskless image or installing a diskful node, and need multiple versions of PE RTE present in the image as part of the initial install, need to have multiple versions of the corresponding kitcomponent defined in the xCAT osimage definition. To add multiple versions of PE RTE kitcomponents to an xCAT osimage, add the kitcomponent using the full name with separate addkitcomp commands and specifying the ``-n (--noupgrade)`` flag. For example, to add PE RTE 1.3.0.1 and PE RTE 1.3.0.2 to your compute osimage definition ::

  addkitcomp -i compute pperte_compute-1.3.0.1-0-rhels-6-x86_64
  addkitcomp -i compute -n pperte_compute-1.3.0.2-0-rhels-6-x86_64
  lsdef -t osimage -o compute -i kitcomponents
    kitcomponents = pperte_compute-1.3.0.1-0-rhels-6-x86_64,pperte_compute-1.3.0.2-0-rhels-6-x86_64

In this example, when building a diskless image for the first time, or when deploying a diskful node, xCAT will first install PE RTE 1.3.0.1, and then in a separate yum or zypper call, xCAT will install PE RTE 1.3.0.2. The second install will upgrade the pperte-1.3.0.1 rpm to pperte-1.3.0.2, and will install the new ppe_rte_1302 rpm without removing the previous ppe_rte_1301 rpm.

**Starting PE on cluster nodes**

The PNSD daemon is started from xinetd on compute nodes. This daemon should start automatically at node boot time. Verify that xinetd is running on nodes and PNSD daemon is active.

**POE hostlist files**

If using POE to start a parallel job, xCAT can help create the host list file. Simply run the nodels command against the desired noderange and redirect the output to a file.  ::

      nodels compute &gt; /tmp/hostlist
      poe -hostfile /tmp/hostlist ....

**Known problems with PE RTE**

For PE RTE 1.3.0.1 to 1.3.0.6 on both System X and System P architectures, there is a known issue that when uninstall or upgrade ppe_rte_man in a diskless image, ``genimage <osimage>`` will fail and stop at the error. To workaround this problem, will need to rerun ``genimage <osimage>`` to finish the remaining work. 

For PE RTE 1.3.0.7 on both System X and System P architectures, there is a known issue that when uninstall or upgrade ppe_rte_man in a diskless image, ``genimage <osimage>`` will output errors. However, the new packages are actually upgraded, so no workaround is required and the error can be ignored with risks. 

Starting with PE RTE 1.3.0.7, the src rpm is no longer required. It is not recommended build a complete kit for PE RTE 1.3.0.7 or newer using a partial PE RTE 1.3.0.6 or older kit which still require the src rpm. User should download the latest partial kit for PE RTE 1.3.0.7 or newer to build the corresponding PE RTE complete kit.

Parallel Environment Developer Edition (PE DE)
``````````````````````````````````````````````
PE DE software kits are available for Linux PE DE 1.2.0.1 and newer releases on System X. Also PE DE software kits are available for Linux PE DE 1.2.0.3 and newer releases on System P.

For older Linux releases on System x and System P, and for AIX, use the xCAT HPC Integration Support Documentation.

No special procedures are required for using the PE DE kit. If you received an incomplete kit, simply follow the previously documented process for adding the product packages and building the complete kit

Engineering and Scientific Subroutine Library (ESSL)
````````````````````````````````````````````````````
ESSL software kits are available for Linux ESSL 5.2.0.1 and newer releases on System P.

For older Linux releases on System P, and for AIX, use the xCAT HPC Integration Support Documentation.

No special procedures are required for building the complete PESSL kit. If received an incomplete kit, simply follow the previously documented process for adding the product packages and building the complete kit

When building a diskless image or installing a diskful node, and want ESSL installed with compiler XLC/XLF kits, there is one change when add a ESSL kitcomponent to an xCAT osimage. To add ESSL kitcomponent to an xCAT osimage, add the kitcomponent using separate addkitcomp command and specifying the ``-n(--noupgrade)`` flag. For example, to add ESSL 5.2.0.1 kitcomponent to compute osimage definition ::

    addkitcomp -i compute essl_compute-5.2.0.1-rhels-6-ppc64
    lsdef -t osimage -o compute -i kitcomponents
        kitcomponents = essl_compute-5.2.0.1-rhels-6-ppc64

Parallel Engineering and Scientific Subroutine Library (PESSL)
``````````````````````````````````````````````````````````````

PESSL software kits are available for Linux PESSL 4.2.0.0 and newer releases on System P.

For older Linux releases on System P, and for AIX, use the xCAT HPC Integration Support Documentation.

No special procedures are required for building the PESSL complete kit. If received an incomplete kit, simply follow the previously documented process for adding the product packages and building the complete kit

When building a diskless image or installing a diskful node, and want PESSL installed with ESSL kits, there is one change when add a PESSL kitcomponent to an xCAT osimage. To add PESSL kitcomponent to an xCAT osimage, add the kitcomponent using separate addkitcomp command and specifying the ``-n(--noupgrade)`` flag. For example, to add PESSL 4.2.0.0 kitcomponent to compute osimage definition ::

     addkitcomp -i compute pessl_compute-4.2.0.0-rhels-6-ppc64
     lsdef -t osimage -o compute -i kitcomponents
        kitcomponents = essl_compute-4.2.0.0-rhels-6-ppc64

General Parallel File System (GPFS)
```````````````````````````````````
GPFS software kits are available for Linux GPFS 3.5.0.7 and newer releases on System x.

For Linux GPFS 3.5.0.6 and older releases on System x and for AIX or Linux on System p, use the xCAT HPC Integration Support Documentation.

The GPFS kit requires the addition of the GPFS portability layer package to be added to it. This rpm must be built on a server that matches the architecture and kernel version of all OS images that will be using this kit.

Follow this procedure before using the GPFS kit

  *  On a server that has the correct architecture and kernel version, manually install the GPFS rpms and build the portability layer according to the instructions documented by GPFS: General Parallel File System . After installing the GPFS rpms, check ``/usr/lpp/mmfs/src/README``.  **NOTE**: Building the portability layer requires that the kernel source rpms are installed on server. For example, for SLES11, make sure the kernel-source and kernel-ppc64-devel rpms are installed. For rhels6, make sure the cpp.ppc64,gcc.ppc64,gcc-c++.ppc64,kernel-devel.ppc64 and rpm-build.ppc64 are installed.  
  *  Copy the ``gpfs.gplbin`` rpm that have successfully created to the server that are using to complete the build of GPFS kit, placing it in the same directory as other GPFS rpms.

  *  Complete the kit build ::

      buildkit addpkgs <gpfs-kit-NEED_PRODUCT_PKGS-tarfile> -p <gpfs-rpm-directory>


At this point follow the general instructions for working with kits to add the kit to the xCAT database and add the GPFS kitcomponents to the OS images.

IBM Compilers
`````````````

XLC and XLF software kits are available for Linux XLC 12.1.0.3 and XLF 14.1.0.3, and newer releases on System P.

For XLC 13.1.1.0 and XLF 15.1.1.0, xCAT ships partial software kits for Ubuntu at:

  http://xcat.org/files/xcat/kits/hpckits/2.9/Ubuntu/ppc64_Little_Endian/

For XLC 13.1.2.0 and XLF 15.1.2.0, xCAT ships partial software kits for RHEL 7.2 at:

  http://xcat.org/files/xcat/kits/hpckits/2.11/rhels7.2/ppc64le/
  
For older Linux releases on System P, and for AIX, use the xCAT HPC Integration Support

No special procedures are required for using the XLC/XLF kit. If received an incomplete kit, simply follow the previously documented process for adding the product packages and building the complete kit

Toolkit for Event Analysis and Logging (TEAL)
`````````````````````````````````````````````
Teal software kits are available for Linux Teal 1.2.0.1 and newer releases on System X.

For older Linux releases on System x, and for AIX or System P, use the xCAT HPC Integration Support Documentation.

No special procedures are required for using the Teal kit. If you received an incomplete kit, simply follow the previously documented process for adding the product packages and building the complete kit


Install HPC Software Kits 
`````````````````````````

This section describes the process of using xCAT Software Kits to assist installing the IBM HPC software stack on a cluster managed by xCAT.  The example describe the process of adding the kits and kit components to the the RedHat Enterprise Linux 7.2 operating system running on ppc64le architecture.

The following software kits are provided for the IBM HPC software stack: 


    * ``xlc-13.1.3-0-ppc64le.tar.bz2``
    * ``xlf-15.1.3-0-ppc64le.tar.bz2``
    * ``pperte-2.3.0.0-1547a-ppc64le.tar.bz2``
    * ``pperte-2.3.0.2-s002a-ppc64le.tar.bz2``
    * ``pessl-5.2.0-0-ppc64le.tar.bz2``
    * ``essl-5.4.0-0-ppc64le.tar.bz2``
    * ``ppedev-2.2.0-0.tar.bz2``


#. Using the ``addkit`` command, add each software kit package into xCAT: ::
  
    addkit xlc-13.1.3-0-ppc64le.tar.bz2,xlf-15.1.3-0-ppc64le.tar.bz2
    addkit pperte-2.3.0.0-1547a-ppc64le.tar.bz2,pperte-2.3.0.2-s002a-ppc64le.tar.bz2
    addkit pessl-5.2.0-0-ppc64le.tar.bz2,essl-5.4.0-0-ppc64le.tar.bz2
    addkit ppedev-2.2.0-0.tar.bz2

   The ``lskit`` command can be used to view the kits after adding to xCAT.


#. Using the ``addkitcomp`` command, add the kitcomponent to the target osimage.  

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


    #. Add the **Parallel ESSL** kitcomponents to osimage.  

       *Note:* ESSL kitcomponents are required for the PESSL.  ::

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
    

#. The updated osimage now contains the HPC software stack configuration using xCAT software kits: ::

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

#. The osimage is now ready to deploy to the compute nodes. 
