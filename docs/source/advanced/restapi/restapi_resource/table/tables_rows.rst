/tables/{tablelist}/rows
========================

Use this for tables that don't have node name as the key of the table, for example: passwd, site, networks, polciy, etc.

GET - Get all rows from non-node tables
---------------------------------------

**Returns:**

* An object containing each table.  Within each table object is an array of row objects containing the attributes.

**Example:** 

Get all rows from networks table. :: 

    curl -X GET -k 'https://127.0.0.1/xcatws/tables/networks/rows?userName=root&userPW=cluster&pretty=1'
    {
       "networks":[
          {
             "netname":"192_168_13_0-255_255_255_0",
             "gateway":"192.168.13.254",
             "staticrangeincrement":"1",
             "net":"192.168.13.0",
             "mask":"255.255.255.0"
          },
          {
             "netname":"192_168_12_0-255_255_255_0",
             "gateway":"192.168.12.254",
             "staticrangeincrement":"1",
             "net":"192.168.12.0",
             "mask":"255.255.255.0"
          },
       ]
    }


