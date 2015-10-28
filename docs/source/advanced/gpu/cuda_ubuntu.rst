
CUDA Installation Based on Ubuntu
=================================

Overview
--------

CUDA (Compute Unified Device Architecture) is a parallel computing platform and programming model created by NVIDIA.  It can be used by the graphics processing units (GPUs) for general purpose processing.

xCAT supports CUDA installation for Ubuntu 14.04.3 and RHEL 7.2LE on PowerNV (Non-Virtualized) for both diskless and diskful nodes.  The CUDA packages provided by NVIDIA include both the runtime libraries for computing and development tools for programming and monitoring. The full package set is very large, so in xCAT, it's suggested that the packages be split into two package sets: 

#. **cudaruntime** package set 
#. **cudafull** package set  

It's suggested to only installing the **cudaruntime** package set on the Compute Nodes (CNs), and the **cudafull** package set on the Management Node or the monitor/development nodes.

In this documentation, xCAT will provide CUDA installation based on Ubuntu 14.04.3 running on IBM Power Systems S822LC nodes.


CUDA Repository
---------------

Currently, there are 2 types of Ubuntu repos for installing cuda-7-0 on p8LE hardware: `The online repo <http://developer.download.nvidia.com/compute/cuda/repos/ubuntu1404/ppc64el/cuda-repo-ubuntu1404_7.0-28_ppc64el.deb>`_ and `The local package repo <http://developer.download.nvidia.com/compute/cuda/7_0/Prod/local_installers/rpmdeb/cuda-repo-ubuntu1404-7-0-local_7.0-28_ppc64el.deb>`_. 

**The online repo**

The online repo will provide a sourcelist entry which includes the URL with the location of the cuda packages. The online repo can be used directly by Compute Nodes. The source.list entry will be similar to: ::

   deb http://developer.download.nvidia.com/compute/cuda/repos/ubuntu1410/ppc64el /

**The local package repo**

A local package repo will contain all of the cuda packages.The admin can either simply install the local repo (need to copy the whole /var/cuda-repo-7-0-local/ to /install/cuda-repo/)or extract the cuda packages into the local repo with the following command: ::

   dpkg -x cuda-repo-ubuntu14xx-7-0-local_7.0-28_ppc64el.deb /install/cuda-repo/

The following repos will be used in the test environment:

* "/install/ubuntu14.04.2/ppc64el": The OS image package directory
* "http://ports.ubuntu.com/ubuntu-ports": The internet mirror, if there is local mirror available, it can be replaced
* "http://10.3.5.10/install/cuda-repo/var/cuda-repo-7-0-local /": The repo for cuda, you can replaced it with online cuda repo.


CUDA osimage
------------
User can generate a new CUDA osimage object based on another osimage definition or just modify an existing osimage.  xCAT provides some sample CUDA pkglist files:


* diskful provisioning in ``/opt/xcat/share/install/ubuntu/`` for ``cudafull`` and ``cudaruntime``:  :: 


    #cat /opt/xcat/share/xcat/install/ubuntu/cudafull.ubuntu14.04.3.ppc64el.pkglist
      #INCLUDE:compute.ubuntu14.04.3.ppc64el.pkglist#
      linux-headers-generic-lts-utopic
      build-essential
      dkms
      
      zlib1g-dev
      
      cuda
    #cat /opt/xcat/share/xcat/install/ubuntu/cudaruntime.ubuntu14.04.3.ppc64el.pkglist
      #INCLUDE:compute.ubuntu14.04.3.ppc64el.pkglist#
      linux-headers-generic-lts-utopic
      build-essential
      dkms
      
      zlib1g-dev
      
      cuda-runtime-7-0


* diskless provisioning in ``/opt/xcat/share/xcat/netboot/ubuntu`` for ``cudafull`` and ``cudaruntime``: ::


    #cat /opt/xcat/share/xcat/netboot/ubuntu/cudafull.ubuntu14.04.3.ppc64el.pkglist
      #INCLUDE:compute.ubuntu14.04.3.ppc64el.pkglist#
      linux-headers-generic-lts-utopic
      
      build-essential
      zlib1g-dev
      dkms
    #cat /opt/xcat/share/xcat/netboot/ubuntu/cudaruntime.ubuntu14.04.3.ppc64el.pkglist
      #INCLUDE:compute.ubuntu14.04.3.ppc64el.pkglist#
      linux-headers-generic-lts-utopic

      build-essential
      zlib1g-dev
      dkms



The following are some sample osimage definitions:   

