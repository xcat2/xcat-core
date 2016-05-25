NVIDIA CUDA
===========

CUDA (Compute Unified Device Architecture) is a parallel computing platform and programming model created by NVIDIA.  It can be used to increase computing performance by leveraging the Graphics Processing Units (GPUs).

For more information, see NVIDIAs website: https://developer.nvidia.com/cuda-zone

xCAT supports CUDA installation for Ubuntu 14.04.3 and RHEL 7.2LE on PowerNV (Non-Virtualized) for both diskful and diskless nodes. 

Within the NVIDIA CUDA Toolkit, installing the ``cuda`` package will install both the ``cuda-runtime`` and the ``cuda-toolkit``.  The ``cuda-toolkit`` is intended for developing CUDA programs and monitoring CUDA jobs.  If your particular installation requires only running GPU jobs, it's recommended to install only the ``cuda-runtime`` package. 

.. toctree::
   :maxdepth: 2

   repo/index.rst
   osimage/index.rst
   deploy_cuda_node.rst
   verify_cuda_install.rst
   management.rst
   update_nvidia_driver.rst
