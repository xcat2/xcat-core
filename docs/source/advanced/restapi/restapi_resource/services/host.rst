/services/host
==============

The hostname resource.

POST - Create the IP/hostname records for all the nodes to /etc/hosts
---------------------------------------------------------------------

Refer to the man page: :doc:`makehosts </guides/admin-guides/references/man8/makehosts.8>`

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Create the IP/hostname records for all the nodes to /etc/hosts. :: 

    curl -X POST -k 'https://127.0.0.1/xcatws/services/host?userName=root&userPW=cluster&pretty=1'


