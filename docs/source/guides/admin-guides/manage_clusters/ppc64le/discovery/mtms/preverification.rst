Before Starting 
===============

Before starting hardware discovery, ensure the following is configured to make the discovery process as smooth as possible. 

Password Table
--------------

In order to communicate with IPMI-based (bmc) hardware, verify that the xCAT ``passwd`` table contains an entry for ``ipmi`` defininig the username and password for IPMI-based servers. ::

    tabdump passwd | grep ipmi


Genesis Package 
---------------

The **xcat-genesis** packages provides the utility to create the genesis network boot rootimage used by xCAT when doing hardware discivery.  IT should have been installed during the xCAT installation and would cause problems if missing.  

Verify that the ``genesis-scripts`` and ``genesis-base`` packages are installed:

    * **[RHEL/SLES]**: ::

        rpm -qa | grep -i genesis

    * **[Ubuntu]**: ::

        dpkg -l | grep -i genesis


If the packages are missing:

    #. Install them using the OS specific package manager from the ``xcat-deps`` repository
    #. Create the network boot rootimage with the following command: ``mknb ppc64``.  
       The resulting genesis kernel should appear in the ``/tftpboot/xcat`` directory.

