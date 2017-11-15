IPMI Firmware Update
====================

The process for updating firmware on the IBM Power9 Server (Boston) is documented below.


Collect the required files
--------------------------

Collect the following files and put them into a directory on the Management Node. 

   * pUpdate
   * pnor
   * bmc 

Flash Firmware
--------------

Using xCAT ``rflash`` command, specify the directory containing the files with the ``-d`` option. ::

   rflash <noderange> -d /path-to-directory/ 

The ``pUpdate`` utility is leveraged in doing the firmware update against the target node and will do the following: 

   * power off the host
   * flash bmc and reboot
   * flash pnor 
   * power on the host 

Monitor the progress for the nodes by looking at the files under ``/var/log/xcat/rflash/``.

Validatation
------------

Use the ``rinv`` command to validate firmware level: ::

    rinv <noderange> firm | xcoll

