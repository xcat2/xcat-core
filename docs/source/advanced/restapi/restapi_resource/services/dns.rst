/services/dns
=============

The dns service resource.

POST - Initialize the dns service
---------------------------------

Refer to the man page: :doc:`makedns </guides/admin-guides/references/man8/makedns.8>`

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Initialize the dns service. :: 

    curl -X POST -k 'https://127.0.0.1/xcatws/services/dns?userName=root&userPW=cluster&pretty=1'

