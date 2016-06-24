Ubuntu 14.04.3
==============

NVIDIA supports two types of debian repositories that can be used to install Cuda Toolkit: **local** and **network**.  You can download the installers from https://developer.nvidia.com/cuda-downloads.

Local
-----

A local package repo will contain all of the CUDA packages.  Extract the CUDA packages into ``/install/cuda-repo/ppc64le``: ::

    # For CUDA toolkit: /root/cuda-repo-ubuntu1404-7-5-local_7.5-18_ppc64el.deb
    
    # Create the repo directory under xCAT /install dir
    mkdir -p /install/cuda-repo/ppc64el

    # extract the package
    dpkg -x /root/cuda-repo-ubuntu1404-7-5-local_7.5-18_ppc64el.deb /install/cuda-repo/ppc64el

    

Network
-------

The online package repo provides a source list entry pointing to a URL containing the CUDA packages.  This can be used directly on the Compute Nodes.

The ``sources.list`` entry may look similar to: ::

   deb http://developer.download.nvidia.com/compute/cuda/repos/ubuntu1410/ppc64el /


Authorize the CUDA repo
-----------------------

In order to access the CUDA repository you must import the CUDA GPGKEY into the ``apt_key`` trust list.  xCAT provides a sample postscript ``/install/postscripts/addcudakey`` to help with this task: :: 

   chdef -t node -o <noderange> -p postscripts=addcudakey

