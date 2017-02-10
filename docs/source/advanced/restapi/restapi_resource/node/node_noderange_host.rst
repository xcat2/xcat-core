/nodes/{noderange}/host
-----------------------

POST - Create the mapping of ip and hostname record for the node {noderange}.
`````````````````````````````````````````````````````````````````````````````

Refer to the man page: :doc:`makehosts </guides/admin-guides/references/man8/makehosts.8>`

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Create the mapping of ip and hostname record for node 'node1'. :: 

    curl -X POST -k 'https://127.0.0.1/xcatws/nodes/node1/host?userName=root&userPW=cluster&pretty=1'

