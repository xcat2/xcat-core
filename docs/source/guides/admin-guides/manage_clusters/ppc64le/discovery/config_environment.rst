Configure xCAT
--------------

Configure network table
```````````````````````


Normally, there will be at least two entries for the two subnet on MN in ``networks`` table after xCAT is installed::

    #tabdump networks
    #netname,net,mask,mgtifname,gateway,dhcpserver,tftpserver,nameservers,ntpservers,logservers,dynamicrange,staticrange,staticrangeincrement,nodehostname,ddnsdomain,vlanid,domain,comments,disable
    "10_0_0_0-255_255_0_0","10.0.0.0","255.255.0.0","eth1","<xcatmaster>",,"10.0.1.1",,,,,,,,,,,,
    "50_0_0_0-255_255_0_0","50.0.0.0","255.255.0.0","eth2","<xcatmaster>",,"50.0.1.1",,,,,,,,,,,,

Pls run the following command to add networks in ``networks`` table if no entry in ``networks`` table::

    makenetworks

.. _Setup-dhcp:

Setup DHCP
``````````

Set the correct NIC from which DHCP server provide service::

    chdef -t site dhcpinterfaces=eth1,eth2

Add dynamic range in purpose of assigning temporary IP adddress for FSP/BMCs and hosts::

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

Verify the genesis pkg
``````````````````````

Genesis pkg is used to **create the root image for network boot** and it **MUST** be installed before doing hardware discovery. 

* **[RH]**::

    # rpm -qa |grep -i genesis
    xCAT-genesis-scripts-ppc64-2.10-snap201507240527.noarch
    xCAT-genesis-base-ppc64-2.10-snap201505172314.noarch

* **[ubuntu]**::

    # dpkg -l | grep genesis
    ii  xcat-genesis-base-ppc64 2.10-snap201505172314   all          xCAT Genesis netboot image
    ii  xcat-genesis-scripts    2.10-snap201507240105   ppc64el      xCAT genesis

**Note:** If the two pkgs are not installed, pls installed them first and then run ``mknb ppc64`` to create the network boot root image.
