
CUDA Installation
=================

Overview
--------

CUDA (Compute Unified Device Architecture) is a parallel computing platform and programming model created by NVIDIA.  It can be used by the graphics processing units (GPUs) for general purpose processing.

xCAT supports CUDA installation for Ubuntu and rhel7.2 on PowerNV (p8le node with Nvidia GPU Support) for both diskless and diskfull nodes.  The cuda packages provided by nvidia include both the runtime libraries for computing and dev tools for programming and monitoring. In xCAT, we split the packages into 2 groups: the cudaruntime package set and the cudafull package set.  Since the full package set is so large. xCAT suggests only installing the runtime libraries on the Compute Nodes (CNs), and the full cuda package set on the Management Node or the monitor/development nodes.

In this documentation, xCAT will provide only installation for CUDA on rhel7.2 power 8 firestone nodes.  User can find Ubuntu cuda installation document here: http://sourceforge.net/p/xcat/wiki/xCAT_P8LE_cuda_installing/


Install xCAT MN
---------------

Follow the instructions in  ``XCAT_P8LE_Hardware_Management`` to install xCAT Management Node and do hardware discovery for p8le nodes.

CUDA Repository
---------------

The Nividia CUDA Toolkit is available at http://developer.nvidia.com/cuda-downloads.  User can download the CUDA Toolkit based on the target platform.  Currently, this download site didn't provide the CUDA Toolkit for rhel7.2 ppc64le. The Users need to pull the package from Nvidia partner site with user id and passwords. 

Prepare a local repo directory which contains all the CUDA packages and repository meta-data.  ::


  #mkdir -p /install/cuda-repo/cuda-7-5   
  #rpm -ivh cuda-repo-rhel7-7-5-local-7.5-18.ppc64le.rpm
  #cp /var/cuda-repo-7-5-local/* /install/cuda-repo/cuda-7-5
  #cd /install/cuda-repo/cuda-7-5
  #createrepo .


or if don't want to install cuda on the MN node, do ::

   
  #mkdir -p /tmp/cuda
  #cd /tmp/cuda
  #rpm2cpio /root/cuda-repo-rhel7-7-5-local-7.5-18.ppc64le.rpm | cpio -i -d
  #cp /tmp/cuda/var/cuda-repo-7-5-local/* /install/cuda-repo/cuda-7-5
  #cd /install/cuda-repo/cuda-7-5
  #createrepo .


