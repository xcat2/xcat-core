/nodes/{noderange}/updating
===========================

POST - Update the node with file syncing, software maintenance and rerun postscripts
------------------------------------------------------------------------------------

Refer to the man page: :doc:`updatenode </guides/admin-guides/references/man1/updatenode.1>`

**Returns:**

* An array of messages for performing the node updating.

**Example:** 

Initiate an updatenode process. :: 


    curl -X POST -k 'https://127.0.0.1/xcatws/nodes/node2/updating?userName=root&userPW=cluster&pretty=1'
    [
       "There were no syncfiles defined to process. File synchronization has completed.",
       "Performing software maintenance operations. This could take a while, if there are packages to install.
    ",
       "node2: Wed Mar 20 15:01:43 CST 2013 Running postscript: ospkgs",
       "node2: Running of postscripts has completed."
    ]
