MTMS-based Discovery
====================

MTMS is short for Machine Type/Model and Serial which is unique for a physical server. The idea of MTMS based hardware discovery is that the admin know the physical location information of the server with specified MTMS. Then the admin can assign nodename and host ip address for the physical server.

.. include:: schedule_environment.rst
.. include:: config_environment.rst 

Discover server and define
--------------------------

After environment is ready, and the server is powered, we can start server discovery process. The first thing to do is discovering the FSP/BMC of the server. It is automatically powered on when the physical server is powered.

The following command can be used to discover BMC(s) within an IP range and write the discovered node definition(s) into a stanza file::

  bmcdiscover -s nmap --range 50.0.100.1-100 -z > ./bmc.stanza

**Note**: bmcdiscover will use username/password pair set in ``passwd`` table with **key** equal **ipmi**. If you'd like to use other username/password, you can use ::

        bmcdiscover -s nmap --range 50.0.100.1-100 -z -u <username> -p <password> > ./bmc.stanza

You need to modify the node definition(s) in stanza file before using them, the stanza file will be like this::
 
  # cat pbmc.stanza
  cn1:
      objtype=node
      bmc=50.0.100.1
      mtm=8247-42L
      serial=10112CA
      groups=pbmc,all
      mgt=ipmi

Then, define it into xCATdb::
  
  # cat pbmc.stanza | mkdef -z
  1 object definitions have been created or modified.

The server definition will be like this::

  # lsdef cn1
  Object name: cn1
      bmc=50.0.100.1
      groups=pbmc,all
      hidden=0
      mgt=ipmi
      mtm=8247-42L
      nodetype=mp
      postbootscripts=otherpkgs
      postscripts=syslog,remoteshell,syncfiles
      serial=10112CA

After the physical server is defined into xCATdb, the next thing is update the node definition with the example node attributes::

  # chdef cn1 ip=10.0.101.1
  1 object definitions have been created or modified.

Then, add node info into /etc/hosts and DNS::

  makehosts cn1
  makedns -n



Start discovery process
-----------------------

To start discovery process, just need to power on the host remotely with the following command, and the discovery process will start automatically after the host is powered on::

  rpower cn1 on

**[Optional]** If you'd like to monitor the discovery process, you can use::

  chdef cn1 cons=ipmi
  makeconsercf
  rcons cn1

.. include:: standard_cn_definition.rst
