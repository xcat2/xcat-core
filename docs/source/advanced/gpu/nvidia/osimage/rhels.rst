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

    chdef -t osimage -o rhels7.2-ppc64le-install-cudafull -p pkgdir=/install/cuda-repo

#. Use the provided ``cudafull`` pkglist to install the CUDA packages: ::

    chdef -t osimage -o rhels7.2-ppc64le-install-cudafull \
    pkglist=/opt/xcat/share/xcat/instal/rh/cudafull.rhels7.ppc64le.pkglist

cudaruntime
^^^^^^^^^^^

#. Create a copy of the ``install-compute`` image and label it ``cudaruntime``: ::

    lsdef -t osimage -z rhels7.2-ppc64le-install-compute \
      | sed 's/install-compute:/install-cudaruntime:/' \
      | mkdef -z 

#. Add the CUDA repo created in the previous step to the ``pkgdir`` attribute: ::

    chdef -t osimage -o rhels7.2-ppc64le-install-cudaruntime -p pkgdir=/install/cuda-repo

#. Use the provided ``cudaruntime`` pkglist to install the CUDA packages: ::

    chdef -t osimage -o rhels7.2-ppc64le-install-cudaruntime \
    pkglist=/opt/xcat/share/xcat/instal/rh/cudaruntime.rhels7.ppc64le.pkglist

Diskless images
---------------

The following examples will create diskless images for ``cudafull`` and ``cudaruntime``.  The osimage definitions will be created from the base ``rhels7.2-ppc64le-netboot-compute`` osimage. 

xCAT provides a sample package list files for CUDA. You can find them at:

    * ``/opt/xcat/share/xcat/netboot/rh/cudafull.rhels7.ppc64le.otherpkgs.pkglist``
    * ``/opt/xcat/share/xcat/netboot/rh/cudaruntime.rhels7.ppc64le.otherpkgs.pkglist``

**[diskless note]**: For diskless images, the requirement for rebooting the machine is not applicable because the images is loaded on each reboot.  The install of the CUDA packages is required to be done in the ``otherpkglist`` **NOT** the ``pkglist``. 

cudafull
^^^^^^^^

#. Create a copy of the ``netboot-compute`` image and label it ``cudafull``: ::

    lsdef -t osimage -z rhels7.2-ppc64le-netboot-compute \
      | sed 's/netboot-compute:/netboot-cudafull:/' \
      | mkdef -z 

#. Add the CUDA repo created in the previous step to the ``otherpkgdir`` attribute: ::

    chdef -t osimage -o rhels7.2-ppc64le-netboot-cudafull otherpkgdir=/install/cuda-repo

#. Add the provided ``cudafull`` otherpkglist.pkglist file to install the CUDA packages: ::

    chdef -t osimage -o rhels7.2-ppc64le-netboot-cudafull \
    otherpkglist=/opt/xcat/share/xcat/netboot/rh/cudafull.rhels7.ppc64le.otherpkgs.pkglist

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

#. Add the CUDA repo created in the previous step to the ``otherpkgdir`` attribute: ::

    chdef -t osimage -o rhels7.2-ppc64le-netboot-cudaruntime otherpkgdir=/install/cuda-repo

#. Add the provided ``cudaruntime`` otherpkglist.pkglist file to install the CUDA packages: ::

    chdef -t osimage -o rhels7.2-ppc64le-netboot-cudaruntime \
    otherpkglist=/opt/xcat/share/xcat/netboot/rh/cudaruntime.rhels7.ppc64le.otherpkgs.pkglist

#. Generate the image: ::

    genimage rhels7.2-ppc64le-netboot-cudaruntime

#. Package the image: ::

    packimage rhels7.2-ppc64le-netboot-cudaruntime

