/nodes/{noderange}/vitals
=========================

GET - Get all the vitals attibutes
----------------------------------

Refer to the man page: :doc:`rvitals </guides/admin-guides/references/man1/rvitals.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...}' pairs.

**Example:** 

Get all the vitails attributes for the node1. :: 


    curl -X GET -k 'https://127.0.0.1/xcatws/nodes/node1/vitals?userName=root&userPW=cluster&pretty=1'
    {
       "node1":{
          "SysBrd Fault":"0",
          "CPUs":"0",
          "Fan 4A Tach":"3330 RPM",
          "Drive 15":"0",
          "SysBrd Vol Fault":"0",
          "nvDIMM Flash":"0",
          "Progress":"0"
          ...
       }
    }


