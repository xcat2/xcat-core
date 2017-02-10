/nodes/{noderange}/nodeshell
============================

The nodeshell resource for the node {noderange}

POST - Run the command in the shell of the node {noderange}
-----------------------------------------------------------

Refer to the man page: :doc:`xdsh </guides/admin-guides/references/man1/xdsh.1>`

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: set environment {ENV:{en1:v1,en2:v2}}, raw command {raw:[op1,op2]}, direct command {command:[cmd1,cmd2]}.

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...}' pairs.

**Example:** 

Run the 'date' command on the node2. :: 

    curl -X POST -k 'https://127.0.0.1/xcatws/nodes/node2/nodeshell?userName=root&userPW=cluster&pretty=1' \
       -H Content-Type:application/json --data '{"command":["date","ls"]}'
    {
       "node2":[
          " Wed Apr  3 08:30:26 CST 2013",
          " testline1",
          " testline2"
       ]
    }

