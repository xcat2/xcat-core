.. BEGIN_Overview

During the installing or netbooting of a node, the drivers in the initrd will be used to drive the devices like network cards and IO devices to perform the installation/netbooting tasks. But sometimes the drivers for the new devices were not included in the default initrd shipped by Red Hat or Suse. A solution is to inject the new drivers into the initrd to drive the new device during the installation/netbooting process.

Generally there are two approaches to inject the new drivers: **Driver Update Disk** and **Drive RPM package**.

A "**Driver Update Disk**" is media which contains the drivers, firmware and related configuration files for certain devices. The driver update disk is always supplied by the vendor of the device. One driver update disk can contain multiple drivers for different OS releases and different hardware architectures. Red Hat and Suse have different driver update disk formats.

The '**Driver RPM Package**' is the rpm package which includes the drivers and firmware for the specific devices. The Driver RPM is the rpm package which is shipped by the Vendor of the device for a new device or a new kernel version.

xCAT supports both. But for '**Driver RPM Package**' is only supported in xCAT 2.8 and later.

No matter which approach chosen, there are two steps to make new drivers work. one is locate the new driver's path, another is inject the new drivers into the initrd.

.. END_Overview


.. BEGIN_locate_driver_for_DUD

There are two approaches for xCAT to find the driver disk (pick one):

#. Specify the location of the driver disk in the osimage object (*This is ONLY supported in xCAT 2.8 and later*)

  The value for the 'driverupdatesrc' attribute is a comma separated driver disk list. The tag 'dud' must be specified before the full path of 'driver update disk' to specify the type of the file: ::

      chdef -t osimage <osimagename> driverupdatesrc=dud:<full path of driver disk>

#. Put the driver update disk in the directory ``<installroot>/driverdisk/<os>/<arch>`` (example: ``/install/driverdisk/sles11.1/x86_64``).

   During the running of the ``genimage``, ``geninitrd``, or ``nodeset`` commands, xCAT will look for driver update disks in the directory ``<installroot>/driverdisk/<os>/<arch>``.

.. END_locate_driver_for_DUD

.. BEGIN_locate_driver_for_RPM

The Driver RPM packages must be specified in the osimage object.

Three attributes of osimage object can be used to specify the Driver RPM location and Driver names. If you want to load new drivers in the initrd, the '**netdrivers**' attribute must be set. And one or both of the '**driverupdatesrc**' and '**osupdatename**' attributes must be set. If both of 'driverupdatesrc' and 'osupdatename' are set, the drivers in the 'driverupdatesrc' have higher priority.

- netdrivers - comma separated driver names that need to be injected into the initrd. The postfix '.ko' can be ignored.

The 'netdrivers' attribute must be set to specify the new driver list. If you want to load all the drivers from the driver rpms, use the keyword allupdate. Another keyword for the netdrivers attribute is updateonly, which means only the drivers located in the original initrd will be added to the newly built initrd from the driver rpms. This is useful to reduce the size of the new built initrd when the distro is updated, since there are many more drivers in the new kernel rpm than in the original initrd. Examples: ::

    chdef -t osimage <osimagename> netdrivers=megaraid_sas.ko,igb.ko
    chdef -t osimage <osimagename> netdrivers=allupdate
    chdef -t osimage <osimagename> netdrivers=updateonly,igb.ko,new.ko

- driverupdatesrc - comma separated driver rpm packages (full path should be specified)

A tag named 'rpm' can be specified before the full path of the rpm to specify the file type. The tag is optional since the default format is 'rpm' if no tag is specified. Example: ::

    chdef -t osimage <osimagename> driverupdatesrc=rpm:<full path of driver disk1>,rpm:<full path of driver disk2>

- osupdatename - comma separated 'osdistroupdate' objects. Each 'osdistroupdate' object specifies a Linux distro update.

