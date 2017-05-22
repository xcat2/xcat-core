/tables/{tablelist}/rows/{keys}
===============================

Use this for tables that don't have node name as the key of the table, for example: passwd, site, networks, polciy, etc.

{keys} should be the name=value pairs which are used to search table. e.g. {keys} should be [net=192.168.1.0,mask=255.255.255.0] for networks table query since the net and mask are the keys of networks table.

GET - Get attibutes for rows from non-node tables
-------------------------------------------------

**Returns:**

* An object containing each table.  Within each table object is an array of row objects containing the attributes.

**Example:** 

Get row which net=192.168.1.0,mask=255.255.255.0 from networks table. :: 

    curl -X GET -k 'https://127.0.0.1/xcatws/tables/networks/rows/net=192.168.1.0,mask=255.255.255.0?userName=root&userPW=cluster&pretty=1'
    {
       "networks":[
          {
             "mgtifname":"eth0",
             "netname":"192_168_1_0-255_255_255_0",
             "tftpserver":"192.168.1.15",
             "gateway":"192.168.1.100",
             "staticrangeincrement":"1",
             "net":"192.168.1.0",
             "mask":"255.255.255.0"
          }
       ]
    }

PUT - Change the non-node table attibutes for the row that matches the {keys}
-----------------------------------------------------------------------------

**Parameters:**

* A hash of attribute names and values.  DataBody: {attr1:v1,att2:v2,...}.

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Create a route row in the routes table. :: 

    curl -X PUT -k 'https://127.0.0.1/xcatws/tables/routes/rows/routename=privnet?userName=root&userPW=cluster&pretty=1' -H Content-Type:application/json --data '{"net":"10.0.1.0","mask":"255.255.255.0","gateway":"10.0.1.254","ifname":"eth1"}'

DELETE - Delete rows from a non-node table that have the attribute values specified in {keys}
---------------------------------------------------------------------------------------------

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Delete a route row which routename=privnet in the routes table. :: 

    curl -X DELETE -k 'https://127.0.0.1/xcatws/tables/routes/rows/routename=privnet?userName=root&userPW=cluster&pretty=1'

