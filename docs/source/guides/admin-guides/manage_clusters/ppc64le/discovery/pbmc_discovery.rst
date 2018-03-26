Discover server and define
--------------------------

After environment is ready, and the server is powered, we can start server discovery process. The first thing to do is discovering the FSP/BMC of the server. It is automatically powered on when the physical server is powered.

The following command can be used to discovery FSP/BMC within an IP range and write the discovered node definition into xCAT database::

    lsslp -s PBMC -u --range 50.0.100.1-100 -w

The discovered PBMC node will be like this::

    # lsdef Server-8247-22L-SN10112CA
    Object name: Server-8247-22L-SN10112CA
    bmc=50.0.100.1
    groups=pbmc,all
    hidden=0
    hwtype=pbmc
    mgt=ipmi
    mtm=8247-22L
    nodetype=mp
    postbootscripts=otherpkgs
    postscripts=syslog,remoteshell,syncfiles
    serial=10112CA

**Note**: Note that the PBMC node is just used to control the physical during hardware discovery process, it will be deleted after the correct server node object is found.

Start discovery process
-----------------------

To start discovery process, just need to power on the PBMC node remotely with the following command, and the discovery process will start automatically after the host is powered on::

  rpower Server-8247-22L-SN10112CA on

**[Optional]** If you'd like to monitor the discovery process, you can use::

  chdef Server-8247-22L-SN10112CA cons=ipmi
  makegocons
  rcons Server-8247-22L-SN10112CA
