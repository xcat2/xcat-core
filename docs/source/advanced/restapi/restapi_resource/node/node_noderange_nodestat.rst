/nodes/{noderange}/nodestat
===========================

GET - Get the running status for the node {noderange}.
``````````````````````````````````````````````````````

Refer to the man page: :doc:`nodestat </guides/admin-guides/references/man1/nodestat.1>`

**Returns:**

* An object which includes multiple entries like: <nodename> : { nodestat : <node state> }

**Example:** 

Get the running status for node node1 :: 


    curl -X GET -k 'https://127.0.0.1/xcatws/nodes/node1/nodestat?userName=root&userPW=cluster&pretty=1'
    {
       "node1":{
          "nodestat":"noping"
       }
    }