* The diskful cudafull installation osimage object. ::

    #lsdef -t osimage ubuntu14.04.3-ppc64el-install-cudafull
      Object name: ubuntu14.04.3-ppc64el-install-cudafull
      imagetype=linux
      osarch=ppc64el
      osname=Linux
      osvers=ubuntu14.04.3
      otherpkgdir=/install/post/otherpkgs/ubuntu14.04.3/ppc64el
      pkgdir=http://ports.ubuntu.com/ubuntu-ports trusty main,http://ports.ubuntu.com/ubuntu-ports trusty-updates main,http://10.3.5.10/install/cuda-repo/var/cuda-repo-7-0-local /,/install/ubuntu14.04.3/ppc64el
      pkglist=/opt/xcat/share/xcat/install/ubuntu/cudafull.ubuntu14.04.3.ppc64el.pkglist
      profile=cudafull
      provmethod=install
      template=/opt/xcat/share/xcat/install/ubuntu/cudafull.tmpl


	  
* The diskful cudaruntime installation osimage object. ::

    #lsdef -t osimage ubuntu14.04.3-ppc64el-install-cudaruntime                          
      Object name: ubuntu14.04.3-ppc64el-install-cudaruntime
      imagetype=linux
      osarch=ppc64el
      osname=Linux
      osvers=ubuntu14.04.3
      otherpkgdir=/install/post/otherpkgs/ubuntu14.04.3/ppc64el
      pkgdir=http://ports.ubuntu.com/ubuntu-ports trusty main,http://ports.ubuntu.com/ubuntu-ports trusty-updates main,http://10.3.5.10/install/cuda-repo/var/cuda-repo-7-0-local /,/install/ubuntu14.04.3/ppc64el
      pkglist=/opt/xcat/share/xcat/install/ubuntu/cudaruntime.ubuntu14.04.3.ppc64el.pkglist
      profile=cudaruntime
      provmethod=install
      template=/opt/xcat/share/xcat/install/ubuntu/cudaruntime.tmpl



* The diskless cudafull installation osimage object. ::

    #Object name: ubuntu14.04.3-ppc64el-netboot-cudafull
      imagetype=linux
      osarch=ppc64el
      osname=Linux
      osvers=ubuntu14.04.3
      otherpkgdir=http://10.3.5.10/install/cuda-repo/var/cuda-repo-7-0-local /
      otherpkglist=/opt/xcat/share/xcat/netboot/ubuntu/cudafull.otherpkgs.pkglist
      permission=755
      pkgdir=http://ports.ubuntu.com/ubuntu-ports trusty main,http://ports.ubuntu.com/ubuntu-ports trusty-updates main,/install/ubuntu14.04.3/ppc64el
      pkglist=/opt/xcat/share/xcat/netboot/ubuntu/cudafull.ubuntu14.04.3.ppc64el.pkglist
      profile=cudafull
      provmethod=netboot
      rootimgdir=/install/netboot/ubuntu14.04.3/ppc64el/cudafull



* The diskless cudaruntime installation osimage object. ::

    #Object name: ubuntu14.04.3-ppc64el-netboot-cudaruntime
      imagetype=linux
      osarch=ppc64el
      osname=Linux
      osvers=ubuntu14.04.3
      otherpkgdir=http://10.3.5.10/install/cuda-repo/var/cuda-repo-7-0-local /
      otherpkglist=/opt/xcat/share/xcat/netboot/ubuntu/cudaruntime.otherpkgs.pkglist
      permission=755
      pkgdir=http://ports.ubuntu.com/ubuntu-ports trusty main,http://ports.ubuntu.com/ubuntu-ports trusty-updates main,/install/ubuntu14.04.3/ppc64el
      pkglist=/opt/xcat/share/xcat/netboot/ubuntu/cudaruntime.ubuntu14.04.3.ppc64el.pkglist
      profile=cudaruntime
      provmethod=netboot
      rootimgdir=/install/netboot/ubuntu14.04.3/ppc64el/cudaruntime



**Use addcudakey postscript to install GPGKEY for cuda packages**

In order to access the cuda repo and authorize it, you will need to import the cuda GPGKEY into the apt key trust list.The following command can be used to add a postscript for a node that will install cuda. ::

   chdef <node> -p postscripts=addcudakey

**Install NVML (optional, for nodes which need to compile cuda related applications)**

The NVIDIA Management Library (NVML) is a C-based programmatic interface for monitoring and managing various states within NVIDIA Tesla GPUs. It is intended to be a platform for building 3rd party applications.

The NVML can be download from http://developer.download.nvidia.com/compute/cuda/7_0/Prod/local_installers/cuda_346.46_gdk_linux.run.

After download NVML and put it under /install/postscripts on MN, the following steps can be used to have NVML installed after the node is installed and rebooted if needed. ::

   chmod +x  /install/postscripts/cuda_346.46_gdk_linux.run
   chdef <node> -p postbootscripts="cuda_346.46_gdk_linux.run --silent --installdir=<you_desired_dir>"

