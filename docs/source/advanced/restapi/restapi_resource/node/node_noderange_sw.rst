/nodes/{noderange}/sw
=====================

The software maintenance for the node {noderange}

POST - Perform the software maintenance process for the node {noderange}
------------------------------------------------------------------------

Refer to the man page: :doc:`updatenode </guides/admin-guides/references/man1/updatenode.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...}' pairs.

**Example:** 

Initiate an software maintenance process. :: 


    curl -X POST -k 'https://127.0.0.1/xcatws/nodes/node2/sw?userName=root&userPW=cluster&pretty=1'
    {
       "node2":[
          " Wed Apr  3 09:05:42 CST 2013 Running postscript: ospkgs",
          " Unable to read consumer identity",
          " Postscript: ospkgs exited with code 0",
          " Wed Apr  3 09:05:44 CST 2013 Running postscript: otherpkgs",
          " ./otherpkgs: no extra rpms to install",
          " Postscript: otherpkgs exited with code 0",
          " Running of Software Maintenance has completed."
       ]
    }


