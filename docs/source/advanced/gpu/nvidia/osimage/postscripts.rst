Postscripts
===========

The following sections demonstrates how to use xCAT to configure post-installation steps

Setting PATH and LD_LIBRARY_PATH
--------------------------------

NVIDIA recommends various post-installation actions that should be performed to properly configure the nodes.  A sample script is provided by xCAT for this purpose ``config_cuda`` and can be modified to fit your specific installation.

Add this script to your node object using the ``chdef`` command: ::

    chdef -t node -o <noderange> -p postscripts=config_cuda


Setting GPU Configurations
--------------------------

NVIDIA allows for changing GPU attributes using the ``nvidia-smi`` commands.  These settings do not persist when a compute node is rebooted.  One way set these attributes is to use an xCAT postscript to set the values every time the node is rebooted.  


* Set the power limit to 175W: ::

    # set the power limit to 175W
    nvidia-smi -pl 175


*  Set the GPUs to persistence mode to increase performance: ::

    # nvidia-smi -pm 1
    Enabled persistence mode for GPU 0000:03:00.0.
    Enabled persistence mode for GPU 0000:04:00.0.
    Enabled persistence mode for GPU 0002:03:00.0.
    Enabled persistence mode for GPU 0002:04:00.0.
    All done.