Deployment of CUDA node
-----------------------

* To provision diskful nodes: ::

    nodeset <node> osimage=<diskfull_osimage_object_name>
    rsetboot <node> net
    rpower <node> boot 
	
* To provision diskless nodes:

To generate stateless image for a diskless installation, the acpid is needed to be installed on MN or the host on which you generate stateless image. ::

    apt-get  install -y acpid

Then, use the following commands to generate stateless image and pack it. ::

    genimage <diskless_osimage_object_name>
    packimage <diskless_osimage_object_name>
    nodeset <node> osimage=<diskless_osimage_object_name>
    rsetboot <node> net
    rpower <node> boot


Verification of CUDA Installation
---------------------------------

The command below can be used to display GPU or Unit info on the node. ::

    nvidia-smi -q

Verify the Driver Version. ::
    
    # cat /proc/driver/nvidia/version
      NVRM version: NVIDIA UNIX ppc64le Kernel Module  346.46  Tue Feb 17 17:18:33 PST 2015
      GCC version:  gcc version 4.8.4 (Ubuntu 4.8.4-2ubuntu1~14.04)

**GPU management and monitoring**

The tool "nvidia-smi" provided by NVIDIA driver can be used to do GPU management and monitoring, but it can only be run on the host where GPU hardware, CUDA and NVIDIA driver is installed. The xdsh can be used to run "nvidia-smi" on GPU host remotely from xCAT management node.

The using of xdsh will be like this: ::

    # xdsh p8le-42l "nvidia-smi -i 0 --query-gpu=name,serial,uuid --format=csv,noheader"
      p8le-42l: Tesla K40m, 0324114102927, GPU-8750df00-40e1-8a39-9fd8-9c29905fa127

Some of the useful nvidia-smi command for monitoring and managing of GPU are as belows, for more information, pls read nvidia-smi manpage.

* For monitoring: ::
	
    *The number of NVIDIA GPUs in the system.
      nvidia-smi --query-gpu=count --format=csv,noheader
    *The version of the installed NVIDIA display driver
      nvidia-smi -i 0 --query-gpu=driver_version --format=csv,noheader
    *The BIOS of the GPU board
      nvidia-smi -i 0 --query-gpu=vbios_version --format=csv,noheader
    *Product name, serial number and UUID of the GPU
      nvidia-smi -i 0 --query-gpu=name,serial,uuid --format=csv,noheader
    *Fan speed
      nvidia-smi -i 0 --query-gpu=fan.speed --format=csv,noheader
    *The compute mode flag indicates whether individual or multiple compute applications may run on the GPU. Also known as exclusivity modes
      nvidia-smi -i 0 --query-gpu=compute_mode --format=csv,noheader
    *Percent of time over the past sample period during which one or more kernels was executing on the GPU
      nvidia-smi -i 0 --query-gpu=utilization.gpu --format=csv,noheader
    *Total errors detected across entire chip. Sum of device_memory, register_file, l1_cache, l2_cache and texture_memory
      nvidia-smi -i 0 --query-gpu=ecc.errors.corrected.aggregate.total --format=csv,noheader
    *Core GPU temperature, in degrees C
      nvidia-smi -i 0 --query-gpu=temperature.gpu --format=csv,noheader
    *The ECC mode that the GPU is currently operating under
      nvidia-smi -i 0 --query-gpu=ecc.mode.current --format=csv,noheader
    *The power management status
      nvidia-smi -i 0 --query-gpu=power.management --format=csv,noheader
    *The last measured power draw for the entire board, in watts
      nvidia-smi -i 0 --query-gpu=power.draw --format=csv,noheader
    *The minimum and maximum value in watts that power limit can be set to.
      nvidia-smi -i 0 --query-gpu=power.min_limit,power.max_limit --format=csv
	
* For management: ::
	
    *Set persistence mode, When persistence mode is enabled the NVIDIA driver remains loaded even when no active clients, DISABLED by default
      nvidia-smi -i 0 -pm 1
    *Disabled ECC support for GPU. Toggle ECC support, A flag that indicates whether ECC support is enabled, need to use --query-gpu=ecc.mode.pending to check. Reboot required.
      nvidia-smi -i 0 -e 0
    *Reset the ECC volatile/aggregate error counters for the target GPUs
      nvidia-smi -i 0 -p 0/1
    *Set MODE for compute applications, query with --query-gpu=compute_mode
      nvidia-smi -i 0 -c 0/1/2/3
    *Trigger reset of the GPU.
      nvidia-smi -i 0 -r
    *Enable or disable Accounting Mode, statistics can be calculated for each compute process running on the GPU, query with -query-gpu=accounting.mode
      nvidia-smi -i 0 -am 0/1
    *Specifies maximum power management limit in watts, query with --query-gpu=power.limit.
      nvidia-smi -i 0 -pl 200

