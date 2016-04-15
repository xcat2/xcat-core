Discovery
=========

When the IPMI-based servers are connected to power, the BMCs will boot up and attempt to obtain an IP address from an open range dhcp server on your network.  In the case for xCAT managed networks, xCAT should be configured serve an open range dhcp IP addresses with the ``dynamicrange`` attribute in the networks table.

When the BMCs have an IP address and is pingable from the xCAT management node, administrators can discover the BMCs using the xCAT's :doc:`bmcdiscover </guides/admin-guides/references/man1/bmcdiscover.1>` command and obtain basic information to start the hardware discovery process.  

xCAT Hardware discover uses the xCAT genesis kernel (diskless) to discover additional attributes of the compute node and automatically populate the node definitions in xCAT.

.. toctree::
   :maxdepth: 2

   discovery_using_defined.rst
   discovery_using_dhcp.rst
