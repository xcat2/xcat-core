RHEL 7.2 LE
===========

xCAT provides a sample package list (pkglist) files for CUDA. You can find them: 

    * Diskful: ``/opt/xcat/share/xcat/install/rh/cuda*``
    * Diskless: ``/opt/xcat/share/xcat/netboot/rh/cuda*``

Diskful images
---------------

The following examples will create diskful images for ``cudafull`` and ``cudaruntime``.  The osimage definitions will be created from the base ``rhels7.2-ppc64le-install-compute`` osimage. 

**[Note]**: There is a requirement to reboot the machine after the CUDA drivers are installed.  To satisfy this requirement, the CUDA software is installed in the ``pkglist`` attribute of the osimage definition where a reboot will happen after the Operating System is installed.

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

**[Note]**: For diskless, the install of the CUDA packages MUST be done in the ``otherpkglist`` and **NOT** the ``pkglist`` as with diskful.  The requirement for rebooting the machine is not applicable in diskless nodes because the image is loaded on each reboot. 

cudafull
^^^^^^^^

#. Create a copy of the ``netboot-compute`` image and label it ``cudafull``: ::

    lsdef -t osimage -z rhels7.2-ppc64le-netboot-compute \
      | sed 's/netboot-compute:/netboot-cudafull:/' \
      | mkdef -z 

#. Verify that the CUDA repo created in the previous step is available in the directory specified by the ``otherpkgdir`` attribute.  

   The ``otherpkgdir`` directory can be obtained by running lsdef on the osimage: ::

       # lsdef -t osimage rhels7.2-ppc64le-netboot-cudafull -i otherpkgdir
       Object name: rhels7.2-ppc64le-netboot-cudafull
           otherpkgdir=/install/post/otherpkgs/rhels7.2/ppc64le
        
   Create a symbolic link of the CUDA repository in the directory specified by ``otherpkgdir`` ::

       ln -s /install/cuda-7.5 /install/post/otherpkgs/rhels7.2/ppc64le/cuda-7.5

#. Change the ``rootimgdir`` for the cudafull osimage: ::

    chdef -t osimage -o rhels7.2-ppc64le-netboot-cudafull \
       rootimgdir=/install/netboot/rhels7.2/ppc64le/cudafull

#. Create a custom pkglist file to install additional operating system packages for your CUDA node. 

    #. Copy the default compute pkglist file as a starting point: ::

        mkdir -p /install/custom/netboot/rh/

        cp /opt/xcat/share/xcat/netboot/rh/compute.rhels7.ppc64le.pkglist \
          /install/custom/netboot/rh/cudafull.rhels7.ppc64le.pkglist

    #. Edit the pkglist file and append any packages you desire to be installed.  For example: ::

        vi /install/custom/netboot/rh/cudafull.rhels7.ppc64le.pkglist
        ...
        # Additional packages for CUDA
        pciutils

    #. Set the new file as the ``pkglist`` attribute for the cudafull osimage: ::

        chdef -t osimage -o rhels7.2-ppc64le-netboot-cudafull \
          pkglist=/install/custom/netboot/rh/cudafull.rhels7.ppc64le.pkglist


#. Create the ``otherpkg.pkglist`` file to do the install of the CUDA full packages:

    #. Create the otherpkg.pkglist file for cudafull: ::

        vi /install/custom/netboot/rh/cudafull.rhels7.ppc64le.otherpkgs.pkglist
        # add the following packages 
        cuda-7.5/ppc64le/cuda-deps/dkms
        cuda-7.5/ppc64le/cuda-core/cuda

    #. Set the ``otherpkg.pkglist`` attribute for the cudafull osimage: ::

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

#. Verify that the CUDA repo created previously is available in the directory specified by the ``otherpkgdir`` attribute.  

    #. Obtain the ``otherpkgdir`` directory using the ``lsdef`` command: ::

        # lsdef -t osimage rhels7.2-ppc64le-netboot-cudaruntime -i otherpkgdir
          Object name: rhels7.2-ppc64le-netboot-cudaruntime
             otherpkgdir=/install/post/otherpkgs/rhels7.2/ppc64le

    #. Create a symbolic link to the CUDA repository in the directory specified by ``otherpkgdir`` ::

        ln -s /install/cuda-7.5 /install/post/otherpkgs/rhels7.2/ppc64le/cuda-7.5

#. Change the ``rootimgdir`` for the cudaruntime osimage: ::

    chdef -t osimage -o rhels7.2-ppc64le-netboot-cudaruntime \
       rootimgdir=/install/netboot/rhels7.2/ppc64le/cudaruntime

#. Create the ``otherpkg.pkglist`` file to do the install of the CUDA runtime packages:

    #. Create the otherpkg.pkglist file for cudaruntime: ::

        vi /install/custom/netboot/rh/cudaruntime.rhels7.ppc64le.otherpkgs.pkglist

        # Add the following packages:
        cuda-7.5/ppc64le/cuda-deps/dkms
        cuda-7.5/ppc64le/cuda-core/cuda-runtime-7-5

    #. Set the ``otherpkg.pkglist`` attribute for the cudaruntime osimage: ::

        chdef -t osimage -o rhels7.2-ppc64le-netboot-cudaruntime \
          otherpkglist=/install/custom/netboot/rh/cudaruntime.rhels7.ppc64le.otherpkgs.pkglist

#. Generate the image: ::

    genimage rhels7.2-ppc64le-netboot-cudaruntime

#. Package the image: ::

    packimage rhels7.2-ppc64le-netboot-cudaruntime

