/nodes/{noderange}/energy
=========================

GET - Get all the energy status for the node {noderange}.
`````````````````````````````````````````````````````````

Refer to the man page: :doc:`renergy </guides/admin-guides/references/man1/renergy.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...}' pairs.

**Example:** 

Get all the energy attributes. :: 

    curl -X GET -k 'https://127.0.0.1/xcatws/nodes/node1/energy?userName=root&userPW=cluster&pretty=1'

    {
       "node1":{
          "cappingmin":"272.3 W",
          "cappingmax":"354.0 W"
          ...
       }
    }

PUT - Change energy attributes for the node {noderange}.
````````````````````````````````````````````````````````

Refer to the man page: :doc:`renergy </guides/admin-guides/references/man1/renergy.1>`

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: {powerattr:value}.

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Turn on the cappingstatus to [on] :: 

    curl -X PUT -k 'https://127.0.0.1/xcatws/nodes/node1/energy?userName=root&userPW=cluster&pretty=1' \
       -H Content-Type:application/json --data '{"cappingstatus":"on"}'


/nodes/{noderange}/energy/{cappingmaxmin,cappingstatus,cappingvalue ...}
========================================================================

GET - Get the specific energy attributes cappingmaxmin,cappingstatus,cappingvalue ... for the node {noderange}.
```````````````````````````````````````````````````````````````````````````````````````````````````````````````

Refer to the man page: :doc:`renergy </guides/admin-guides/references/man1/renergy.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...}' pairs.

**Example:** 

Get the energy attributes which are specified in the URI. :: 


    curl -X GET -k 'https://127.0.0.1/xcatws/nodes/node1/energy/cappingmaxmin,cappingstatus?userName=root&userPW=cluster&pretty=1'
    {
       "node1":{
          "cappingmin":"272.3 W",
          "cappingmax":"354.0 W"
       }
    }

