/tables/{tablelist}/nodes/{noderange}
=====================================

For a large number of nodes, this API call can be faster than using the corresponding nodes resource.  The disadvantage is that you need to know the table names the attributes are stored in.

GET - Get attibutes of tables for a noderange
---------------------------------------------

**Returns:**

* An object containing each table.  Within each table object is an array of node objects containing the attributes.

**Examples:**

#. Get all the columns from table nodetype for node1 and node2. :: 

    curl -X GET -k 'https://127.0.0.1/xcatws/tables/nodetype/nodes/node1,node2?userName=root&userPW=cluster&pretty=1'
    {
       "nodetype":[
          {
             "provmethod":"rhels6.4-x86_64-install-compute",
             "profile":"compute",
             "arch":"x86_64",
             "name":"node1",
             "os":"rhels6.4"
          },
          {
             "provmethod":"rhels6.3-x86_64-install-compute",
             "profile":"compute",
             "arch":"x86_64",
             "name":"node2",
             "os":"rhels6.3"
          }
       ]
    }

#. Get all the columns from tables nodetype and noderes for node1 and node2. :: 

    curl -X GET -k 'https://127.0.0.1/xcatws/tables/nodetype,noderes/nodes/node1,node2?userName=root&userPW=cluster&pretty=1'
    {
       "noderes":[
          {
             "installnic":"mac",
             "netboot":"xnba",
             "name":"node1",
             "nfsserver":"192.168.1.15"
          },
          {
             "installnic":"mac",
             "netboot":"pxe",
             "name":"node2",
             "proxydhcp":"no"
          }
       ],
       "nodetype":[
          {
             "provmethod":"rhels6.4-x86_64-install-compute",
             "profile":"compute",
             "arch":"x86_64",
             "name":"node1",
             "os":"rhels6.4"
          },
          {
             "provmethod":"rhels6.3-x86_64-install-compute",
             "profile":"compute",
             "arch":"x86_64",
             "name":"node2",
             "os":"rhels6.3"
          }
       ]
    }


PUT - Change the node table attibutes for {noderange}
-----------------------------------------------------

**Parameters:**

* A hash of table names and attribute objects.  DataBody: {table1:{attr1:v1,att2:v2,...}}.

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Change the nodetype.arch and noderes.netboot attributes for nodes node1,node2. :: 

    curl -X PUT -k 'https://127.0.0.1/xcatws/tables/nodetype,noderes/nodes/node1,node2?userName=root&userPW=cluster&pretty=1' -H Content-Type:application/json --data '{"nodetype":{"arch":"x86_64"},"noderes":{"netboot":"xnba"}}'

