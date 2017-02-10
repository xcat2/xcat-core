/networks/{netname}
===================

GET - Get all the attibutes for the network {netname}
-----------------------------------------------------

The keyword ALLRESOURCES can be used as {netname} which means to get network attributes for all the networks.

Refer to the man page: :doc:`lsdef </guides/admin-guides/references/man1/lsdef.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value, ...}' pairs.

**Example:** 

Get all the attibutes for network 'network1'. :: 

    curl -X GET -k 'https://127.0.0.1/xcatws/networks/network1?userName=root&userPW=cluster&pretty=1'
    {
       "network1":{
          "gateway":"<xcatmaster>",
          "mask":"255.255.255.0",
          "mgtifname":"eth2",
          "net":"10.0.0.0",
          "tftpserver":"10.0.0.119",
          ...
       }
    }

PUT - Change the attibutes for the network {netname}
----------------------------------------------------

Refer to the man page: :doc:`chdef </guides/admin-guides/references/man1/chdef.1>`

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: {attr1:v1,att2:v2,...}.

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Change the attributes mgtifname=eth0 and net=10.1.0.0. :: 

    curl -X PUT -k 'https://127.0.0.1/xcatws/networks/network1?userName=root&userPW=cluster&pretty=1' -H Content-Type:application/json --data '{"mgtifname":"eth0","net":"10.1.0.0"}'

POST - Create the network {netname}. DataBody: {attr1:v1,att2:v2,...}
---------------------------------------------------------------------

Refer to the man page: :doc:`mkdef </guides/admin-guides/references/man1/mkdef.1>`

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: {attr1:v1,att2:v2,...}.

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Create a network with attributes gateway=10.1.0.1, mask=255.255.0.0  :: 

    curl -X POST -k 'https://127.0.0.1/xcatws/networks/network1?userName=root&userPW=cluster&pretty=1' -H Content-Type:application/json --data '{"gateway":"10.1.0.1","mask":"255.255.0.0"}'

DELETE - Remove the network {netname}
-------------------------------------

Refer to the man page: :doc:`rmdef </guides/admin-guides/references/man1/rmdef.1>`

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Delete the network network1 :: 

    curl -X DELETE -k 'https://127.0.0.1/xcatws/networks/network1?userName=root&userPW=cluster&pretty=1'

