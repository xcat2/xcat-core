/nodes/{noderange}/inventory
============================

GET - Get all the inventory attibutes
------------------------------------- 

Refer to the man page: :doc:`rinv </guides/admin-guides/references/man1/rinv.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...}' pairs.

**Example:** 

Get all the inventory attributes for node1. :: 


    curl -X GET -k 'https://127.0.0.1/xcatws/nodes/node1/inventory?userName=root&userPW=cluster&pretty=1'
    {
       "node1":{
          "DIMM 21 ":"8GB PC3-12800 (1600 MT/s) ECC RDIMM",
          "DIMM 1 Manufacturer":"Hyundai Electronics",
          "Power Supply 2 Board FRU Number":"94Y8105",
          "DIMM 9 Model":"HMT31GR7EFR4C-PB",
          "DIMM 8 Manufacture Location":"01",
          "DIMM 13 Manufacturer":"Hyundai Electronics",
          "DASD Backplane 4":"Not Present",
          ...
       }
    }

