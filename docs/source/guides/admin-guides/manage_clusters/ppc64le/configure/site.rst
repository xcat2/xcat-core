Set attributes in the ``site`` table
====================================

#. Verify the following attributes have been correctly set in the xCAT ``site`` table. 

    * domain
    * forwarders
    * master [#]_
    * nameservers

   For more information on the keywords, see the DHCP ATTRIBUTES in the :doc:`site </guides/admin-guides/references/man5/site.5>` table.

   If the fields are not set or need to be changed, use the xCAT ``chdef`` command: ::

      chdef -t site domain="domain_string"
      chdef -t site fowarders="forwarders"
      chdef -t site master="xcat_master_ip"
      chdef -t site nameservers="nameserver1,nameserver2,etc"

.. [#] The value of the ``master`` attribute in the site table should be set as the IP address of the management node responsible for the compute node.

Initialize DNS services
-----------------------

#. Initialize the DNS [#]_ services on the xCAT Management Node: ::

      makedns -n 

   Verify DNS is working by running ``nslookup`` against your Management Node: ::

      nslookup <management_node_hostname>

   For more information on DNS, refer to :ref:`dns_label`
 

.. [#] Setting up name resolution and the ability to have hostname resolved to IP addresses is **required** for xCAT.
