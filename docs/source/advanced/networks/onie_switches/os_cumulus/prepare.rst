Preparation
===========

Prepare the Cumulus Linux files on the xCAT Management Node.

#. Obtain a valid Cumulus Linux License and download the Cumulus Linux OS installer.

#. Copy the above files into a location under the xCAT ``/install`` directory. ::

    # Create a directory to hold the cumulus linux files
    mkdir -p /install/custom/sw_os/cumulus/

    # copy the license file
    cp licensefile.txt /install/custom/sw_os/cumulus/

    # copy the installer
    cp cumulus-linux-3.1.0-bcm-armel.bin /install/custom/sw_os/cumulus/


Cumulus osimage
---------------

xCAT can able to create a cumulus osimage defintion via ``copycds`` command.  ``copycds`` will copy cumulus installer to a destination directory, and create several relevant osimage definitions. **cumulus<release>-<arch>** is the default osimage name. ::

    #run copycds command
    # copycds cumulus-linux-3.5.2-bcm-armel.bin

The ``pkgdir`` attribute will contain full path of cumulus installer as **/install/cumulus<release>/<arch>/<installer>**. ::

    # lsdef -t osimage cumulus3.5.2-armel
    Object name: cumulus3.5.2-armel
        description=Cumulus Linux
        imagetype=linux
        osarch=armel
        osname=cumulus
        osvers=cumulus3.5.2
        pkgdir=/install/cumulus3.5.2/armel/cumulus-linux-3.5.2-bcm-armel.bin
        provmethod=install





