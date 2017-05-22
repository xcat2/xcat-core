/tables/{tablelist}/rows/{keys}/{attr1,attr2,attr3,...}
=======================================================

Use this for tables that don't have node name as the key of the table, for example: passwd, site, networks, polciy, etc.

GET - Get specific attibutes for rows from non-node tables
----------------------------------------------------------

**Returns:**

* An object containing each table.  Within each table object is an array of row objects containing the attributes.

**Example:** 

Get attributes mgtifname and tftpserver which net=192.168.1.0,mask=255.255.255.0 from networks table. :: 

    curl -X GET -k 'https://127.0.0.1/xcatws/tables/networks/rows/net=192.168.1.0,mask=255.255.255.0/mgtifname,tftpserver?userName=root&userPW=cluster&pretty=1'
    {
       "networks":[
          {
             "mgtifname":"eth0",
             "tftpserver":"192.168.1.15"
          }
       ]
    }
