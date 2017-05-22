/nodes/{noderange}/vmmigrate
============================

The virtualization resource for migration. The node specified should be a virtual machine. 

POST - Migrate a node to targe node
-----------------------------------

Refer to the man page: :doc:`rmigrate </guides/admin-guides/references/man1/rmigrate.1>`

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: {"target":"targethost"}.

**Example:** 

Migrate node1 to target host host2. :: 

    curl -X POST -k 'https://127.0.0.1/xcatws/nodes/node1/vmmigrate?userName=root&userPW=cluster&pretty=1' \
       -H Content-Type:application/json --data '{"target":"host2"}'
