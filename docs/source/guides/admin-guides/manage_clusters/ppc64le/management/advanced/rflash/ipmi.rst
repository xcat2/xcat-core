IPMI Firmware Update
====================

The ``rflash`` command is provided to assist the system administrator in updating firmware.

To check the current firmware version on the node's BMC and the HPM file: ::

    rflash <noderange> -c /firmware/8335_810.1543.20151021b_update.hpm

To update the firmware on the node's BMC to version in the HPM file: ::

    rflash <noderange> /firmware/8335_810.1543.20151021b_update.hpm

