RHEL 7.2 LE
===========

Diskful images
---------------

The following examples will create diskful images for ``cudafull`` and ``cudaruntime``.  The osimage definitions will be created from the base ``rhels7.2-ppc64le-install-compute`` osimage. 

xCAT provides a sample package list files for CUDA. You can find them at:

    * ``/opt/xcat/share/xcat/instal/rh/cudafull.rhels7.ppc64le.pkglist``
    * ``/opt/xcat/share/xcat/instal/rh/cudaruntime.rhels7.ppc64le.pkglist``

**[diskful note]**: There is a requirement to reboot the machine after the CUDA drivers are installed.  To satisfy this requirement, the CUDA software is installed in the ``pkglist`` attribute of the osimage definition where the reboot happens after the Operating System is installed. 

cudafull
^^^^^^^^

#. Create a copy of the ``install-compute`` image and label it ``cudafull``: ::

    lsdef -t osimage -z rhels7.2-ppc64le-install-compute \
      | sed 's/install-compute:/install-cudafull:/' \
      | mkdef -z 

#. Add the CUDA repo created in the previous step to the ``pkgdir`` attribute: ::

    chdef -t osimage -o rhels7.2-ppc64le-install-cudafull -p \
      pkgdir=/install/cuda-7.5/ppc64le/cuda-core,/install/cuda-7.5/ppc64le/cuda-deps

#. Use the provided ``cudafull`` pkglist to install the CUDA packages: ::

    chdef -t osimage -o rhels7.2-ppc64le-install-cudafull \
      pkglist=/opt/xcat/share/xcat/install/rh/cudafull.rhels7.ppc64le.pkglist

cudaruntime
^^^^^^^^^^^

#. Create a copy of the ``install-compute`` image and label it ``cudaruntime``: ::

    lsdef -t osimage -z rhels7.2-ppc64le-install-compute \
      | sed 's/install-compute:/install-cudaruntime:/' \
      | mkdef -z 

#. Add the CUDA repo created in the previous step to the ``pkgdir`` attribute: ::

    chdef -t osimage -o rhels7.2-ppc64le-install-cudaruntime -p \
      pkgdir=/install/cuda-7.5/ppc64le/cuda-core,/install/cuda-7.5/ppc64le/cuda-deps

#. Use the provided ``cudaruntime`` pkglist to install the CUDA packages: ::

    chdef -t osimage -o rhels7.2-ppc64le-install-cudaruntime \
      pkglist=/opt/xcat/share/xcat/instal/rh/cudaruntime.rhels7.ppc64le.pkglist

Diskless images
---------------

The following examples will create diskless images for ``cudafull`` and ``cudaruntime``.  The osimage definitions will be created from the base ``rhels7.2-ppc64le-netboot-compute`` osimage. 

**[diskless note]**: For diskless images, the requirement for rebooting the machine is not applicable because the images is loaded on each reboot.  The install of the CUDA packages is required to be done in the ``otherpkglist`` **NOT** the ``pkglist``. 

cudafull
^^^^^^^^

#. Create a copy of the ``netboot-compute`` image and label it ``cudafull``: ::

    lsdef -t osimage -z rhels7.2-ppc64le-netboot-compute \
      | sed 's/netboot-compute:/netboot-cudafull:/' \
      | mkdef -z 

#. Add the CUDA repo created in the previous step to the ``otherpkgdir`` attribute:

   The default ``otherpkgdir`` should be **/install/post/otherpkgs/rhels7.2/ppc64le** ::

    # lsdef -t osimage rhels7.2-ppc64le-netboot-cudafull -i otherpkgdir
    Object name: rhels7.2-ppc64le-netboot-compute
        otherpkgdir=/install/post/otherpkgs/rhels7.2/ppc64le

   Symbol link your CUDA repo which was created in the previous step to this ``otherpkgdir`` ::

    ln -s /install/cuda-7.5 /install/post/otherpkgs/rhels7.2/ppc64le/cuda-7.5

