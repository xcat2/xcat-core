/nodes/{noderange}/dns
----------------------

POST - Create the dns record for the node {noderange}.
``````````````````````````````````````````````````````

The prerequisite of the POST operation is the mapping of ip and noderange for the node has been added in the /etc/hosts.  Refer to the man page: :doc:`makedns </guides/admin-guides/references/man8/makedns.8>`

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Create the dns record for node 'node1'. :: 

    curl -X POST -k 'https://127.0.0.1/xcatws/nodes/node1/dns?userName=root&userPW=cluster&pretty=1'

DELETE - Remove the dns record for the node {noderange}.
````````````````````````````````````````````````````````

Refer to the man page: :doc:`makedns </guides/admin-guides/references/man8/makedns.8>`

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Delete the dns record for node node1 :: 

    curl -X DELETE -k 'https://127.0.0.1/xcatws/nodes/node1/dns?userName=root&userPW=cluster&pretty=1'

