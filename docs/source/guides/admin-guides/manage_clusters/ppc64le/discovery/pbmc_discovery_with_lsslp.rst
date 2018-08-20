Discover server and define
--------------------------

After environment is ready, and the server is powered, we can start server discovery process. The first thing to do is discovering the FSP/BMC of the server. It is automatically powered on when the physical server is powered.

The following command can be used to discovery FSP/BMC within an IP range and write the discovered node definition into a stanza file::

  lsslp -s PBMC -u --range 50.0.100.1-100 -z > ./pbmc.stanza

You need to modify the node definition in stanza file before using them, the stanza file will be like this::

  # cat pbmc.stanza
  cn1:
      objtype=node
      bmc=50.0.100.1
      nodetype=mp
      mtm=8247-42L
      serial=10112CA
      groups=pbmc,all
      mgt=ipmi
      hidden=0

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

After the physical server is defined into xCATdb, the next thing is update the node definition with the scheduled node info like this::

  # chdef cn1 ip=10.0.101.1
  1 object definitions have been created or modified.

Then, add node info into /etc/hosts and DNS::

  makehosts cn1
  makedns -n


