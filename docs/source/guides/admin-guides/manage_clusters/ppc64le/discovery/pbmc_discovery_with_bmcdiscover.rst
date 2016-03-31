Discover server and define
--------------------------

After environment is ready, and the server is powered, we can start server discovery process. The first thing to do is discovering the FSP/BMC of the server. It is automatically powered on when the physical server is powered.

The following command can be used to discovery BMC within an IP range and write the discovered node definition into xCAT database::

    bmcdiscover -s nmap --range 50.0.100.1-100 -t -z -w

The discovered BMC node will be like this::

    # lsdef node-8247-42l-10112ca
    Object name: node-8247-42l-10112ca
    bmc=50.0.100.1
    cons=ipmi
    groups=all
    hwtype=bmc
    mgt=ipmi
    mtm=8247-42L
    nodetype=mp
    postbootscripts=otherpkgs
    postscripts=syslog,remoteshell,syncfiles
    serial=10112CA

**Note**:
    1. The BMC node is just used to control the physical during hardware discovery process, it will be deleted after the correct server node object is found.
    
    2. bmcdiscover will use username/password pair set in ``passwd`` table with **key** equal **ipmi**. If you'd like to use other username/password pair, you can use ::

        bmcdiscover -s nmap --range 50.0.100.1-100 -t -z -w -u <username> -p <password>

Start discovery process
-----------------------

To start discovery process, just need to power on the PBMC node remotely with the following command, and the discovery process will start automatically after the host is powered on::

  rpower node-8247-42l-10112ca on

**[Optional]** If you'd like to monitor the discovery process, you can use::

  makeconservercf node-8247-42l-10112ca
  rcons node-8247-42l-10112ca
