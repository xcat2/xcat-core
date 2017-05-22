/policy/{policy_priority}
=========================

GET - Get all the attibutes for a policy {policy_priority}
----------------------------------------------------------

It will display all the policy attributes for one policy resource.

The keyword ALLRESOURCES can be used as {policy_priority}which means to get policy attributes for all the policies.

Refer to the man page: :doc:`lsdef </guides/admin-guides/references/man1/lsdef.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...} pairs.

**Example:** 

Get all the attribute for policy 1. :: 

    curl -X GET -k 'https://127.0.0.1/xcatws/policy/1?userName=root&userPW=cluster&pretty=1'
    {
       "1":{
          "name":"root",
          "rule":"allow"
       }
    }

PUT - Change the attibutes for the policy {policy_priority}
-----------------------------------------------------------

It will change one or more attributes for a policy.

Refer to the man page: :doc:`chdef </guides/admin-guides/references/man1/chdef.1>`

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: {attr1:v1,att2:v2,...}

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}

**Example:** 

Set the name attribute for policy 3. :: 


    curl -X PUT -k 'https://127.0.0.1/xcatws/policy/3?userName=root&userPW=cluster&pretty=1' \
       -H Content-Type:application/json --data '{"name":"root"}

POST - Create the policy {policyname} DataBody: {attr1:v1,att2:v2...}
---------------------------------------------------------------------

It will creat a new policy resource.

Refer to the man page: :doc:`chdef </guides/admin-guides/references/man1/chdef.1>`

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: {attr1:v1,att2:v2,...}

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}

**Example:** 

Create a new policy 10. :: 

    curl -X POST -k 'https://127.0.0.1/xcatws/policy/10?userName=root&userPW=cluster&pretty=1' \
       -H Content-Type:application/json --data '{"name":"root","commands":"rpower"}

DELETE - Remove the policy {policy_priority}
--------------------------------------------

Remove one or more policy resource.

Refer to the man page: :doc:`rmdef </guides/admin-guides/references/man1/rmdef.1>`

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}

**Example:** 

Delete the policy 10. :: 

    curl -X DELETE -k 'https://127.0.0.1/xcatws/policy/10?userName=root&userPW=cluster&pretty=1'
