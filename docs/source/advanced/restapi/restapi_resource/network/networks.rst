/networks
=========

This resource can be used to display all the networks which have been defined in the xCAT database.

GET - Get all the networks in xCAT
----------------------------------

The attributes details for the networks will not be displayed.

Refer to the man page: :doc:`lsdef </guides/admin-guides/references/man1/lsdef.1>`

**Returns:**

* Json format: An array of networks names.

**Example:** 

Get all the networks names from xCAT database. :: 


    curl -X GET -k 'https://127.0.0.1/xcatws/networks?userName=root&userPW=cluster&pretty=1'
    [
       "network1",
       "network2",
       "network3",
    ]

POST - Create the networks resources base on the network configuration on xCAT MN
---------------------------------------------------------------------------------

Refer to the man page: :doc:`makenetworks </guides/admin-guides/references/man8/makenetworks.8>`

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: {attr1:v1,att2:v2,...}.

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Create the networks resources base on the network configuration on xCAT MN. :: 

    curl -X POST -k 'https://127.0.0.1/xcatws/networks?userName=root&userPW=cluster&pretty=1'
