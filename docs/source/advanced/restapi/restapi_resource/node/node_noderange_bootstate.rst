/nodes/{noderange}/bootstate
============================

GET - Get boot state
--------------------

Refer to the man page: :doc:`nodeset </guides/admin-guides/references/man1/nimnodeset.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...}' pairs.

**Example:** 

Get the next boot state for the node1. :: 


    curl -X GET -k 'https://127.0.0.1/xcatws/nodes/node1/bootstate?userName=root&userPW=cluster&pretty=1'
    {
       "node1":{
          "bootstat":"boot"
       }
    }

PUT - Set the boot state
------------------------

Refer to the man page: :doc:`nodeset </guides/admin-guides/references/man1/nimnodeset.1>`

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: {osimage:xxx}/{state:offline}.

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Set the next boot state for the node1. :: 

    curl -X PUT -k 'https://127.0.0.1/xcatws/nodes/node1/bootstate?userName=root&userPW=cluster&pretty=1' \
        -H Content-Type:application/json --data '{"osimage":"rhels6.4-x86_64-install-compute"}'


