Verify CUDA Installation
========================

**The following verification steps only apply to the ``cudafull`` installations.**

#. Verify driver version by looking at: ``/proc/driver/nvidia/version``: ::
  
    # cat /proc/driver/nvidia/version
     NVRM version: NVIDIA UNIX ppc64le Kernel Module  352.39  Fri Aug 14 17:10:41 PDT 2015
     GCC version:  gcc version 4.8.5 20150623 (Red Hat 4.8.5-4) (GCC) 

#. Verify the CUDA Toolkit version ::

    # nvcc -V
     nvcc: NVIDIA (R) Cuda compiler driver
     Copyright (c) 2005-2015 NVIDIA Corporation
     Built on Tue_Aug_11_14:31:50_CDT_2015
     Cuda compilation tools, release 7.5, V7.5.17

#. Verify running CUDA GPU jobs by compiling the samples and executing the ``deviceQuery`` or ``bandwidthTest`` programs.

   * Compile the samples: 

     **[RHEL]:** ::

        cd ~/
        cuda-install-samples-7.5.sh .
        cd NVIDIA_CUDA-7.5_Samples
        make

     **[Ubuntu]:** ::

        cd ~/
        apt-get install cuda-samples-7-0 -y
        cd /usr/local/cuda-7.0/samples 
        make 


   * Run the ``deviceQuery`` sample: ::

        # ./bin/ppc64le/linux/release/deviceQuery   
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
   
   * Run the ``bandwidthTest`` sample: ::
 
        # ./bin/ppc64le/linux/release/bandwidthTest
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
    
