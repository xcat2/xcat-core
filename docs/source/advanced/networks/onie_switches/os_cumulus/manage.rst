Switch Management
=================

Switch Port and VLAN Configuration
----------------------------------

xCAT places the front-panel port configuration in ``/etc/network/interfaces.d/xCAT.intf``.

The ``configinterface`` postscript can be used to pull switch interface configuration from the xCAT Management Node (MN) to the switch.  Place the switch specific confguration files in the following directory on the MN: ``/install/custom/sw_os/cumulus/interface/``.  

xCAT will look for files in the above directory in the following order:

   1. file name that matches the switch hostname 
   2. file name that matches the switch group name 
   3. file name that has the word 'default'

   Note: If the postscript cannot find a configuration file on the MN, it will set all ports on the switch to be part of VLAN 1.

Execute the script using the following command: ::

    updatenode <switch> -P configinterface


Re-install OS
-------------

There may be occasions where a re-install of the Cumulus Linux OS is required.   The following commands can be used to invoke the install: 

**Note:** Assumption that the Cumulus Linux files are on the xCAT MN in the correct place.

* **Using xCAT**, ``xdsh`` can invoke the reinstall of the OS: ::

    # to clear out all the previous configuration, use the -k option (optional)
    xdsh <switch> "/usr/cumulus/bin/onie-select -k
    
    # to invoke the reinstall of the OS
    xdsh <switch> "/usr/cumulus/bin/onie-select -i -f;reboot"

* **Manually**, log into the switch and run the following commands: ::

    sudo onie-select -i
    sudo reboot 
