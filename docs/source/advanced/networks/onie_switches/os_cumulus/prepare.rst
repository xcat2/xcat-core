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