When geninitrd is run, ``kernel-*.rpm`` will be searched in the osdistroupdate.dirpath to get all the rpm packages and then those rpms will be searched for drivers. Example: ::

    mkdef -t osdistroupdate update1 dirpath=/install/<os>/<arch>
    chdef -t osimage <osimagename> osupdatename=update1

If 'osupdatename' is specified, the kernel shipped with the 'osupdatename' will be used to load the newly built initrd, then only the drivers matching the new kernel will be kept in the newly built initrd. If trying to use the 'osupdatename', the 'allupdate' or 'updateonly' should be added in the 'netdrivers' attribute, or all the necessary driver names for the new kernel need to be added in the 'netdrivers' attribute. Otherwise the new drivers for the new kernel will be missed in newly built initrd.
.. END_locate_driver_for_RPM


.. BEGIN_inject_into_initrd__for_diskful_for_DUD

- If specifying the driver disk location in the osimage, there are two ways to inject drivers:

  #. Using nodeset command only: ::

      nodeset <noderange> osimage=<osimagename>

  #. Using geninitrd with nodeset command: ::

      geninitrd <osimagename>
      nodeset <noderange> osimage=<osimagename> --noupdateinitrd

.. note:: 'geninitrd' + 'nodeset --noupdateinitrd' is useful when you need to run nodeset frequently for a diskful node. 'geninitrd' only needs be run once to rebuild the initrd and 'nodeset --noupdateinitrd' will not touch the initrd and kernel in /tftpboot/xcat/osimage/<osimage name>/.

- If putting the driver disk in <installroot>/driverdisk/<os>/<arch>:

Running 'nodeset <nodenrage>' in anyway will load the driver disk

.. END_inject_into_initrd__for_diskful_for_DUD

.. BEGIN__inject_into_initrd__for_diskful_for_RPM

There are two ways to inject drivers:

   #. Using nodeset command only: ::

       nodeset <noderange> osimage=<osimagename> [--ignorekernelchk]

   #. Using geninitrd with nodeset command: ::

       geninitrd <osimagename> [--ignorekernelchk]
       nodeset <noderange> osimage=<osimagename> --noupdateinitrd

.. note:: 'geninitrd' + 'nodeset --noupdateinitrd' is useful when you need to run nodeset frequently for diskful nodes. 'geninitrd' only needs to be run once to rebuild the initrd and 'nodeset --noupdateinitrd' will not touch the initrd and kernel in /tftpboot/xcat/osimage/<osimage name>/.

The option '--ignorekernelchk' is used to skip the kernel version checking when injecting drivers from osimage.driverupdatesrc. To use this flag, you should make sure the drivers in the driver rpms are usable for the target kernel.
.. END_inject_into_initrd__for_diskful_for_RPM

.. BEGIN_inject_into_initrd__for_diskless_for_DUD

- If specifying the driver disk location in the osimage

Run the following command: ::

      genimage <osimagename>

- If putting the driver disk in <installroot>/driverdisk/<os>/<arch>:

Running 'genimage' in anyway will load the driver disk
.. END_inject_into_initrd__for_diskless_for_DUD

.. BEGIN_inject_into_initrd__for_diskless_for_RPM

Run the following command:  ::

   genimage <osimagename> [--ignorekernelchk]

The option '--ignorekernelchk' is used to skip the kernel version checking when injecting drivers from osimage.driverupdatesrc. To use this flag, you should make sure the drivers in the driver rpms are usable for the target kernel.
.. END_inject_into_initrd__for_diskless_for_RPM

.. BEGIN_node

- If the drivers from the driver disk or driver rpm are not already part of the installed or booted system, it's necessary to add the rpm packages for the drivers to the .pkglist or .otherpkglist of the osimage object to install them in the system.

- If a driver rpm needs to be loaded, the osimage object must be used for the 'nodeset' and 'genimage' command, instead of the older style profile approach.

- Both a Driver disk and a Driver rpm can be loaded in one 'nodeset' or 'genimage' invocation.

.. END_node
