/nodes/{noderange}/dhcp
=======================

POST - Create the dhcp record for the node {noderange}.
```````````````````````````````````````````````````````

Refer to the man page: :doc:`makedhcp </guides/admin-guides/references/man8/makedhcp.8>`

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Create the dhcp record for node 'node1'. :: 

    curl -X POST -k 'https://127.0.0.1/xcatws/nodes/node1/dhcp?userName=root&userPW=cluster&pretty=1'

DELETE - Remove the dhcp record for the node {noderange}.
`````````````````````````````````````````````````````````

Refer to the man page: :doc:`makedhcp </guides/admin-guides/references/man8/makedhcp.8>`

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Delete the dhcp record for node node1 :: 

    curl -X DELETE -k 'https://127.0.0.1/xcatws/nodes/node1/dhcp?userName=root&userPW=cluster&pretty=1'

