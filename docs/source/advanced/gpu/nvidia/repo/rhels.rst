RHEL 7.2 LE
===========


#. Create a repository on the MN node installing the CUDA Toolkit: ::

    # For cuda toolkit name: /root/cuda-repo-rhel7-7-5-local-7.5-18.ppc64le.rpm
    # extract the contents from the rpm 
    mkdir -p /tmp/cuda
    cd /tmp/cuda
    rpm2cpio /root/cuda-repo-rhel7-7-5-local-7.5-18.ppc64le.rpm | cpio -i -d

    # Create the repo directory under xCAT /install dir
    mkdir -p /install/cuda-repo/ppc64le
    cp -r /tmp/cuda/var/cuda-repo-7-5-local /install/cuda-repo/ppc64le/

    # Create the yum repo files 
    createrepo /install/cuda-repo/ppc64le
    
#. The NVIDIA CUDA Toolkit contains rpms that have dependencies on other external packages (such as ``DKMS``).  These are provided by EPEL.  It's up to the system administrator to obtain the dependency packages and add those to the ``cuda-deps`` directory: ::

    mkdir -p /install/cuda-repo/cuda-deps  
    cd /install/cuda-repo/cuda-deps

    # Copy the DKMS rpm to this directory 
    ls -ltr /install/cuda-repo/cuda-deps
    -rw-r--r-- 1 root root 79048 Oct  5 10:58 dkms-2.2.0.3-30.git.7c3e7c5.el7.noarch.rpm  

    # Execute createrepo in this directory 
    createrepo .

