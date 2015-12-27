Ubuntu 14.04.3
==============


Diskful images
---------------

The following examples will create diskful images for ``cudafull`` and ``cudaruntime``.  The osimage definitions will be created from the base ``ubuntu14.04.3-ppc64el-install-compute`` osimage.

xCAT provides a sample package list files for CUDA. You can find them at:

    * ``/opt/xcat/share/xcat/install/ubuntu/cudafull.ubuntu14.04.3.ppc64el.pkglist``
    * ``/opt/xcat/share/xcat/install/ubuntu/cudaruntime.ubuntu14.04.3.ppc64el.pkglist``

**[diskful note]**: There is a requirement to reboot the machine after the CUDA drivers are installed.  To satisfy this requirement, the CUDA software is installed in the ``pkglist`` attribute of the osimage definition where the reboot happens after the Operating System is installed. 

cudafull
^^^^^^^^

#. Create a copy of the ``install-compute`` image and label it ``cudafull``: ::

    lsdef -t osimage -z ubuntu14.04.3-ppc64el-install-compute \
      | sed 's/install-compute:/install-cudafull:/' \
      | mkdef -z 

#. Add the CUDA repo created in the previous step to the ``pkgdir`` attribute.

   If your Management Node IP is 10.0.0.1, the URL for the repo would be ``http://10.0.0.1/install/cuda-repo/ppc64el/var/cuda-repo-7-5-local``, add it to the pkgdir::

    chdef -t osimage -o ubuntu14.04.3-ppc64el-install-cudafull \ 
     -p pkgdir=http://10.0.0.1/install/cuda-repo/ppc64el/var/cuda-repo-7-5-local


   **TODO:** Need to add Ubuntu Port?  "http://ports.ubuntu.com/ubuntu-ports trusty main,http://ports.ubuntu.com/ubuntu-ports trusty-updates main"

#. Use the provided ``cudafull`` pkglist to install the CUDA packages: ::

    chdef -t osimage -o ubuntu14.04.3-ppc64el-install-cudafull \
    pkglist=/opt/xcat/share/xcat/install/ubuntu/cudafull.ubuntu14.04.3.ppc64el.pkglist

cudaruntime
^^^^^^^^^^^

#. Create a copy of the ``install-compute`` image and label it ``cudaruntime``: ::

    lsdef -t osimage -z ubuntu14.04.3-ppc64el-install-compute \
      | sed 's/install-compute:/install-cudaruntime:/' \
      | mkdef -z 

#. Add the CUDA repo created in the previous step to the ``pkgdir`` attribute:

   If your Management Node IP is 10.0.0.1, the URL for the repo would be ``http://10.0.0.1/install/cuda-repo/ppc64el/var/cuda-repo-7-5-local``, add it to the pkgdir::

    chdef -t osimage -o ubuntu14.04.3-ppc64el-install-cudaruntime \
     -p pkgdir=http://10.0.0.1/install/cuda-repo/ppc64el/var/cuda-repo-7-5-local

   **TODO:** Need to add Ubuntu Port?  "http://ports.ubuntu.com/ubuntu-ports trusty main,http://ports.ubuntu.com/ubuntu-ports trusty-updates main"

#. Use the provided ``cudaruntime`` pkglist to install the CUDA packages: ::

    chdef -t osimage -o ubuntu14.04.3-ppc64el-install-cudaruntime \
    pkglist=/opt/xcat/share/xcat/install/ubuntu/cudaruntime.ubuntu14.04.3.ppc64el.pkglist

Diskless images
---------------

The following examples will create diskless images for ``cudafull`` and ``cudaruntime``.  The osimage definitions will be created from the base ``ubuntu14.04.3-ppc64el-netboot-compute`` osimage. 

