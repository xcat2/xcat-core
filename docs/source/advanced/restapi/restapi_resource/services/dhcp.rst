/services/dhcp
==============

The dhcp service resource.

POST - Create the dhcpd.conf for all the networks which are defined in the xCAT Management Node
-----------------------------------------------------------------------------------------------

Refer to the man page: :doc:`makedhcp </guides/admin-guides/references/man8/makedhcp.8>`

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Create the dhcpd.conf and restart the dhcpd. :: 

    curl -X POST -k 'https://127.0.0.1/xcatws/services/dhcp?userName=root&userPW=cluster&pretty=1'

