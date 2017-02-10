/groups/{groupname}/attrs/{attr1,attr2,attr3,...}
=================================================

GET - Get the specific attributes for the group {groupname}
-----------------------------------------------------------

Refer to the man page: :doc:`lsdef </guides/admin-guides/references/man1/lsdef.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...}' pairs.

**Example:** 

Get the attributes {mgt,netboot} for group all :: 


    curl -X GET -k 'https://127.0.0.1/xcatws/groups/all/attrs/mgt,netboot?userName=root&userPW=cluster&pretty=1'
    {
       "all":{
          "netboot":"yaboot",
          "mgt":"dfm"
       }
    }

