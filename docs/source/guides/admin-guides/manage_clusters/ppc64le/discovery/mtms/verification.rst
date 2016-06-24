Verification
============

Before starting hardware discovery, ensure the following is configured to make the discovery process as smooth as possible. 

Password Table
--------------

In order to communicate with IPMI-based hardware (with BMCs), verify that the xCAT ``passwd`` table contains an entry for ``ipmi`` which defines the default username and password to communicate with the IPMI-based servers. ::

    tabdump passwd | grep ipmi

If not configured, use the following command to set ``usernam=ADMIN`` and ``password=admin``.  ::

    chtab key=ipmi passwd.username=ADMIN passwd.password=admin


Genesis Package 
---------------

The **xCAT-genesis** packages provides the utility to create the genesis network boot rootimage used by xCAT when doing hardware discovery.  It should be installed during the xCAT install and would cause problems if missing.  

Verify that the ``genesis-scripts`` and ``genesis-base`` packages are installed:

    * **[RHEL/SLES]**: ::

        rpm -qa | grep -i genesis

    * **[Ubuntu]**: ::

        dpkg -l | grep -i genesis


If missing:

    #. Install them from the ``xcat-dep`` repository using the Operating Specific package manager (``yum, zypper, apt-get, etc``)

       * **[RHEL]**: ::

           yum install xCAT-genesis

       * **[SLES]**: ::

           zypper install xCAT-genesis

       * **[Ubuntu]**: ::

           apt-get install xCAT-genesis

    #. Create the network boot rootimage with the following command: ``mknb ppc64``.  

       The genesis kernel should be copied to ``/tftpboot/xcat``.