The NVIDIA driver RPM packages depend on other external packages, such as DKMS and maybe EPEL (firestone node doesn't need this package).  Users need to download those package to the directory. ::
   
  #mkdir -p /install/cuda-repo/cuda-deps  
  #ls -ltr /install/cuda-repo/cuda-deps
    -rw-r--r-- 1 root root 79048 Oct  5 10:58 dkms-2.2.0.3-30.git.7c3e7c5.el7.noarch.rpm  
  #cd /install/cuda-repo/cuda-deps
  #createrepo .



CUDA osimage
------------
User can generate own CUDA osimage object based on the definition or just modify existing osimage.  xCAT provides sample cuda pkglist file which defined in the pkgdir for CUDA osimage. ::

  # cat /opt/xcat/share/xcat/install/rh/cudafull.rhels7.pkglist
    #INCLUDE:compute.rhels7.pkglist#
    #For Cuda 7.5
    kernel-devel
    gcc
    pciutils
    dkms
    cuda
  # cat /opt/xcat/share/xcat/install/rh/cudaruntime.rhels7.pkglist
    #INCLUDE:compute.rhels7.pkglist#
    #For Cuda 7.5
    kernel-devel
    gcc
    pciutils
    dkms
    cuda-runtime-7-5

Similar pkglist files are created for diskless osimage also in the ``/opt/xcat/share/xcat/netboot/rh`` directory  ::

  # cat /opt/xcat/share/xcat/netboot/rh/cudafull.rhels7.ppc64le.pkglist
    #INCLUDE:compute.rhels7.ppc64.pkglist#
    #For Cuda 7.5
    kernel-devel
    gcc
    pciutils
    dkms
    cuda
  # cat /opt/xcat/share/xcat/netboot/rh/cudaruntime.rhels7.ppc64le.pkglist
    #INCLUDE:compute.rhels7.ppc64.pkglist#
    #For Cuda 7.5
    kernel-devel
    gcc
    pciutils
    dkms
    cuda-runtime-7-5


After installed cuda, the nodes have to be reboot, so for the diskfull installation,  the cuda packages should be included in the pkglist.  for the diskless installation, the cuda package can be put either in otherpkglist or pktlist.  Following shows the definition for each cuda osimage object.  
 
* The diskfull cudafull installation osimage object. ::

    #lsdef -t osimage rhels7.2-ppc64le-install-cudafull
      Object name: rhels7.2-ppc64le-install-cudafull
      imagetype=linux
      osarch=ppc64le
      osdistroname=rhels7.2-ppc64le
      osname=Linux
      osvers=rhels7.2
      otherpkgdir=/install/post/otherpkgs/rhels7.2/ppc64le
      pkgdir=/install/rhels7.2/ppc64le,/install/cuda-repo
      pkglist=/opt/xcat/share/xcat/install/rh/cudafull.rhels7.pkglist
      profile=compute
      provmethod=install
      template=/opt/xcat/share/xcat/install/rh/compute.rhels7.tmpl


* The diskfull cudaruntime installation osimage object. ::

    #lsdef -t osimage rhels7.2-ppc64le-install-cudaruntime
      Object name: rhels7.2-ppc64le-install-cudaruntime
      imagetype=linux
      osarch=ppc64le
      osdistroname=rhels7.2-ppc64le
      osname=Linux
      osvers=rhels7.2
      otherpkgdir=/install/post/otherpkgs/rhels7.2/ppc64le
      pkgdir=/install/rhels7.2/ppc64le,/install/cuda-repo
      pkglist=/opt/xcat/share/xcat/install/rh/cudairuntime.rhels7.pkglist
      profile=compute
      provmethod=install
      template=/opt/xcat/share/xcat/install/rh/compute.rhels7.tmpl


* The diskless cudafull installation osimage object. ::

    #lsdef -t osimage rhels7.2-ppc64le-netboot-cudafull
      Object name: rhels7.2-ppc64le-netboot-cudafull
      imagetype=linux
      osarch=ppc64le
      osdistroname=rhels7.2-ppc64le
      osname=Linux
      osvers=rhels7.2
      otherpkgdir=/install/post/otherpkgs/rhels7.2/ppc64le
      permission=755
      pkgdir=/install/rhels7.2/ppc64le,/install/cuda-repo
      pkglist=/opt/xcat/share/xcat/netboot/rh/cudafull.rhels7.ppc64le.pkglist
      postinstall=/opt/xcat/share/xcat/netboot/rh/compute.rhels7.ppc64le.postinstall
      profile=compute
      provmethod=netboot
      rootimgdir=/install/netboot/rhels7.2/ppc64le/compute


* The diskless cudaruntime installation osimage object. ::

    #lsdef -t osimage rhels7.2-ppc64le-netboot-cudaruntime
      Object name: rhels7.2-ppc64le-netboot-cudaruntime
      imagetype=linux
      osarch=ppc64le
      osdistroname=rhels7.2-ppc64le
      osname=Linux
      osvers=rhels7.2
      otherpkgdir=/install/post/otherpkgs/rhels7.2/ppc64le
      permission=755
      pkgdir=/install/rhels7.2/ppc64le,/install/cuda-repo
      pkglist=/opt/xcat/share/xcat/netboot/rh/cudaruntime.rhels7.ppc64le.pkglist
      postinstall=/opt/xcat/share/xcat/netboot/rh/compute.rhels7.ppc64le.postinstall
      profile=compute
      provmethod=netboot
      rootimgdir=/install/netboot/rhels7.2/ppc64le/compute



Deployment of CUDA node
-----------------------

Follow the instructions in ``xCAT_p8LE_Hardware_Management`` to perform OS provisioning for the p8le compute nodes.  Then use the osimage object generated above to do the OS provisioning 

* For diskfull nodes: ::


    #nodeset <node> osimage=rhels7.2-ppc64le-install-cudafull
    #rsetboot <node> net
    #rpower <node> boot 


* For diskless nodes: ::

    
    #genimage rhels7.2-ppc64le-netboot-cudafull
    #packimage rhels7.2-ppc64le-netboot-cudafull
    #nodeset <node> osimage=rhels7.2-ppc64le-netboot-cudafull
    #rsetboot <node> net
    #rpower <node> boot 



Verification of CUDA Installation
---------------------------------
  
After compute node booted, The Environment variable has to be set in order to use the CUDA toolkits.  The PATH variable needs to include ``/usr/local/cuda-7.5/bin`` and LD_LIBRARY_PATH variable needs to contain ``/usr/local/cuda-7.5/lib64`` on a 64-bit system, and ``/usr/local/cuda-7.5`` on a 32-bit system.

* To change the environment variables for 64-bit operating systems ::

    #export PATH=/usr/local/cuda-7.5/bin:$PATH
    #export LD_LIBRARY_PATH=/usr/local/cuda-7.5/lib64:$LD_LIBRARY_PATH


* To change the environment variable for 32-bit operating systems ::

    #export PATH=/usr/local/cuda-7.5/bin:$PATH
    #export LD_LIBRARY_PATH=/usr/local/cuda-7.5/lib:$LD_LIBRARY_PATH

After Environment variables are set correctly, user can verify the cuda installation by
  
* Verify the Driver Version ::
    
    #cat /proc/driver/nvidia/version
      NVRM version: NVIDIA UNIX ppc64le Kernel Module  352.39  Fri Aug 14 17:10:41 PDT 2015
      GCC version:  gcc version 4.8.5 20150623 (Red Hat 4.8.5-4) (GCC) 

* The version of the CUDA Toolkits ::

    #nvcc -V
     nvcc: NVIDIA (R) Cuda compiler driver
     Copyright (c) 2005-2015 NVIDIA Corporation
     Built on Tue_Aug_11_14:31:50_CDT_2015
     Cuda compilation tools, release 7.5, V7.5.17

* Compiling the Examples, then can run a `deviceQuery` or `bandwidthTest` or other commands under the bin directory to ensure the system and the CUDA-capable device are able to communicate correctly  ::
  
    # mkdir -p /tmp/cuda
    # cuda-install-samples-7.5.sh /tmp/cuda
    # cd /tmp/cuda/NVIDIA_CUDA-7.5_Samples
    # make
    # cd bin/ppc64le/linux/release
    # ./deviceQuery   
      ./deviceQuery Starting...
      CUDA Device Query (Runtime API) version (CUDART static linking)
      Detected 4 CUDA Capable device(s)
      Device 0: "Tesla K80"
        CUDA Driver Version / Runtime Version          7.5 / 7.5
        CUDA Capability Major/Minor version number:    3.7
        Total amount of global memory:                 11520 MBytes (12079136768 bytes)
        (13) Multiprocessors, (192) CUDA Cores/MP:     2496 CUDA Cores
        GPU Max Clock rate:                            824 MHz (0.82 GHz)
        Memory Clock rate:                             2505 Mhz
        Memory Bus Width:                              384-bit
        L2 Cache Size:                                 1572864 bytes
        ............
        deviceQuery, CUDA Driver = CUDART, CUDA Driver Version = 7.5, CUDA Runtime Version = 7.5, NumDevs = 4, Device0 = Tesla K80, Device1 = Tesla K80, Device2 = Tesla K80, Device3 = Tesla K80
        Result = PASS

    # ./bandwidthTest
      [CUDA Bandwidth Test] - Starting...
      Running on...
      Device 0: Tesla K80
      Quick Mode
      Host to Device Bandwidth, 1 Device(s)
      PINNED Memory Transfers
        Transfer Size (Bytes)        Bandwidth(MB/s)
        33554432                     7765.1
      Device to Host Bandwidth, 1 Device(s)
      PINNED Memory Transfers
        Transfer Size (Bytes)        Bandwidth(MB/s)
        33554432                     7759.6

      Device to Device Bandwidth, 1 Device(s)
      PINNED Memory Transfers
        Transfer Size (Bytes)        Bandwidth(MB/s)
        33554432                     141485.3

      Result = PASS

      NOTE: The CUDA Samples are not meant for performance measurements. Results may vary when GPU Boost is enabled.



* The tool `nvidia-smi` providied by NVIDIA driver can be used to do GPU management and monitoring. ::

   #nvidia-smi -q
     ==============NVSMI LOG==============

     Timestamp                           : Mon Oct  5 13:43:39 2015
     Driver Version                      : 352.39

     Attached GPUs                       : 4
     GPU 0000:03:00.0
     Product Name                    : Tesla K80
     Product Brand                   : Tesla
     ...........................


    






  

