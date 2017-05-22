/nodes/{noderange}
==================

GET - Get all the attibutes for the node {noderange}
----------------------------------------------------

The keyword ALLRESOURCES can be used as {noderange} which means to get node attributes for all the nodes.

Refer to the man page: :doc:`lsdef </guides/admin-guides/references/man1/lsdef.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...}' pairs.

**Example:** 

Get all the attibutes for node 'node1'. :: 


    curl -X GET -k 'https://127.0.0.1/xcatws/nodes/node1?userName=root&userPW=cluster&pretty=1'
    {
       "node1":{
          "profile":"compute",
          "netboot":"xnba",
          "arch":"x86_64",
          "mgt":"ipmi",
          "groups":"all",
          ...
       }
    }

PUT - Change the attibutes for the node {noderange}
---------------------------------------------------

Refer to the man page: :doc:`chdef </guides/admin-guides/references/man1/chdef.1>`

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: {attr1:v1,att2:v2,...}.

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Change the attributes mgt=dfm and netboot=yaboot. :: 


    curl -X PUT -k 'https://127.0.0.1/xcatws/nodes/node1?userName=root&userPW=cluster&pretty=1' \
       -H Content-Type:application/json --data '{"mgt":"dfm","netboot":"yaboot"}'


POST - Create the node {noderange}
---------------------------------- 

Refer to the man page: :doc:`mkdef </guides/admin-guides/references/man1/mkdef.1>`

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: {attr1:v1,att2:v2,...}.

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Create a node with attributes groups=all, mgt=dfm and netboot=yaboot :: 


    curl -X POST -k 'https://127.0.0.1/xcatws/nodes/node1?userName=root&userPW=cluster&pretty=1' \
       -H Content-Type:application/json --data '{"groups":"all","mgt":"dfm","netboot":"yaboot"}'

DELETE - Remove the node {noderange}
------------------------------------

Refer to the man page: :doc:`rmdef </guides/admin-guides/references/man1/rmdef.1>`

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Delete the node node1 :: 

    curl -X DELETE -k 'https://127.0.0.1/xcatws/nodes/node1?userName=root&userPW=cluster&pretty=1'

