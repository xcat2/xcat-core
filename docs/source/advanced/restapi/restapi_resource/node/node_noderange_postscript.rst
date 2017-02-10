/nodes/{noderange}/postscript
=============================

The postscript resource for the node {noderange}

POST - Run the postscripts for the node {noderange}
---------------------------------------------------

Refer to the man page: :doc:`updatenode </guides/admin-guides/references/man1/updatenode.1>`

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: {scripts:[p1,p2,p3,...]}.

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...}' pairs.

**Example:** 

Initiate an updatenode process. :: 

    curl -X POST -k 'https://127.0.0.1/xcatws/nodes/node2/postscript?userName=root&userPW=cluster&pretty=1' \
       -H Content-Type:application/json --data '{"scripts":["syslog","remoteshell"]}'
    {
       "node2":[
          " Wed Apr  3 09:01:33 CST 2013 Running postscript: syslog",
          " Shutting down system logger: [  OK  ]",
          " Starting system logger: [  OK  ]",
          " Postscript: syslog exited with code 0",
          " Wed Apr  3 09:01:33 CST 2013 Running postscript: remoteshell",
          " Stopping sshd: [  OK  ]",
          " Starting sshd: [  OK  ]",
          " Postscript: remoteshell exited with code 0",
          " Running of postscripts has completed."
       ]
    }

