/nodes/{noderange}/attrs/{attr1,attr2,attr3,...}
------------------------------------------------

GET - Get the specific attributes for the node {noderange}.
```````````````````````````````````````````````````````````

The keyword ALLRESOURCES can be used as {noderange} which means to get node attributes for all the nodes.  Refer to the man page: :doc:`lsdef </guides/admin-guides/references/man1/lsdef.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value, ...}' pairs.

**Example:** 

Get the attributes {groups,mgt,netboot} for node node1 :: 


    curl -X GET -k 'https://127.0.0.1/xcatws/nodes/node1/attrs/groups,mgt,netboot?userName=root&userPW=cluster&pretty=1'
    {
       "node1":{
          "netboot":"xnba",
          "mgt":"ipmi",
          "groups":"all"
       }
    }

