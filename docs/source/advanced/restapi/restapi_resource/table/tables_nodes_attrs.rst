/tables/{tablelist}/nodes/nodes/{noderange}/{attr1,attr2,attr3,...}
===================================================================

For a large number of nodes, this API call can be faster than using the corresponding nodes resource.  The disadvantage is that you need to know the table names the attributes are stored in.

GET - Get table attibutes for a noderange
-----------------------------------------

**Returns:**

* An object containing each table.  Within each table object is an array of node objects containing the attributes.

**Example:** 

Get OS and ARCH attributes from nodetype table for node1 and node2. :: 

    curl -X GET -k 'https://127.0.0.1/xcatws/tables/nodetype/nodes/node1,node2/os,arch?userName=root&userPW=cluster&pretty=1'
    {
       "nodetype":[
          {
             "arch":"x86_64",
             "name":"node1",
             "os":"rhels6.4"
          },
          {
             "arch":"x86_64",
             "name":"node2",
             "os":"rhels6.3"
          }
       ]
    }

