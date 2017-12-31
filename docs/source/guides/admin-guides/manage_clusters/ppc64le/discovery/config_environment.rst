
Configure xCAT
--------------

Configure network table
```````````````````````

Normally, there will be at least two entries for the two subnet on MN in ``networks`` table after xCAT is installed::

    #tabdump networks
    #netname,net,mask,mgtifname,gateway,dhcpserver,tftpserver,nameservers,ntpservers,logservers,dynamicrange,staticrange,staticrangeincrement,nodehostname,ddnsdomain,vlanid,domain,mtu,comments,disable
    "10_0_0_0-255_255_0_0","10.0.0.0","255.255.0.0","eth1","<xcatmaster>",,"10.0.1.1",,,,,,,,,,,,,
    "50_0_0_0-255_255_0_0","50.0.0.0","255.255.0.0","eth2","<xcatmaster>",,"50.0.1.1",,,,,,,,,,,,,

Run the following command to add networks in ``networks`` table if there are no entries in it::

    makenetworks

Setup DHCP
``````````

Set the correct NIC from which DHCP server provide service::

    chdef -t site dhcpinterfaces=eth1,eth2

Add dynamic range in purpose of assigning temporary IP address for FSP/BMCs and hosts::

    chdef -t network 10_0_0_0-255_255_0_0 dynamicrange="10.0.100.1-10.0.100.100"
    chdef -t network 50_0_0_0-255_255_0_0 dynamicrange="50.0.100.1-50.0.100.100"

Update DHCP configuration file::

    makedhcp -n
    makedhcp -a

Config passwd table
```````````````````

Set required passwords for xCAT to do hardware management and/or OS provisioning by adding entries to the xCAT ``passwd`` table::

    # tabedit passwd
    # key,username,password,cryptmethod,authdomain,comments,disable

For hardware management with ipmi, add the following line::

    "ipmi","ADMIN","admin",,,,

Verify the genesis packages
```````````````````````````

The **xcat-genesis** packages should have been installed when xCAT was installed, but would cause problems if missing.  **xcat-genesis** packages are required to create the genesis root image to do hardware discovery and the genesis kernel sits in ``/tftpboot/xcat/``.  Verify that the ``genesis-scripts`` and ``genesis-base`` packages are installed:

* **[RHEL/SLES]**: ``rpm -qa | grep -i genesis``

* **[Ubuntu]**: ``dpkg -l | grep -i genesis``

If missing, install them from the ``xcat-deps`` package and run ``mknb ppc64`` to create the genesis network boot root image.
