.. BEGIN_unattended_OpenBMC_flashing

Unattended flash of OpenBMC firmware will do the following events:

#. Upload both BMC firmware file and Host firmware file
#. Activate both BMC firmware and Host firmware
#. If BMC firmware becomes activate, reboot BMC to apply new BMC firmware, or else, ``rflash`` will exit
#. If BMC itself state is ``NotReady``, ``rflash`` will exit
#. If BMC itself state is ``Ready``, ``rflash`` will reboot the compute node to apply Host firmware

Use the following command to flash the firmware unattended: ::

    rflash <noderange> -d /path/to/directory

If there are errors encountered during the flash process, take a look at the manual steps to continue flashing the BMC.

.. END_unattended_OpenBMC_flashing

.. BEGIN_flashing_OpenBMC_Servers

The sequence of events that must happen to flash OpenBMC firmware is the following:

#. Power off the Host
#. Upload and Activate BMC
#. Reboot the BMC (applies BMC)
#. Upload and Activate Host
#. Power on the Host (applies Host)


Power off Host
--------------

Use the rpower command to power off the host: ::

   rpower <noderange> off

Upload and Activate BMC Firmware
--------------------------------

Use the rflash command to upload and activate the Host firmware: ::

   rflash <noderange> -a /path/to/obmc-phosphor-image-witherspoon.ubi.mtd.tar

If running ``rflash`` in Hierarchy, the firmware files must be accessible on the Service Nodes.

**Note:** If a .tar file is provided, the ``-a`` option does an upload and activate in one step. If an ID is provided, the ``-a`` option just does activate the specified firmware. After firmware is activated, use the ``rflash <noderange> -l`` to view.  The ``rflash`` command shows ``(*)`` as the active firmware and ``(+)`` on the firmware that requires reboot to become effective.

Reboot the BMC
--------------

Use the ``rpower`` command to reboot the BMC: ::

   rpower <noderange> bmcreboot

The BMC will take 2-5 minutes to reboot, check the status using: ``rpower <noderange> bmcstate`` and wait for ``BMCReady`` to be returned.

**Known Issue:**  On reboot, the first call to the BMC after reboot, xCAT will return ``Error: BMC did not respond within 10 seconds, retry the command.``.  Please retry.

Upload and Activate Host Firmware
---------------------------------

Use the rflash command to upload and activate the Host firmware: ::

   rflash <noderange> -a /path/to/witherspoon.pnor.squashfs.tar

If running ``rflash`` in Hierarchy, the firmware files must be accessible on the Service Nodes.

**Note:** The ``-a`` option does an upload and activate in one step, after firmware is activated, use the ``rflash <noderange> -l`` to view.  The ``rflash`` command shows ``(*)`` as the active firmware and ``(+)`` on the firmware that requires reboot to become effective.

Power on Host
-------------

User the ``rpower`` command to power on the Host: ::

   rpower <noderange> on

.. END_flashing_OpenBMC_Servers

.. BEGIN_Validation_OpenBMC_firmware

Validation
----------

Use one of the following commands to validate firmware levels are in sync:

* Use the ``rinv`` command to validate firmware level: ::

    rinv <noderange> firm -V | grep -i ibm | grep "\*" | xcoll

* Use the ``rflash`` command to validate the firmware level: ::

   rflash <noderange> -l | grep "\*" | xcoll


.. END_Validation_OpenBMC_firmware
