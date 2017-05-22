/nodes/{noderange}/sp/{community|ip|netmask|...}
================================================

GET - Get the specific attributes for service processor resource.
`````````````````````````````````````````````````````````````````

Refer to the man page: :doc:`rspconfig </guides/admin-guides/references/man1/rspconfig.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...}' pairs.

**Example:** 

Get the snmp community for the service processor of node1. :: 


    curl -X GET -k 'https://127.0.0.1/xcatws/nodes/node1/sp/community?userName=root&userPW=cluster&pretty=1'
    {
       "node1":{
          "SP SNMP Community":"public"
       }
    }

PUT - Change the specific attributes for the service processor resource. 
`````````````````````````````````````````````````````````````````````````

Refer to the man page: :doc:`rspconfig </guides/admin-guides/references/man1/rspconfig.1>`

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: {community:public}.

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Set the snmp community to [mycommunity]. :: 

    curl -X PUT -k 'https://127.0.0.1/xcatws/nodes/node1/sp/community?userName=root&userPW=cluster&pretty=1' \
       -H Content-Type:application/json --data '{"value":"mycommunity"}'


