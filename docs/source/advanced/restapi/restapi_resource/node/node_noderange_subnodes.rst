/nodes/{noderange}/subnodes
===========================

GET - Return the Children nodes for the node {noderange}.
`````````````````````````````````````````````````````````

Refer to the man page: :doc:`rscan </guides/admin-guides/references/man1/rscan.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...}' pairs.

**Example:** 

Get all the children nodes for node 'node1'. :: 


    curl -X GET -k 'https://127.0.0.1/xcatws/nodes/node1/subnodes?userName=root&userPW=cluster&pretty=1'
    {
       "cmm01node09":{
          "mpa":"ngpcmm01",
          "parent":"ngpcmm01",
          "serial":"1035CDB",
          "mtm":"789523X",
          "cons":"fsp",
          "hwtype":"blade",
          "objtype":"node",
          "groups":"blade,all,p260",
          "mgt":"fsp",
          "nodetype":"ppc,osi",
          "slotid":"9",
          "hcp":"10.1.9.9",
          "id":"1"
       },
       ...
    }

