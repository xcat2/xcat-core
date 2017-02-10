/policy
=======

GET - Get all the policies in xCAT
----------------------------------

It will dislplay all the policy resource.

Refer to the man page: :doc:`lsdef </guides/admin-guides/references/man1/lsdef.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...}' pairs.

**Example:** 

Get all the policy objects. :: 

    curl -X GET -k 'https://127.0.0.1/xcatws/policy?userName=root&userPW=cluster&pretty=1'
    [
       "1",
       "1.2",
       "2",
       "4.8"
    ]
