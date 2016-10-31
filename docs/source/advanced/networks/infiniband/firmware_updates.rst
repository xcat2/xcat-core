Firmware Updates
================


Adapter Firmware Update
-----------------------

Download the OFED IB adapter firmware from the Mellanox site `http://www.mellanox.com/page/firmware_table_IBM <http://www.mellanox.com/page/firmware_table_IBM>`_ .

Obtain device id:  ::

	lspci | grep -i mel

Check current installed fw level: ::

	mstflint -d 0002:01:00.0 q | grep FW

Copy or mount firmware to host:

Burn new firmware on each ibaX: ::

	mstflint -d 0002:01:00.0 -i <image location> b

Note: if this is a PureFlex MezzanineP adapater then you must select the correct image for each ibaX device. Note the difference in the firmware image at end of filename: _0.bin (iba0/iba2) & _1.bin (iba1/iba3)

Verify download successful: ::

	mstflint -d 0002:01:00.0 q

Activate the new firmware: ::

	reboot the image

Note: the above 0002:01:00.0 device location was used as an example only. it is not meant to imply that there is only one device location or that your device will have the same device location.

Mellanox Switch Firmware Upgrade
--------------------------------

This section provides manual procedure to help update the firmware for Mellanox Infiniband (IB) Switches. You can down load IB switch firmware like IB6131 (image-PPC_M460EX-SX_3.2.xxx.img) from the Mellanox website `http://www.mellanox.com/page/firmware_table_IBM <http://www.mellanox.com/page/firmware_table_IBM>`_ and place into your xCAT Management Node or server that can communicate to Flex IB6131 switch module. There are two ways to update the MLNX-OS switch package. This process works regardless if updating an internal PureFlex chassis Infiniband switch (IB6131 or for an external Mellanox switch.

Update via Browser
^^^^^^^^^^^^^^^^^^

This method is straight forward if your switches are on the public network or your browser is already capable to tunnel to the private address. If neither is the case then you may prefer to use option two.

After logging into the switch (id=admin, pwd=admin)

Select the "System" tab and then the "MLNX-OS Upgrade" option

Under the "Install New Image", select the "Install via scp"
URL: scp://userid@fwhost/directoryofimage/imagename

Select "Install Image"

The image will then be downloaded to the switch and the installation process will begin.

Once completed, the switch must be rebooted for the new package to be activate

Update via CLI
^^^^^^^^^^^^^^

Login to the IB switch: ::

	ssh admin@<switchipaddr>
	enable  (get into correct CLI mode. You can use en)
	configure terminal (get into correct CLI mode. You can use co t)

List current images and Remove older images to free up space: ::

	show image
	image delete <ibimage>
	(you can paste in ibimage name from show image for image delete)

Get the new IB image using fetch with scp to a server that contains new IB image. An example of IB3161 image would be "image-PPC_M460EX-SX_3.2.0291.img" Admin can use different protocol . This image fetch scp command is about 4 minutes. ::

	image fetch ?
	image fetch scp://userid:password@serveripddr/<full path ibimage location>

Verify that new IB image is loaded, then install the new showIB image on IB switch. The install image process goes through 4 stages Verify image, Uncompress image, Create Filesystems, and Extract Image. This install process takes about 9 minutes. ::

	show image
	image install <newibimage>
	(you can paste in new IB image from "show image" to execute image install)

Toggle boot partition to new IB image, verify image install is loaded , and that next boot setting is pointing to new IB image. ::

	image boot next
	show image

Save the changes made for new IB image: ::

	configuration write

Activate the new IB image (reboot switch): ::
      
	reload


