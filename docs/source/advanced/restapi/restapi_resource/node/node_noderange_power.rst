/nodes/{noderange}/power
========================

GET - Get the power status for the node {noderange}.
````````````````````````````````````````````````````

Refer to the man page: :doc:`rpower </guides/admin-guides/references/man1/rpower.1>`

**Returns:**

* An object which includes multiple entries like: <nodename> : { power : <powerstate> }

**Example:** 

Get the power status. :: 


    curl -X GET -k 'https://127.0.0.1/xcatws/nodes/node1/power?userName=root&userPW=cluster&pretty=1'
    {
       "node1":{
          "power":"on"
       }
    }

PUT - Change power status for the node {noderange}.
```````````````````````````````````````````````````

Refer to the man page: :doc:`rpower </guides/admin-guides/references/man1/rpower.1>`

**Parameters:**

* Json Formatted DataBody: {action:on/off/reset ...}.

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Change the power status to on :: 

    curl -X PUT -k 'https://127.0.0.1/xcatws/nodes/node1/power?userName=root&userPW=cluster&pretty=1' \
       -H Content-Type:application/json --data '{"action":"on"}'

