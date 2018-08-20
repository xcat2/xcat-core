Discover server and define
--------------------------

After environment is ready, and the server is powered, we can start server discovery process. The first thing to do is discovering the FSP/BMC of the server. It is automatically powered on when the physical server is powered.

Use the :doc:`bmcdiscover </guides/admin-guides/references/man1/bmcdiscover.1>` command to discover the BMCs responding over an IP range and write the output into the xCAT database.  This discovered BMC node is used to control the physical server during hardware discovery and will be deleted after the correct server node object is matched to a pre-defined node.  You **must** use the ``-w`` option to write the output into the xCAT database.

To discover the BMC with an IP address range of 50.0.100.1-100: ::

   bmcdiscover --range 50.0.100.1-100 -z -w

The discovered nodes will be written to xCAT database.  The discovered BMC nodes are in the form **node-model_type-serial**.   To view the discovered nodes: ::

   lsdef /node-.*

**Note:** The ``bmcdiscover`` command will use the username/password from the ``passwd`` table corresponding to ``key=ipmi``.  To overwrite with a different username/password use the ``-u`` and ``-p`` option to ``bmcdiscover``.


Start discovery process
-----------------------

To start discovery process, just need to power on the PBMC node remotely with the following command, and the discovery process will start automatically after the host is powered on::

  rpower node-8247-42l-10112ca on

**[Optional]** If you'd like to monitor the discovery process, you can use::

  makegocons node-8247-42l-10112ca
  rcons node-8247-42l-10112ca
