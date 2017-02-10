/networks/{netname}/attrs/{attr1,attr2,attr3,...}
=================================================

GET - Get the specific attributes for the network {netname}
-----------------------------------------------------------

The keyword ALLRESOURCES can be used as {netname} which means to get network attributes for all the networks.

Refer to the man page: :doc:`lsdef </guides/admin-guides/references/man1/lsdef.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value, ...}' pairs.

**Example:** 

Get the attributes {groups,mgt,netboot} for network network1 :: 

    curl -X GET -k 'https://127.0.0.1/xcatws/networks/network1/attrs/gateway,mask,mgtifname,net,tftpserver?userName=root&userPW=cluster&pretty=1'
    {
       "network1":{
          "gateway":"9.114.34.254",
          "mask":"255.255.255.0",
             }
    }
