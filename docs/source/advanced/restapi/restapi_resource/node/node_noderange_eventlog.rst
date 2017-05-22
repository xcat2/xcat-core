/nodes/{noderange}/eventlog
===========================

GET - Get all the eventlog for the node {noderange}
---------------------------------------------------

Refer to the man page: :doc:`reventlog </guides/admin-guides/references/man1/reventlog.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...}' pairs.

**Example:** 

Get all the eventlog for node1. :: 


    curl -X GET -k 'https://127.0.0.1/xcatws/nodes/node1/eventlog?userName=root&userPW=cluster&pretty=1'
    {
       "node1":{
          "eventlog":[
             "03/19/2014 15:17:58 Event Logging Disabled, Log Area Reset/Cleared (SEL Fullness)"
          ]
       }
    }

DELETE - Clean up the event log for the node {noderange}
--------------------------------------------------------

Refer to the man page: :doc:`reventlog </guides/admin-guides/references/man1/reventlog.1>`

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Delete all the event log for node1. :: 


    curl -X DELETE -k 'https://127.0.0.1/xcatws/nodes/node1/eventlog?userName=root&userPW=cluster&pretty=1'
    [
       {
          "eventlog":[
             "SEL cleared"
          ],
          "name":"node1"
       }
    ]