**Installing CUDA example applications**

The cuda-samples-7-0 pkgs include some CUDA examples which can help uses to know how to use cuda.For a node which only cuda runtime libraries installed, the following command can be used to install cuda-samples package. ::

    apt-get install cuda-samples-7-0 -y
	
After cuda-sample-7-0 has been installed, go to /usr/local/cuda-7.0/samples to build the examples. See this link https://developer.nvidia.com/ for more information. Or, you can simply run the make command under dir /usr/local/cuda-7.0/samples to build all the tools.

The following command can be used to build the deviceQuery tool in the cuda samples directory: ::

    # pwd
      /usr/local/cuda-7.0/samples
    # make -C 1_Utilities/deviceQuery 
      make: Entering directory `/usr/local/cuda-7.0/samples/1_Utilities/deviceQuery'
      /usr/local/cuda-7.0/bin/nvcc -ccbin g++ -I../../common/inc  -m64    -gencode arch=compute_20,code=sm_20 -gencode arch=compute_30,code=sm_30 -gencode arch=compute_35,code=sm_35 -gencode arch=compute_37,code=sm_37 -gencode arch=compute_50,code=sm_50 -gencode arch=compute_52,code=sm_52 -gencode arch=compute_52,code=compute_52 -o deviceQuery.o -c deviceQuery.cpp
      /usr/local/cuda-7.0/bin/nvcc -ccbin g++   -m64      -gencode arch=compute_20,code=sm_20 -gencode arch=compute_30,code=sm_30 -gencode arch=compute_35,code=sm_35 -gencode arch=compute_37,code=sm_37 -gencode arch=compute_50,code=sm_50 -gencode arch=compute_52,code=sm_52 -gencode arch=compute_52,code=compute_52 -o deviceQuery deviceQuery.o 
      mkdir -p ../../bin/ppc64le/linux/release
      cp deviceQuery ../../bin/ppc64le/linux/release
      make: Leaving directory `/usr/local/cuda-7.0/samples/1_Utilities/deviceQuery'

The verification results from this example on a test node were: ::

    # pwd
      /usr/local/cuda-7.0/samples
    # bin/ppc64le/linux/release/deviceQuery 
      bin/ppc64le/linux/release/deviceQuery Starting...
      CUDA Device Query (Runtime API) version (CUDART static linking)
      Detected 4 CUDA Capable device(s)
	  Device 0: "Tesla K80"
        CUDA Driver Version / Runtime Version          7.0 / 7.0
        CUDA Capability Major/Minor version number:    3.7
        Total amount of global memory:                 11520 MBytes (12079136768 bytes)
        (13) Multiprocessors, (192) CUDA Cores/MP:     2496 CUDA Cores
        GPU Max Clock rate:                            824 MHz (0.82 GHz)
        Memory Clock rate:                             2505 Mhz
        Memory Bus Width:                              384-bit
        L2 Cache Size:                                 1572864 bytes
        Maximum Texture Dimension Size (x,y,z)         1D=(65536), 2D=(65536, 65536), 3D=(4096, 4096, 4096)
        Maximum Layered 1D Texture Size, (num) layers  1D=(16384), 2048 layers
        Maximum Layered 2D Texture Size, (num) layers  2D=(16384, 16384), 2048 layers
        Total amount of constant memory:               65536 bytes
        Total amount of shared memory per block:       49152 bytes
        Total number of registers available per block: 65536
        Warp size:                                     32
        Maximum number of threads per multiprocessor:  2048
        Maximum number of threads per block:           1024
        Max dimension size of a thread block (x,y,z): (1024, 1024, 64)
        Max dimension size of a grid size    (x,y,z): (2147483647, 65535, 65535)
        Maximum memory pitch:                          2147483647 bytes
        Texture alignment:                             512 bytes
        Concurrent copy and kernel execution:          Yes with 2 copy engine(s)
        Run time limit on kernels:                     No
        Integrated GPU sharing Host Memory:            No
        Support host page-locked memory mapping:       Yes
        Alignment requirement for Surfaces:            Yes
        Device has ECC support:                        Enabled
        Device supports Unified Addressing (UVA):      Yes
        Device PCI Domain ID / Bus ID / location ID:   0 / 3 / 0
        Compute Mode:
           < Default (multiple host threads can use ::cudaSetDevice() with device simultaneously) >
      Device 1: "Tesla K80"
        CUDA Driver Version / Runtime Version          7.0 / 7.0
        ......
