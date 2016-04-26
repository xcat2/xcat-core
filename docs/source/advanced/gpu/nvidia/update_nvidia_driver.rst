Update NVIDIA Driver
=====================

If the user wants to update the newer NVIDIA driver on the system,  follow the :doc:`Create CUDA software repository </advanced/gpu/nvidia/repo/index>` document to create another repository for the new driver.

The following example assumes the new driver is in ``/install/cuda-7.5/ppc64le/nvidia_new``.  

Diskful
-------

#.  Change pkgdir for the cuda image: ::

      chdef -t osimage -o rhels7.2-ppc64le-install-cudafull \
        pkgdir=/install/cuda-7.5/ppc64le/nvidia_new,/install/cuda-7.5/ppc64le/cuda-deps


#.  Use xdsh command to remove all the NVIDIA rpms: ::
    
      xdsh <noderange> "yum remove *nvidia* -y"


#.  Run updatenode command to update NVIDIA driver on the compute node: ::

      updatenode <noderange> -S


#.  Reboot compute node: ::

      rpower <noderange> off
      rpower <noderange> on


#.  Verify the newer driver level: ::

      nvidia-smi | grep Driver




Diskless
--------

To update a new NVIDIA driver on diskless compute nodes, re-generate the osimage pointing to the new NVIDIA driver repository and reboot the node to load the diskless image.  

Refer to :doc:`Create osimage definitions </advanced/gpu/nvidia/osimage/index>` for specific instructions. 