xCAT provides a sample package list files for CUDA. You can find them at:

    * ``/opt/xcat/share/xcat/netboot/ubuntu/cudafull.ubuntu14.04.3.ppc64el.pkglist``
    * ``/opt/xcat/share/xcat/netboot/ubuntu/cudaruntime.ubuntu14.04.3.ppc64el.pkglist``

**[diskless note]**: For diskless images, the requirement for rebooting the machine is not applicable because the images is loaded on each reboot.  The install of the CUDA packages is required to be done in the ``otherpkglist`` **NOT** the ``pkglist``. 

cudafull
^^^^^^^^

#. Create a copy of the ``netboot-compute`` image and label it ``cudafull``: ::

    lsdef -t osimage -z ubuntu14.04.3-ppc64el-netboot-compute \
      | sed 's/netboot-compute:/netboot-cudafull:/' \
      | mkdef -z 

#. Add the CUDA repo created in the previous step to the ``otherpkgdir`` attribute. 

   If your Management Node IP is 10.0.0.1, the URL for the repo would be ``http://10.0.0.1/install/cuda-repo/ppc64el/var/cuda-repo-7-5-local``, add it to the ``otherpkgdir``::

    chdef -t osimage -o ubuntu14.04.3-ppc64el-netboot-cudafull \
    otherpkgdir=http://10.0.0.1/install/cuda-repo/ppc64el/var/cuda-repo-7-5-local

#. Add the provided ``cudafull`` otherpkg.pkglist file to install the CUDA packages: ::

    chdef -t osimage -o ubuntu14.04.3-ppc64el-netboot-cudafull \
    otherpkglist=/opt/xcat/share/xcat/netboot/ubuntu/cudafull.otherpkgs.pkglist

   **TODO:** Need to add Ubuntu Port?  "http://ports.ubuntu.com/ubuntu-ports trusty main,http://ports.ubuntu.com/ubuntu-ports trusty-updates main"

#. Verify that ``acpid`` is installed on the Management Node or on the Ubuntu host where you are generating the diskless image: ::

    apt-get install -y acpid 

#. Generate the image: ::

    genimage ubuntu14.04.3-ppc64el-netboot-cudafull

#. Package the image: ::

    packimage ubuntu14.04.3-ppc64el-netboot-cudafull

cudaruntime
^^^^^^^^^^^

#. Create a copy of the ``netboot-compute`` image and label it ``cudaruntime``: ::

    lsdef -t osimage -z ubuntu14.04.3-ppc64el-netboot-compute \
      | sed 's/netboot-compute:/netboot-cudaruntime:/' \
      | mkdef -z 

#. Add the CUDA repo created in the previous step to the ``otherpkgdir`` attribute. 

   If your Management Node IP is 10.0.0.1, the URL for the repo would be ``http://10.0.0.1/install/cuda-repo/ppc64el/var/cuda-repo-7-5-local``, add it to the ``otherpkgdir``::

    chdef -t osimage -o ubuntu14.04.3-ppc64el-netboot-cudaruntime  \
    otherpkgdir=http://10.0.0.1/install/cuda-repo/ppc64el/var/cuda-repo-7-5-local

#. Add the provided ``cudaruntime`` otherpkg.pkglist file to install the CUDA packages: ::

    chdef -t osimage -o ubuntu14.04.3-ppc64el-netboot-cudaruntime \
    otherpkglist=/opt/xcat/share/xcat/netboot/ubuntu/cudaruntime.otherpkgs.pkglist

   **TODO:** Need to add Ubuntu Port?  "http://ports.ubuntu.com/ubuntu-ports trusty main,http://ports.ubuntu.com/ubuntu-ports trusty-updates main"

#. Verify that ``acpid`` is installed on the Management Node or on the Ubuntu host where you are generating the diskless image: ::

    apt-get install -y acpid 

#. Generate the image: ::

    genimage ubuntu14.04.3-ppc64el-netboot-cudaruntime

#. Package the image: ::

    packimage ubuntu14.04.3-ppc64el-netboot-cudaruntime


