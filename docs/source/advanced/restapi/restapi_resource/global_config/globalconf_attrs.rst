/globalconf/attrs/{attr1,attr2,attr3,...}
=========================================

GET - Get the specific configuration in global
----------------------------------------------

It will display one or more global attributes.

Refer to the man page: :doc:`lsdef </guides/admin-guides/references/man1/lsdef.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value, ...}' pairs.

**Example:** 

Get the 'master' and 'domain' configuration. :: 

    curl -X GET -k 'https://127.0.0.1/xcatws/globalconf/attrs/master,domain?userName=root&userPW=cluster&pretty=1'
    {
       "clustersite":{
          "domain":"cluster.com",
          "master":"192.168.1.15"
       }
    }

PUT - Change the global attributes
----------------------------------

It can be used for changing/adding global attributes.

Refer to the man page: :doc:`chdef </guides/admin-guides/references/man1/chdef.1>`

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: {attr1:v1,att2:v2,...}.

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Change/Add the domain attribute. :: 

    curl -X PUT -k 'https://127.0.0.1/xcatws/globalconf/attrs/domain?userName=root&userPW=cluster&pretty=1' -H Content-Type:application/json --data '{"domain":"cluster.com"}'

DELETE - Remove the site attributes
-----------------------------------

Used for remove one or more global attributes.

Refer to the man page: :doc:`chdef </guides/admin-guides/references/man1/chdef.1>`

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Remove the domain configure. :: 

    curl -X DELETE -k 'https://127.0.0.1/xcatws/globalconf/attrs/domain?userName=root&userPW=cluster&pretty=1'

