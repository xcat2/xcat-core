Install NVIDIA Management Library (optional)
============================================

See https://developer.nvidia.com/nvidia-management-library-nvml for more information.

The .run file can be downloaded from NVIDIAs website and placed into the ``/install/postscripts`` directory on the Management Node. 

To enable installation of the management library after the node is install, add the .run file to the ``postbootscripts`` attribute for the nodes: :: 

   # ensure the .run file has execute permission
   chmod +x /install/postscripts/<gpu_deployment_kit>.run

   # add as the postbootscript
   chdef -t node -o <noderange> -p postbootscripts="<gpu_deployment_kit>.run \
   --silent --installdir=<your_desired_install_dir>"
