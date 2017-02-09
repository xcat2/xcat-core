Switch Management
=================

VLAN Configuration
------------------

xCAT ships a simple configuration script that will set all the ports on the switch to be part of VLAN 1.  See the Cumulus Networks documentation for more information regarding advanced networking configuration. ::

    updatenode <switch> -P configinterface


Re-install OS
-------------

There may be occasions where a re-install of the OS is required.   Assuming the files are available on the xCAT management node, the following commands will invoke the install process: 

* **[use xCAT]** ``xdsh`` can be used to invoke the reinstall of the OS: ::

    xdsh <switch> "/usr/cumulus/bin/onie-select -i -f;reboot"

    # to clear out all the previous configuration, use the -k option 
    xdsh <switch> "/usr/cumulus/bin/onie-select -k -f;reboot"

* **[manually]** Log into the Cumulus OS switch and run the following commands: ::

    sudo onie-select -i
    sudo reboot 
