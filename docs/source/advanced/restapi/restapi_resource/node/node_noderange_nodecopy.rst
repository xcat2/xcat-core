/nodes/{noderange}/nodecopy
===========================

The nodecopy resource for the node {noderange}

POST - Copy files to the node {noderange}
-----------------------------------------

Refer to the man page: :doc:`xdcp </guides/admin-guides/references/man1/xdcp.1>`

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: {src:[file1,file2],target:dir}.

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Copy files /tmp/f1 and /tmp/f2 from xCAT MN to the node2:/tmp. :: 

    curl -X POST -k 'https://127.0.0.1/xcatws/nodes/node2/nodecopy?userName=root&userPW=cluster&pretty=1' \
       -H Content-Type:application/json --data '{"src":["/tmp/f1","/tmp/f2"],"target":"/tmp"}'
    no output for succeeded copy.

