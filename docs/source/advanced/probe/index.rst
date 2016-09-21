xCAT probe
==========

xCAT offers a new tool suite, which called **xCAT probe**, to help customer to probe all the possible issues in xCAT.

You can use ``xcatprobe -l`` to list all valid subcommand, output will be as below  ::

    # xcatprobe -l
    osdeploy                 Probe for OS provision process, realtime monitor of OS provision process.
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


