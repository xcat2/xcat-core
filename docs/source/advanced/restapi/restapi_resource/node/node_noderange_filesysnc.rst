/nodes/{noderange}/filesyncing
==============================

POST - Sync files for the node {noderange}
------------------------------------------

Refer to the man page: :doc:`updatenode </guides/admin-guides/references/man1/updatenode.1>`

**Returns:**

* An array of messages for performing the file syncing for the node.

**Example:** 

Initiate an file syncing process. :: 


    curl -X POST -k 'https://127.0.0.1/xcatws/nodes/node2/filesyncing?userName=root&userPW=cluster&pretty=1'
    [
       "There were no syncfiles defined to process. File synchronization has completed."
    ]

