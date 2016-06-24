GPU Management and Monitoring
=============================

The ``nvidia-smi`` command provided by NVIDIA can be used to manage and monitor GPUs enabled Compute Nodes. In conjunction with the xCAT``xdsh`` command, you can easily manage and monitor the entire set of GPU enabled Compute Nodes remotely from the Management Node. 

Example: ::

    # xdsh <noderange> "nvidia-smi -i 0 --query-gpu=name,serial,uuid --format=csv,noheader"
    node01: Tesla K80, 0322415075970, GPU-b4f79b83-c282-4409-a0e8-0da3e06a13c3
    ...



**Note: The following commands are provided as convenience.**  *Always consult the nvidia-smi manpage for the latest supported functions.*

Management
----------

Some useful ``nvidia-smi`` example commands for management.  

	
    * Set persistence mode, When persistence mode is enabled the NVIDIA driver remains loaded even when no active clients, DISABLED by default::

        nvidia-smi -i 0 -pm 1

    * Disabled ECC support for GPU. Toggle ECC support, A flag that indicates whether ECC support is enabled, need to use --query-gpu=ecc.mode.pending to check [Reboot required]::

        nvidia-smi -i 0 -e 0

    * Reset the ECC volatile/aggregate error counters for the target GPUs::

        nvidia-smi -i 0 -p 0/1

    * Set MODE for compute applications, query with --query-gpu=compute_mode:: 

        nvidia-smi -i 0 -c 0/1/2/3

    * Trigger reset of the GPU :: 

        nvidia-smi -i 0 -r

    * Enable or disable Accounting Mode, statistics can be calculated for each compute process running on the GPU, query with -query-gpu=accounting.mode::

        nvidia-smi -i 0 -am 0/1

    * Specifies maximum power management limit in watts, query with --query-gpu=power.limit ::

        nvidia-smi -i 0 -pl 200
	
Monitoring
----------

Some useful ``nvidia-smi`` example commands for monitoring.  

    * The number of NVIDIA GPUs in the system ::

        nvidia-smi --query-gpu=count --format=csv,noheader

    * The version of the installed NVIDIA display driver ::

        nvidia-smi -i 0 --query-gpu=driver_version --format=csv,noheader

    * The BIOS of the GPU board ::

        nvidia-smi -i 0 --query-gpu=vbios_version --format=csv,noheader

    * Product name, serial number and UUID of the GPU::

        nvidia-smi -i 0 --query-gpu=name,serial,uuid --format=csv,noheader

    * Fan speed::

        nvidia-smi -i 0 --query-gpu=fan.speed --format=csv,noheader

    * The compute mode flag indicates whether individual or multiple compute applications may run on the GPU. (known as exclusivity modes) ::

        nvidia-smi -i 0 --query-gpu=compute_mode --format=csv,noheader

    * Percent of time over the past sample period during which one or more kernels was executing on the GPU::
 
        nvidia-smi -i 0 --query-gpu=utilization.gpu --format=csv,noheader

    * Total errors detected across entire chip. Sum of device_memory, register_file, l1_cache, l2_cache and texture_memory ::

        nvidia-smi -i 0 --query-gpu=ecc.errors.corrected.aggregate.total --format=csv,noheader

    * Core GPU temperature, in degrees C::

        nvidia-smi -i 0 --query-gpu=temperature.gpu --format=csv,noheader

    * The ECC mode that the GPU is currently operating under:: 

        nvidia-smi -i 0 --query-gpu=ecc.mode.current --format=csv,noheader

    * The power management status::

        nvidia-smi -i 0 --query-gpu=power.management --format=csv,noheader
 
    * The last measured power draw for the entire board, in watts::

        nvidia-smi -i 0 --query-gpu=power.draw --format=csv,noheader

    * The minimum and maximum value in watts that power limit can be set to ::

        nvidia-smi -i 0 --query-gpu=power.min_limit,power.max_limit --format=csv


