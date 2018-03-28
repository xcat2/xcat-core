RHEL 7.5
========

#. Create a repository on the MN node installing the CUDA Toolkit: ::

    # For cuda toolkit name: /path/to/cuda-repo-rhel7-9-2-local-9.2.64-1.ppc64le.rpm
    # extract the contents from the rpm
    mkdir -p /tmp/cuda
    cd /tmp/cuda
    rpm2cpio /path/to/cuda-repo-rhel7-9-2-local-9.2.64-1.ppc64le.rpm | cpio -i -d

    # Create the repo directory under xCAT /install dir for cuda 9.2
    mkdir -p /install/cuda-9.2/ppc64le/cuda-core
    cp /tmp/cuda/var/cuda-repo-9-2-local/*.rpm /install/cuda-9.2/ppc64le/cuda-core

    # Create the yum repo files
    createrepo /install/cuda-9.2/ppc64le/cuda-core

#. The NVIDIA CUDA Toolkit contains rpms that have dependencies on other external packages (such as ``DKMS``).  These are provided by EPEL.  It's up to the system administrator to obtain the dependency packages and add those to the ``cuda-deps`` directory: ::

    mkdir -p /install/cuda-9.2/ppc64le/cuda-deps

    # Copy the DKMS rpm to this directory
    cp /path/to/dkms-2.4.0-1.20170926git959bd74.el7.noarch.rpm /install/cuda-9.2/ppc64le/cuda-deps

    # Execute createrepo in this directory
    createrepo /install/cuda-9.2/ppc64le/cuda-deps
