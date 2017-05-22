/nodes/{noderange}/beacon
=========================

PUT - Change the beacon status for the node {noderange}
------------------------------------------------------- 

Refer to the man page: :doc:`rbeacon </guides/admin-guides/references/man1/rbeacon.1>`

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: {action:on/off/blink}.

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Turn on the beacon. :: 


    curl -X PUT -k 'https://127.0.0.1/xcatws/nodes/node1/beacon?userName=root&userPW=cluster&pretty=1' \
       -H Content-Type:application/json --data '{"action":"on"}'
    [
       {
          "name":"node1",
          "beacon":"on"
       }
    ]

