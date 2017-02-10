/nodes
======

This resource can be used to display all the nodes which have been defined in the xCAT database.

GET - Get all the nodes in xCAT.
````````````````````````````````

The attributes details for the node will not be displayed.

Refer to the man page: :doc:`lsdef </guides/admin-guides/references/man1/lsdef.1>`

**Returns:**

* Json format: An array of node names.

**Example:** 

Get all the node names from xCAT database. :: 

    curl -X GET -k 'https://127.0.0.1/xcatws/nodes?userName=root&userPW=cluster&pretty=1'
    [
       "node1",
       "node2",
       "node3",
    ]
