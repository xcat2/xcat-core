OpenBMC Firmware Update
=======================

The process of updating firmware on the OpenBMC managed servers is documented below.  

The sequence of events that must happen is the following: 

  * Power off the Host 
  * Update and Activate PNOR
  * Update and Activate BMC 
  * Reboot the BMC (applies BMC)
  * Power on the Host (applies PNOR) 

**Note:** xCAT is working on streamlining this process to reduce the flexibility of the above steps at the convenience of the Administrator to handle the necessary reboots.  See `Issue #4245 <https://github.com/xcat2/xcat-core/issues/4245>`_


Power off Host 
--------------

Use the rpower command to power off the host: ::

   rpower <noderange> off 

Update and Activate PNOR Firmware
---------------------------------

Use the rflash command to upload and activate the PNOR firmware: ::

   rflash <noderange> -a /path/to/witherspoon.pnor.squashfs.tar

**Note:** The ``-a`` option does an upload and activate in one step, after firmware is activated, use the ``rflash <noderange> -l`` to view.  The ``rflash`` command shows ``(*)`` as the active firmware and ``(+)`` on the firmware that requires reboot to become effective. 

Update and Activate BMC Firmware
--------------------------------

Use the rflash command to upload and activate the PNOR firmware: ::

   rflash <noderange> -a /path/to/obmc-phosphor-image-witherspoon.ubi.mtd.tar

**Note:** The ``-a`` option does an upload and activate in one step, after firmware is activated, use the ``rflash <noderange> -l`` to view.  The ``rflash`` command shows ``(*)`` as the active firmware and ``(+)`` on the firmware that requires reboot to become effective. 

Reboot the BMC
--------------

Use the ``rpower`` command to reboot the BMC: ::
 
   rpower <noderange> bmcreboot`

The BMC will take 2-5 minutes to reboot, check the status using: ``rpower <noderange> bmcstate`` and wait for ``BMCReady`` to be returned. 

**Known Issue:**  On reboot, the first call to the BMC after reboot, xCAT will return ``Error: BMC did not respond within 10 seconds, retry the command.``.  Please retry. 


Power on Host
-------------

User the ``rpower`` command to power on the Host: ::

   rpower <noderange> on 


Validation
----------

Use one of the following commands to validate firmware levels are in sync: 

* Use the ``rinv`` command to validate firmware level: ::

    rinv <noderange> firm -V | grep -i ibm | grep "\*" | xcoll 

* Use the ``rflash`` command to validate the firmware level: ::

   rflash <noderange> -l | grep "\*" | xcoll 