#. Generate a customized ``pkglist`` file to install the CUDA dependency packages: ::

    # copy a pkglist file from /opt/xcat/share/xcat/netboot/rh/compute.rhels7.ppc64le.pkglist
    mkdir -p /install/custom/netboot/rh/
    cp /opt/xcat/share/xcat/netboot/rh/compute.rhels7.ppc64le.pkglist \
      /install/custom/netboot/rh/cudafull.rhels7.ppc64le.pkglist

    # append the dependency packages for cuda
    vi /install/custom/netboot/rh/cudafull.rhels7.ppc64le.pkglist
      ...
      kernel-devel
      gcc
      pciutils

    # set the pkglist file to pkglist attribute
    chdef -t osimage -o rhels7.2-ppc64le-netboot-cudafull \
      pkglist=/install/custom/netboot/rh/cudafull.rhels7.ppc64le.pkglist

#. Generate ``cudafull`` ``otherpkglist.pkglist`` file to install the CUDA packages: ::

    # generate the otherpkgs.pkglist for cudafull osimage
    vi /install/custom/netboot/rh/cudafull.rhels7.ppc64le.otherpkgs.pkglist
      cuda-7.5/ppc64le/cuda-deps/dkms
      cuda-7.5/ppc64le/cuda-core/cuda

    # set the pkglist file to otherpkglist attribute
    chdef -t osimage -o rhels7.2-ppc64le-netboot-cudafull \
      otherpkglist=/install/custom/netboot/rh/cudafull.rhels7.ppc64le.otherpkgs.pkglist

#. Generate the image: ::

    genimage rhels7.2-ppc64le-netboot-cudafull

#. Package the image: ::

    packimage rhels7.2-ppc64le-netboot-cudafull

cudaruntime
^^^^^^^^^^^

#. Create a copy of the ``netboot-compute`` image and label it ``cudaruntime``: ::

    lsdef -t osimage -z rhels7.2-ppc64le-netboot-compute \
      | sed 's/netboot-compute:/netboot-cudaruntime:/' \
      | mkdef -z

#. Add the CUDA repo created in the previous step to the ``otherpkgdir`` attribute:

   The default ``otherpkgdir`` should be **/install/post/otherpkgs/rhels7.2/ppc64le** ::

    # lsdef -t osimage rhels7.2-ppc64le-netboot-cudaruntime -i otherpkgdir
    Object name: rhels7.2-ppc64le-netboot-compute
        otherpkgdir=/install/post/otherpkgs/rhels7.2/ppc64le

   Symbol link your CUDA repo which was created in the previous step to this ``otherpkgdir`` ::

    ln -s /install/cuda-7.5 /install/post/otherpkgs/rhels7.2/ppc64le/cuda-7.5

#. Generate a customized ``pkglist`` file to install the CUDA dependency packages: ::

    # copy a pkglist file from /opt/xcat/share/xcat/netboot/rh/compute.rhels7.ppc64le.pkglist
    mkdir -p /install/custom/netboot/rh/
    cp /opt/xcat/share/xcat/netboot/rh/compute.rhels7.ppc64le.pkglist \
      /install/custom/netboot/rh/cudaruntime.rhels7.ppc64le.pkglist

    # append the dependency packages for cuda
    vi /install/custom/netboot/rh/cudaruntime.rhels7.ppc64le.pkglist
      ...
      kernel-devel
      gcc
      pciutils

    # set the pkglist file to pkglist attribute
    chdef -t osimage -o rhels7.2-ppc64le-netboot-cudaruntime \
      pkglist=/install/custom/netboot/rh/cudaruntime.rhels7.ppc64le.pkglist

#. Generate ``cudaruntime`` ``otherpkglist.pkglist`` file to install the CUDA packages: ::

    # generate the otherpkgs.pkglist for cudaruntime osimage
    vi /install/custom/netboot/rh/cudaruntime.rhels7.ppc64le.otherpkgs.pkglist
      cuda-7.5/ppc64le/cuda-deps/dkms
      cuda-7.5/ppc64le/cuda-core/cuda-runtime-7-5

    # set the pkglist file to otherpkglist attribute
    chdef -t osimage -o rhels7.2-ppc64le-netboot-cudaruntime \
      otherpkglist=/install/custom/netboot/rh/cudaruntime.rhels7.ppc64le.otherpkgs.pkglist

#. Generate the image: ::

    genimage rhels7.2-ppc64le-netboot-cudaruntime

#. Package the image: ::

    packimage rhels7.2-ppc64le-netboot-cudaruntime

