Upgrade NVIDIA Driver
=====================

If the user wants to update the newer NVIDIA driver on the system,  need to :doc:`create New CUDA software reposity </advanced/gpu/nvidia/repo/index>` .  Assume the newer driver is in the ``/install/cuda-7.5/ppc64le/nvidia_new`` for the following processes.     

Diskful
-------

#.  Change pkgdir for the cuda image: ::

      chdef -t osimage -o rhels7.2-ppc64le-install-cudafull \
        pkgdir=/install/cuda-7.5/ppc64le/nvidia_new,/install/cuda-7.5/ppc64le/cuda-deps


#.  Use xdsh command to remove all the nvidia rpms: ::
    
      xdsh <noderange> "yum remove *nvidia* -y"


#.  Run updatenode command to upgrade NVIDIA driver on the compute node: ::

      updatenode <noderange> -S


#.  Reboot compute node: ::

      rpower <noderange> off
      rpower <noderange> on


#.  Verify the newer driver level on the compute node: ::

      nvidia-smi | grep Driver




Diskless
--------

For update new NVIDIA driver on the diskless compute node, the easy and simple way is re-generate the osimage with New NIVIDIA driver reposity and re-provision the node with this osimage because node needs to be reboot in order for NIVIDIA driver to load.  Please follow :doc:`this doc </advanced/gpu/nvidia/osimage/index>` to create osimage definitions and deploy CUDA nodes. 
