Switch Management
=================

Switch Port and VLAN Configuration
----------------------------------

xCAT expects the configuration for the front-panel ports to be located at ``/etc/network/interfaces.d/xCAT.intf`` on the switch.  The ``configinterface`` postscript can download an interface configuration file from the management node.  Place the configuration file in the directory ``/install/custom/sw_os/cumulus/interface/`` on the management node.  It will first look for a file named the same as the switch's hostname, followed by the name of each group, followed by the word 'default'.  If the postscript cannot find a configuration file on the management node, it will set all the ports on the switch to be part of VLAN 1.  See the Cumulus Networks documentation for more information regarding advanced networking configuration. ::

    updatenode <switch> -P configinterface


Re-install OS
-------------

There may be occasions where a re-install of the OS is required.   Assuming the files are available on the xCAT management node, the following commands will invoke the install process: 

* **[use xCAT]** ``xdsh`` can be used to invoke the reinstall of the OS: ::

    # to clear out all the previous configuration, use the -k option (optional)
    xdsh <switch> "/usr/cumulus/bin/onie-select -k
    
    # to invoke the reinstall of the OS
    xdsh <switch> "/usr/cumulus/bin/onie-select -i -f;reboot"

* **[manually]** Log into the Cumulus OS switch and run the following commands: ::

    sudo onie-select -i
    sudo reboot 
