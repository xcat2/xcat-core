/groups/{groupname}
===================

GET - Get all the attibutes for the group {groupname}
-----------------------------------------------------

Refer to the man page: :doc:`lsdef </guides/admin-guides/references/man1/lsdef.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...}' pairs.

**Example:** 

Get all the attibutes for group 'all'. :: 

    curl -X GET -k 'https://127.0.0.1/xcatws/groups/all?userName=root&userPW=cluster&pretty=1'
    {
       "all":{
          "members":"zxnode2,nodexxx,node1,node4"
       }
    }

PUT - Change the attibutes for the group {groupname}
----------------------------------------------------

Refer to the man page: :doc:`chdef </guides/admin-guides/references/man1/chdef.1>`

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: {attr1:v1,att2:v2,...}.

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Change the attributes mgt=dfm and netboot=yaboot. :: 


    curl -X PUT -k 'https://127.0.0.1/xcatws/groups/all?userName=root&userPW=cluster&pretty=1' \
       -H Content-Type:application/json --data '{"mgt":"dfm","netboot":"yaboot"}'
