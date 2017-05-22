/services/slpnodes/{CEC|FRAME|MM|IVM|RSA|HMC|CMM|IMM2|FSP...}
=============================================================

The slp nodes with specific service type in the xCAT cluster

GET - Get all the nodes with specific slp service type in the network
---------------------------------------------------------------------

Refer to the man page: :doc:`lsslp </guides/admin-guides/references/man1/lsslp.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...}' pairs.

**Example:** 

Get all the CMM nodes which support slp in the network. :: 


    curl -X GET -k 'https://127.0.0.1/xcatws/services/slpnodes/CMM?userName=root&userPW=cluster&pretty=1'
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
       "Server--SNY014BG27A01K":{
          "mpa":"Server--SNY014BG27A01K",
          "otherinterfaces":"10.1.9.106",
          "serial":"100CF0A",
          "mtm":"789392X",
          "hwtype":"cmm",
          "side":"1",
          "objtype":"node",
          "nodetype":"mp",
          "groups":"cmm,all,cmm-zet",
          "mgt":"blade",
          "hidden":"0",
          "mac":"34:40:b5:df:0a:be"
       }
    }


