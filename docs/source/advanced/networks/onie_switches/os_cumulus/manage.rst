Switch Management
=================

VLAN Configuration
------------------


Re-install OS
-------------

There may be occasions where a re-install of the OS is required.   Assuming the files are available on the xCAT management node, the following commands will invoke the install process: 

**Manually:** Log into the Cumulus OS switch and run the following commands: ::

    sudo onie-select -i
    sudo reboot 

**Using xCAT:** ``xdsh`` can be used to invoke the reinstall of the OS: ::

    xdsh <switch> "/usr/cumulus/bin/onie-select -i -f;reboot"

