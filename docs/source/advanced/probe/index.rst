xCAT probe
==========

To help identify some of the common issues with xCAT, a new tool suite is now available **xCAT probe**.

You can use ``xcatprobe -l`` to list all valid subcommands, output will be as below  ::

    # xcatprobe -l
    osdeploy                 Probe operating system provision process. Supports two modes - 'Realtime monitor' and 'Replay history'.
    xcatmn                   After xcat installation, use this command to check if xcat has been installed correctly and is
                             ready for use. Before using this command, install 'tftp', 'nslookup' and 'wget' commands.
    switch-macmap            To retrieve MAC address mapping for the specified switch, or all the switches defined in
                             'switches' table in xCAT db.
    ......

.. toctree::
   :maxdepth: 2

   xcatmn.rst
   detect_dhcpd.rst
   image.rst
   osdeploy.rst
   discovery.rst
   switch-macmap.rst 
   nodecheck.rst
   osimagecheck.rst

