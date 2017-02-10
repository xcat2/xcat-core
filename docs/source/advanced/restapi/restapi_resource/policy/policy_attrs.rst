/policy/{policyname}/attrs/{attr1,attr2,attr3,...}
==================================================

GET - Get the specific attributes for the policy {policy_priority}
------------------------------------------------------------------

It will get one or more attributes of a policy.

The keyword ALLRESOURCES can be used as {policy_priority} which means to get policy attributes for all the policies.

Refer to the man page: :doc:`lsdef </guides/admin-guides/references/man1/lsdef.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value, ...}' pairs.

**Example:** 

Get the name and rule attributes for policy 1. :: 

    curl -X GET -k 'https://127.0.0.1/xcatws/policy/1/attrs/name,rule?userName=root&userPW=cluster&pretty=1'
    {
       "1":{
          "name":"root",
          "rule":"allow"
       }
    }

