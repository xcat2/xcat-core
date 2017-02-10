/nodes/{noderange}/nextboot
===========================

GET - Get the next bootorder.
`````````````````````````````

Refer to the man page: :doc:`rsetboot </guides/admin-guides/references/man1/rsetboot.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...}' pairs.

**Example:** 

Get the bootorder for the next boot. (It's only valid after setting.) :: 


    curl -X GET -k 'https://127.0.0.1/xcatws/nodes/node1/nextboot?userName=root&userPW=cluster&pretty=1'
    {
       "node1":{
          "nextboot":"Network"
       }
    }

PUT - Change the next boot order. 
``````````````````````````````````

Refer to the man page: :doc:`rsetboot </guides/admin-guides/references/man1/rsetboot.1>`

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: {order:net/hd}.

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Set the bootorder for the next boot. :: 

    curl -X PUT -k 'https://127.0.0.1/xcatws/nodes/node1/nextboot?userName=root&userPW=cluster&pretty=1' -H Content-Type:application/json --data '{"order":"net"}'

