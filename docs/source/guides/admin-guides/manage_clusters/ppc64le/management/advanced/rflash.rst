``rflash`` - Remote Firmware Flashing
=====================================

For OpenPOWER machines, use the ``rflash`` command to update firmware.

Check firmware version of the node and the HPM file:  ::

    rflash cn1 -c /firmware/8335_810.1543.20151021b_update.hpm

Update node firmware to the version of the HPM file

::

    rflash cn1 /firmware/8335_810.1543.20151021b_update.hpm

