/nodes/{noderange}/inventory/{pci|model...}
===========================================

GET - Get the specific inventory attibutes
------------------------------------------

Refer to the man page: :doc:`rinv </guides/admin-guides/references/man1/rinv.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...}' pairs.

**Example:** 

Get the 'model' inventory attribute for node1. :: 


    curl -X GET -k 'https://127.0.0.1/xcatws/nodes/node1/inventory/model?userName=root&userPW=cluster&pretty=1'
    {
       "node1":{
          "System Description":"System x3650 M4",
          "System Model/MTM":"7915C2A"
       }
    }
