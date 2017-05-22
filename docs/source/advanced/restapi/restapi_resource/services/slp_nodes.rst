/services/slpnodes
==================

The nodes which support SLP in the xCAT cluster

GET - Get all the nodes which support slp protocol in the network
-----------------------------------------------------------------

Refer to the man page: :doc:`lsslp </guides/admin-guides/references/man1/lsslp.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...}' pairs.

**Example:** 

Get all the nodes which support slp in the network. :: 

    curl -X GET -k 'https://127.0.0.1/xcatws/services/slpnodes?userName=root&userPW=cluster&pretty=1'
    {
       "ngpcmm01":{
          "mpa":"ngpcmm01",
          "otherinterfaces":"10.1.9.101",
          "serial":"100037A",
          "mtm":"789392X",
          "hwtype":"cmm",
          "side":"2",
          "objtype":"node",
          "nodetype":"mp",
          "groups":"cmm,all,cmm-zet",
          "mgt":"blade",
          "hidden":"0",
          "mac":"5c:f3:fc:25:da:99"
       },
       ...
    }

