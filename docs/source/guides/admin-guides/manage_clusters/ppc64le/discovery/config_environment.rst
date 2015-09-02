Configure xCAT
--------------

configure network table
^^^^^^^^^^^^^^^^^^^^^^^


Normally, there will be at least two entries for the two subnet on MN in "networks" table after xCAT is installed::

    #tabdump networks
    #netname,net,mask,mgtifname,gateway,dhcpserver,tftpserver,nameservers,ntpservers,logservers,dynamicrange,staticrange,staticrangeincrement,nodehostname,ddnsdomain,vlanid,domain,comments,disable
    "10_1_0_0-255_255_0_0","10.1.0.0","255.255.0.0","eth1","<xcatmaster>",,"10.1.1.1",,,,,,,,,,,,
    "10_2_0_0-255_255_0_0","10.2.0.0","255.255.0.0","eth2","<xcatmaster>",,"10.2.1.1",,,,,,,,,,,,

Pls run the following command to add networks in "networks" table if no entry in "networks" table::

    #makenetworks

setup DHCP
^^^^^^^^^^

Set the correct NIC from which DHCP server provide service::

#chdef -t site dhcpinterfaces=eth1,eth2

Add dynamic range in purpose of assigning temporary IP adddress for FSP/BMCs and hosts::

#chdef -t network 10_1_0_0-255_255_0_0 dynamicrange="10.1.100.1-10.1.100.100"
#chdef -t network 10_2_0_0-255_255_0_0 dynamicrange="10.2.100.1-10.2.100.100"

Update DHCP configuration file::

#makedhcp -n
#makedhcp -a

setup DNS
^^^^^^^^^

Set site.forwarders to your site-wide DNS servers that can resolve site or public hostnames. The DNS on the MN will forward any requests it can't answer to these servers::

#chdef -t site forwarders=8.8.8.8

Run makedns to get the hostname/IP pairs copied from /etc/hosts to the DNS on the MN::

#makedns -n

Config passwd table
^^^^^^^^^^^^^^^^^^^

To configure default password for FSP/BMCs and Hosts::

  #tabedit passwd
  #key,username,password,cryptmethod,authdomain,comments,disable
  "system","root","cluster",,,,
  "ipmi","ADMIN","admin",,,,

Check the genesis pkg
^^^^^^^^^^^^^^^^^^^^^

Genesis pkg can be used to creates a network boot root image, it must be installed before do hardware discovery.

``RH``::

  # rpm -qa |grep -i genesis
  xCAT-genesis-scripts-ppc64-2.10-snap201507240527.noarch
  xCAT-genesis-base-ppc64-2.10-snap201505172314.noarch

``ubuntu``::

  # dpkg -l | grep genesis
  ii  xcat-genesis-base-ppc64 2.10-snap201505172314   all          xCAT Genesis netboot image
  ii  xcat-genesis-scripts    2.10-snap201507240105   ppc64el      xCAT genesis

**Note:** If the two pkgs haven't installed yet, pls installed them first and then run the following command to create the network boot root image::

#mknb ppc64
