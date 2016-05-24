Token Resources
===============

The URI list which can be used to create tokens for account .

[URI:/tokens] - The authentication token resource.
--------------------------------------------------

POST - Create a token.
``````````````````````

**Returns:**

* An array of all the global configuration list.

**Example:** 

Aquire a token for user 'root'. :: 


    #curl -X POST -k 'https://127.0.0.1/xcatws/tokens?userName=root&userPW=cluster&pretty=1' -H Content-Type:application/json --data '{"userName":"root","userPW":"cluster"}'
    {
       "token":{
          "id":"a6e89b59-2b23-429a-b3fe-d16807dd19eb",
          "expire":"2014-3-8 14:55:0"
       }
    }

Node Resources
==============

The URI list which can be used to create, query, change and manage node objects.

[URI:/nodes] - The node list resource.
--------------------------------------

This resource can be used to display all the nodes which have been defined in the xCAT database.

GET - Get all the nodes in xCAT.
````````````````````````````````

The attributes details for the node will not be displayed.

Refer to the man page: :doc:`lsdef </guides/admin-guides/references/man1/lsdef.1>`

**Returns:**

* Json format: An array of node names.

**Example:** 

Get all the node names from xCAT database. :: 


    #curl -X GET -k 'https://127.0.0.1/xcatws/nodes?userName=root&userPW=cluster&pretty=1'
    [
       "node1",
       "node2",
       "node3",
    ]

[URI:/nodes/{noderange}] - The node resource
--------------------------------------------

GET - Get all the attibutes for the node {noderange}.
`````````````````````````````````````````````````````

The keyword ALLRESOURCES can be used as {noderange} which means to get node attributes for all the nodes.

Refer to the man page: :doc:`lsdef </guides/admin-guides/references/man1/lsdef.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...}' pairs.

**Example:** 

Get all the attibutes for node 'node1'. :: 


    #curl -X GET -k 'https://127.0.0.1/xcatws/nodes/node1?userName=root&userPW=cluster&pretty=1'
    {
       "node1":{
          "profile":"compute",
          "netboot":"xnba",
          "arch":"x86_64",
          "mgt":"ipmi",
          "groups":"all",
          ...
       }
    }

PUT - Change the attibutes for the node {noderange}.
````````````````````````````````````````````````````

Refer to the man page: :doc:`chdef </guides/admin-guides/references/man1/chdef.1>`

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: {attr1:v1,att2:v2,...}.

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Change the attributes mgt=dfm and netboot=yaboot. :: 


    #curl -X PUT -k 'https://127.0.0.1/xcatws/nodes/node1?userName=root&userPW=cluster&pretty=1' -H Content-Type:application/json --data '{"mgt":"dfm","netboot":"yaboot"}'


POST - Create the node {noderange}.
```````````````````````````````````

Refer to the man page: :doc:`mkdef </guides/admin-guides/references/man1/mkdef.1>`

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: {attr1:v1,att2:v2,...}.

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Create a node with attributes groups=all, mgt=dfm and netboot=yaboot :: 


    #curl -X POST -k 'https://127.0.0.1/xcatws/nodes/node1?userName=root&userPW=cluster&pretty=1' -H Content-Type:application/json --data '{"groups":"all","mgt":"dfm","netboot":"yaboot"}'

DELETE - Remove the node {noderange}.
`````````````````````````````````````

Refer to the man page: :doc:`rmdef </guides/admin-guides/references/man1/rmdef.1>`

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Delete the node node1 :: 

    #curl -X DELETE -k 'https://127.0.0.1/xcatws/nodes/node1?userName=root&userPW=cluster&pretty=1'

[URI:/nodes/{noderange}/attrs/{attr1,attr2,attr3 ...}] - The attributes resource for the node {noderange}
---------------------------------------------------------------------------------------------------------

GET - Get the specific attributes for the node {noderange}.
```````````````````````````````````````````````````````````

The keyword ALLRESOURCES can be used as {noderange} which means to get node attributes for all the nodes.

Refer to the man page: :doc:`lsdef </guides/admin-guides/references/man1/lsdef.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...}' pairs.

**Example:** 

Get the attributes {groups,mgt,netboot} for node node1 :: 


    #curl -X GET -k 'https://127.0.0.1/xcatws/nodes/node1/attrs/groups,mgt,netboot?userName=root&userPW=cluster&pretty=1'
    {
       "node1":{
          "netboot":"xnba",
          "mgt":"ipmi",
          "groups":"all"
       }
    }

[URI:/nodes/{noderange}/host] - The mapping of ip and hostname for the node {noderange}
---------------------------------------------------------------------------------------

POST - Create the mapping of ip and hostname record for the node {noderange}.
`````````````````````````````````````````````````````````````````````````````

Refer to the man page: :doc:`makehosts </guides/admin-guides/references/man8/makehosts.8>`

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Create the mapping of ip and hostname record for node 'node1'. :: 

    #curl -X POST -k 'https://127.0.0.1/xcatws/nodes/node1/host?userName=root&userPW=cluster&pretty=1'

[URI:/nodes/{noderange}/dns] - The dns record resource for the node {noderange}
-------------------------------------------------------------------------------

POST - Create the dns record for the node {noderange}.
``````````````````````````````````````````````````````

The prerequisite of the POST operation is the mapping of ip and noderange for the node has been added in the /etc/hosts.

Refer to the man page: :doc:`makedns </guides/admin-guides/references/man8/makedns.8>`

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Create the dns record for node 'node1'. :: 

    #curl -X POST -k 'https://127.0.0.1/xcatws/nodes/node1/dns?userName=root&userPW=cluster&pretty=1'

DELETE - Remove the dns record for the node {noderange}.
````````````````````````````````````````````````````````

Refer to the man page: :doc:`makedns </guides/admin-guides/references/man8/makedns.8>`

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Delete the dns record for node node1 :: 

    #curl -X DELETE -k 'https://127.0.0.1/xcatws/nodes/node1/dns?userName=root&userPW=cluster&pretty=1'

[URI:/nodes/{noderange}/dhcp] - The dhcp record resource for the node {noderange}
---------------------------------------------------------------------------------

POST - Create the dhcp record for the node {noderange}.
```````````````````````````````````````````````````````

Refer to the man page: :doc:`makedhcp </guides/admin-guides/references/man8/makedhcp.8>`

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Create the dhcp record for node 'node1'. :: 

    #curl -X POST -k 'https://127.0.0.1/xcatws/nodes/node1/dhcp?userName=root&userPW=cluster&pretty=1'

DELETE - Remove the dhcp record for the node {noderange}.
`````````````````````````````````````````````````````````

Refer to the man page: :doc:`makedhcp </guides/admin-guides/references/man8/makedhcp.8>`

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Delete the dhcp record for node node1 :: 

    #curl -X DELETE -k 'https://127.0.0.1/xcatws/nodes/node1/dhcp?userName=root&userPW=cluster&pretty=1'

[URI:/nodes/{noderange}/nodestat}] - The attributes resource for the node {noderange}
-------------------------------------------------------------------------------------

GET - Get the running status for the node {noderange}.
``````````````````````````````````````````````````````

Refer to the man page: :doc:`nodestat </guides/admin-guides/references/man1/nodestat.1>`

**Returns:**

* An object which includes multiple entries like: <nodename> : { nodestat : <node state> }

**Example:** 

Get the running status for node node1 :: 


    #curl -X GET -k 'https://127.0.0.1/xcatws/nodes/node1/nodestat?userName=root&userPW=cluster&pretty=1'
    {
       "node1":{
          "nodestat":"noping"
       }
    }

[URI:/nodes/{noderange}/subnodes] - The sub-nodes resources for the node {noderange}
------------------------------------------------------------------------------------

GET - Return the Children nodes for the node {noderange}.
`````````````````````````````````````````````````````````

Refer to the man page: :doc:`rscan </guides/admin-guides/references/man1/rscan.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...}' pairs.

**Example:** 

Get all the children nodes for node 'node1'. :: 


    #curl -X GET -k 'https://127.0.0.1/xcatws/nodes/node1/subnodes?userName=root&userPW=cluster&pretty=1'
    {
       "cmm01node09":{
          "mpa":"ngpcmm01",
          "parent":"ngpcmm01",
          "serial":"1035CDB",
          "mtm":"789523X",
          "cons":"fsp",
          "hwtype":"blade",
          "objtype":"node",
          "groups":"blade,all,p260",
          "mgt":"fsp",
          "nodetype":"ppc,osi",
          "slotid":"9",
          "hcp":"10.1.9.9",
          "id":"1"
       },
       ...
    }

[URI:/nodes/{noderange}/power] - The power resource for the node {noderange}
----------------------------------------------------------------------------

GET - Get the power status for the node {noderange}.
````````````````````````````````````````````````````

Refer to the man page: :doc:`rpower </guides/admin-guides/references/man1/rpower.1>`

**Returns:**

* An object which includes multiple entries like: <nodename> : { power : <powerstate> }

**Example:** 

Get the power status. :: 


    #curl -X GET -k 'https://127.0.0.1/xcatws/nodes/node1/power?userName=root&userPW=cluster&pretty=1'
    {
       "node1":{
          "power":"on"
       }
    }

PUT - Change power status for the node {noderange}.
```````````````````````````````````````````````````

Refer to the man page: :doc:`rpower </guides/admin-guides/references/man1/rpower.1>`

**Parameters:**

* Json Formatted DataBody: {action:on/off/reset ...}.

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Change the power status to on :: 

    #curl -X PUT -k 'https://127.0.0.1/xcatws/nodes/node1/power?userName=root&userPW=cluster&pretty=1' -H Content-Type:application/json --data '{"action":"on"}'

[URI:/nodes/{noderange}/energy] - The energy resource for the node {noderange}
------------------------------------------------------------------------------

GET - Get all the energy status for the node {noderange}.
`````````````````````````````````````````````````````````

Refer to the man page: :doc:`renergy </guides/admin-guides/references/man1/renergy.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...}' pairs.

**Example:** 

Get all the energy attributes. :: 

    #curl -X GET -k 'https://127.0.0.1/xcatws/nodes/node1/energy?userName=root&userPW=cluster&pretty=1'

    {
       "node1":{
          "cappingmin":"272.3 W",
          "cappingmax":"354.0 W"
          ...
       }
    }

PUT - Change energy attributes for the node {noderange}.
````````````````````````````````````````````````````````

Refer to the man page: :doc:`renergy </guides/admin-guides/references/man1/renergy.1>`

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: {powerattr:value}.

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Turn on the cappingstatus to [on] :: 

    #curl -X PUT -k 'https://127.0.0.1/xcatws/nodes/node1/energy?userName=root&userPW=cluster&pretty=1' -H Content-Type:application/json --data '{"cappingstatus":"on"}'

[URI:/nodes/{noderange}/energy/{cappingmaxmin,cappingstatus,cappingvalue ...}] - The specific energy attributes resource for the node {noderange}
-------------------------------------------------------------------------------------------------------------------------------------------------

GET - Get the specific energy attributes cappingmaxmin,cappingstatus,cappingvalue ... for the node {noderange}.
```````````````````````````````````````````````````````````````````````````````````````````````````````````````

Refer to the man page: :doc:`renergy </guides/admin-guides/references/man1/renergy.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...}' pairs.

**Example:** 

Get the energy attributes which are specified in the URI. :: 


    #curl -X GET -k 'https://127.0.0.1/xcatws/nodes/node1/energy/cappingmaxmin,cappingstatus?userName=root&userPW=cluster&pretty=1'
    {
       "node1":{
          "cappingmin":"272.3 W",
          "cappingmax":"354.0 W"
       }
    }

[URI:/nodes/{noderange}/sp/{community|ip|netmask|...}] - The attribute resource of service processor for the node {noderange}
-----------------------------------------------------------------------------------------------------------------------------

GET - Get the specific attributes for service processor resource.
`````````````````````````````````````````````````````````````````

Refer to the man page: :doc:`rspconfig </guides/admin-guides/references/man1/rspconfig.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...}' pairs.

**Example:** 

Get the snmp community for the service processor of node1. :: 


    #curl -X GET -k 'https://127.0.0.1/xcatws/nodes/node1/sp/community?userName=root&userPW=cluster&pretty=1'
    {
       "node1":{
          "SP SNMP Community":"public"
       }
    }

PUT - Change the specific attributes for the service processor resource. 
`````````````````````````````````````````````````````````````````````````

Refer to the man page: :doc:`rspconfig </guides/admin-guides/references/man1/rspconfig.1>`

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: {community:public}.

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Set the snmp community to [mycommunity]. :: 

    #curl -X PUT -k 'https://127.0.0.1/xcatws/nodes/node1/sp/community?userName=root&userPW=cluster&pretty=1' -H Content-Type:application/json --data '{"value":"mycommunity"}'

[URI:/nodes/{noderange}/nextboot] - The temporary bootorder resource in next boot for the node {noderange}
----------------------------------------------------------------------------------------------------------

GET - Get the next bootorder.
`````````````````````````````

Refer to the man page: :doc:`rsetboot </guides/admin-guides/references/man1/rsetboot.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...}' pairs.

**Example:** 

Get the bootorder for the next boot. (It's only valid after setting.) :: 


    #curl -X GET -k 'https://127.0.0.1/xcatws/nodes/node1/nextboot?userName=root&userPW=cluster&pretty=1'
    {
       "node1":{
          "nextboot":"Network"
       }
    }

PUT - Change the next boot order. 
``````````````````````````````````

Refer to the man page: :doc:`rsetboot </guides/admin-guides/references/man1/rsetboot.1>`

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: {order:net/hd}.

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Set the bootorder for the next boot. :: 

    #curl -X PUT -k 'https://127.0.0.1/xcatws/nodes/node1/nextboot?userName=root&userPW=cluster&pretty=1' -H Content-Type:application/json --data '{"order":"net"}'

[URI:/nodes/{noderange}/bootstate] - The boot state resource for node {noderange}.
----------------------------------------------------------------------------------

GET - Get boot state.
`````````````````````

Refer to the man page: :doc:`nodeset </guides/admin-guides/references/man1/nimnodeset.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...}' pairs.

**Example:** 

Get the next boot state for the node1. :: 


    #curl -X GET -k 'https://127.0.0.1/xcatws/nodes/node1/bootstate?userName=root&userPW=cluster&pretty=1'
    {
       "node1":{
          "bootstat":"boot"
       }
    }

PUT - Set the boot state.
`````````````````````````

Refer to the man page: :doc:`nodeset </guides/admin-guides/references/man1/nimnodeset.1>`

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: {osimage:xxx}/{state:offline}.

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Set the next boot state for the node1. :: 

    #curl -X PUT -k 'https://127.0.0.1/xcatws/nodes/node1/bootstate?userName=root&userPW=cluster&pretty=1' -H Content-Type:application/json --data '{"osimage":"rhels6.4-x86_64-install-compute"}'

[URI:/nodes/{noderange}/vitals] - The vitals resources for the node {noderange}
-------------------------------------------------------------------------------

GET - Get all the vitals attibutes.
```````````````````````````````````

Refer to the man page: :doc:`rvitals </guides/admin-guides/references/man1/rvitals.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...}' pairs.

**Example:** 

Get all the vitails attributes for the node1. :: 


    #curl -X GET -k 'https://127.0.0.1/xcatws/nodes/node1/vitals?userName=root&userPW=cluster&pretty=1'
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

[URI:/nodes/{noderange}/vitals/{temp|voltage|wattage|fanspeed|power|leds...}] - The specific vital attributes for the node {noderange}
--------------------------------------------------------------------------------------------------------------------------------------

GET - Get the specific vitals attibutes.
````````````````````````````````````````

Refer to the man page: :doc:`rvitals </guides/admin-guides/references/man1/rvitals.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...}' pairs.

**Example:** 

Get the 'fanspeed' vitals attribute. :: 


    #curl -X GET -k 'https://127.0.0.1/xcatws/nodes/node1/vitals/fanspeed?userName=root&userPW=cluster&pretty=1'
    {
       "node1":{
          "Fan 1A Tach":"3219 RPM",
          "Fan 4B Tach":"2688 RPM",
          "Fan 3B Tach":"2560 RPM",
          "Fan 4A Tach":"3330 RPM",
          "Fan 2A Tach":"3293 RPM",
          "Fan 1B Tach":"2592 RPM",
          "Fan 3A Tach":"3182 RPM",
          "Fan 2B Tach":"2592 RPM"
       }
    }

[URI:/nodes/{noderange}/inventory] - The inventory attributes for the node {noderange}
--------------------------------------------------------------------------------------

GET - Get all the inventory attibutes.
``````````````````````````````````````

Refer to the man page: :doc:`rinv </guides/admin-guides/references/man1/rinv.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...}' pairs.

**Example:** 

Get all the inventory attributes for node1. :: 


    #curl -X GET -k 'https://127.0.0.1/xcatws/nodes/node1/inventory?userName=root&userPW=cluster&pretty=1'
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

[URI:/nodes/{noderange}/inventory/{pci|model...}] - The specific inventory attributes for the node {noderange}
--------------------------------------------------------------------------------------------------------------

GET - Get the specific inventory attibutes.
```````````````````````````````````````````

Refer to the man page: :doc:`rinv </guides/admin-guides/references/man1/rinv.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...}' pairs.

**Example:** 

Get the 'model' inventory attribute for node1. :: 


    #curl -X GET -k 'https://127.0.0.1/xcatws/nodes/node1/inventory/model?userName=root&userPW=cluster&pretty=1'
    {
       "node1":{
          "System Description":"System x3650 M4",
          "System Model/MTM":"7915C2A"
       }
    }

[URI:/nodes/{noderange}/eventlog] - The eventlog resource for the node {noderange}
----------------------------------------------------------------------------------

GET - Get all the eventlog for the node {noderange}.
````````````````````````````````````````````````````

Refer to the man page: :doc:`reventlog </guides/admin-guides/references/man1/reventlog.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...}' pairs.

**Example:** 

Get all the eventlog for node1. :: 


    #curl -X GET -k 'https://127.0.0.1/xcatws/nodes/node1/eventlog?userName=root&userPW=cluster&pretty=1'
    {
       "node1":{
          "eventlog":[
             "03/19/2014 15:17:58 Event Logging Disabled, Log Area Reset/Cleared (SEL Fullness)"
          ]
       }
    }

DELETE - Clean up the event log for the node {noderange}.
`````````````````````````````````````````````````````````

Refer to the man page: :doc:`reventlog </guides/admin-guides/references/man1/reventlog.1>`

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Delete all the event log for node1. :: 


    #curl -X DELETE -k 'https://127.0.0.1/xcatws/nodes/node1/eventlog?userName=root&userPW=cluster&pretty=1'
    [
       {
          "eventlog":[
             "SEL cleared"
          ],
          "name":"node1"
       }
    ]

[URI:/nodes/{noderange}/beacon] - The beacon resource for the node {noderange}
------------------------------------------------------------------------------

PUT - Change the beacon status for the node {noderange}.
````````````````````````````````````````````````````````

Refer to the man page: :doc:`rbeacon </guides/admin-guides/references/man1/rbeacon.1>`

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: {action:on/off/blink}.

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Turn on the beacon. :: 


    #curl -X PUT -k 'https://127.0.0.1/xcatws/nodes/node1/beacon?userName=root&userPW=cluster&pretty=1' -H Content-Type:application/json --data '{"action":"on"}'
    [
       {
          "name":"node1",
          "beacon":"on"
       }
    ]

[URI:/nodes/{noderange}/updating] - The updating resource for the node {noderange}
----------------------------------------------------------------------------------

POST - Update the node with file syncing, software maintenance and rerun postscripts.
`````````````````````````````````````````````````````````````````````````````````````

Refer to the man page: :doc:`updatenode </guides/admin-guides/references/man1/updatenode.1>`

**Returns:**

* An array of messages for performing the node updating.

**Example:** 

Initiate an updatenode process. :: 


    #curl -X POST -k 'https://127.0.0.1/xcatws/nodes/node2/updating?userName=root&userPW=cluster&pretty=1'
    [
       "There were no syncfiles defined to process. File synchronization has completed.",
       "Performing software maintenance operations. This could take a while, if there are packages to install.
    ",
       "node2: Wed Mar 20 15:01:43 CST 2013 Running postscript: ospkgs",
       "node2: Running of postscripts has completed."
    ]

[URI:/nodes/{noderange}/filesyncing] - The filesyncing resource for the node {noderange}
----------------------------------------------------------------------------------------

POST - Sync files for the node {noderange}.
```````````````````````````````````````````

Refer to the man page: :doc:`updatenode </guides/admin-guides/references/man1/updatenode.1>`

**Returns:**

* An array of messages for performing the file syncing for the node.

**Example:** 

Initiate an file syncing process. :: 


    #curl -X POST -k 'https://127.0.0.1/xcatws/nodes/node2/filesyncing?userName=root&userPW=cluster&pretty=1'
    [
       "There were no syncfiles defined to process. File synchronization has completed."
    ]

[URI:/nodes/{noderange}/sw] - The software maintenance for the node {noderange}
-------------------------------------------------------------------------------

POST - Perform the software maintenance process for the node {noderange}.
`````````````````````````````````````````````````````````````````````````

Refer to the man page: :doc:`updatenode </guides/admin-guides/references/man1/updatenode.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...}' pairs.

**Example:** 

Initiate an software maintenance process. :: 


    #curl -X POST -k 'https://127.0.0.1/xcatws/nodes/node2/sw?userName=root&userPW=cluster&pretty=1'
    {
       "node2":[
          " Wed Apr  3 09:05:42 CST 2013 Running postscript: ospkgs",
          " Unable to read consumer identity",
          " Postscript: ospkgs exited with code 0",
          " Wed Apr  3 09:05:44 CST 2013 Running postscript: otherpkgs",
          " ./otherpkgs: no extra rpms to install",
          " Postscript: otherpkgs exited with code 0",
          " Running of Software Maintenance has completed."
       ]
    }

[URI:/nodes/{noderange}/postscript] - The postscript resource for the node {noderange}
--------------------------------------------------------------------------------------

POST - Run the postscripts for the node {noderange}.
````````````````````````````````````````````````````

Refer to the man page: :doc:`updatenode </guides/admin-guides/references/man1/updatenode.1>`

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: {scripts:[p1,p2,p3,...]}.

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...}' pairs.

**Example:** 

Initiate an updatenode process. :: 


    #curl -X POST -k 'https://127.0.0.1/xcatws/nodes/node2/postscript?userName=root&userPW=cluster&pretty=1' -H Content-Type:application/json --data '{"scripts":["syslog","remoteshell"]}'
    {
       "node2":[
          " Wed Apr  3 09:01:33 CST 2013 Running postscript: syslog",
          " Shutting down system logger: [  OK  ]",
          " Starting system logger: [  OK  ]",
          " Postscript: syslog exited with code 0",
          " Wed Apr  3 09:01:33 CST 2013 Running postscript: remoteshell",
          " Stopping sshd: [  OK  ]",
          " Starting sshd: [  OK  ]",
          " Postscript: remoteshell exited with code 0",
          " Running of postscripts has completed."
       ]
    }

[URI:/nodes/{noderange}/nodeshell] - The nodeshell resource for the node {noderange}
------------------------------------------------------------------------------------

POST - Run the command in the shell of the node {noderange}.
````````````````````````````````````````````````````````````

Refer to the man page: :doc:`xdsh </guides/admin-guides/references/man1/xdsh.1>`

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: set environment {ENV:{en1:v1,en2:v2}}, raw command {raw:[op1,op2]}, direct command {command:[cmd1,cmd2]}.

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...}' pairs.

**Example:** 

Run the 'date' command on the node2. :: 


    #curl -X POST -k 'https://127.0.0.1/xcatws/nodes/node2/nodeshell?userName=root&userPW=cluster&pretty=1' -H Content-Type:application/json --data '{"command":["date","ls"]}'
    {
       "node2":[
          " Wed Apr  3 08:30:26 CST 2013",
          " testline1",
          " testline2"
       ]
    }

[URI:/nodes/{noderange}/nodecopy] - The nodecopy resource for the node {noderange}
----------------------------------------------------------------------------------

POST - Copy files to the node {noderange}.
``````````````````````````````````````````

Refer to the man page: :doc:`xdcp </guides/admin-guides/references/man1/xdcp.1>`

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: {src:[file1,file2],target:dir}.

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Copy files /tmp/f1 and /tmp/f2 from xCAT MN to the node2:/tmp. :: 


    #curl -X POST -k 'https://127.0.0.1/xcatws/nodes/node2/nodecopy?userName=root&userPW=cluster&pretty=1' -H Content-Type:application/json --data '{"src":["/tmp/f1","/tmp/f2"],"target":"/tmp"}'
    no output for succeeded copy.

[URI:/nodes/{noderange}/vm] - The virtualization node {noderange}.
------------------------------------------------------------------

The node should be a virtual machine of type kvm, esxi ...

PUT - Change the configuration for the virtual machine {noderange}.
```````````````````````````````````````````````````````````````````

Refer to the man page: :doc:`chvm </guides/admin-guides/references/man1/chvm.1>`

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: 
    Set memory size - {"memorysize":"sizeofmemory(MB)"}
    Add new disk - {"adddisk":"sizeofdisk1(GB),sizeofdisk2(GB)"}
    Purge disk - {"purgedisk":"scsi_id1,scsi_id2"}

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example1:** 

Set memory to 3000MB. :: 

    #curl -X PUT -k 'https://127.0.0.1/xcatws/nodes/node1/vm?userName=root&userPW=cluster&pretty=1' -H Content-Type:application/json --data '{"memorysize":"3000"}'

**Example2:** 

Add a new 20G disk. :: 

    #curl -X PUT -k 'https://127.0.0.1/xcatws/nodes/node1/vm?userName=root&userPW=cluster&pretty=1' -H Content-Type:application/json --data '{"adddisk":"20G"}'

**Example3:** 

Purge the disk 'hdb'. :: 

    #curl -X PUT -k 'https://127.0.0.1/xcatws/nodes/node1/vm?userName=root&userPW=cluster&pretty=1' -H Content-Type:application/json --data '{"purgedisk":"hdb"}'

POST - Create the vm node {noderange}.
``````````````````````````````````````

Refer to the man page: :doc:`mkvm </guides/admin-guides/references/man1/mkvm.1>`

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: 
    Set CPU count - {"cpucount":"numberofcpu"}
    Set memory size - {"memorysize":"sizeofmemory(MB)"}
    Set disk size - {"disksize":"sizeofdisk"}
    Do it by force - {"force":"yes"}

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Create the vm node1 with a 30G disk, 2048M memory and 2 cpus. :: 

    #curl -X POST -k 'https://127.0.0.1/xcatws/nodes/node1/vm?userName=root&userPW=cluster&pretty=1' -H Content-Type:application/json --data '{"disksize":"30G","memorysize":"2048","cpucount":"2"}'

DELETE - Remove the vm node {noderange}.
````````````````````````````````````````

Refer to the man page: :doc:`rmvm </guides/admin-guides/references/man1/rmvm.1>`

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: 
    Purge disk - {"purge":"yes"}
    Do it by force - {"force":"yes"}

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Remove the vm node1 by force and purge the disk. :: 

    #curl -X DELETE -k 'https://127.0.0.1/xcatws/nodes/node1/vm?userName=root&userPW=cluster&pretty=1' -H Content-Type:application/json --data '{"force":"yes","purge":"yes"}'

[URI:/nodes/{noderange}/vmclone] - The clone resource for the virtual node {noderange}.
---------------------------------------------------------------------------------------

The node should be a virtual machine of kvm, esxi ...

POST - Create a clone master from node {noderange}. Or clone the node {noderange} from a clone master.
``````````````````````````````````````````````````````````````````````````````````````````````````````

Refer to the man page: :doc:`clonevm </guides/admin-guides/references/man1/clonevm.1>`

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: 
    Clone a master named "mastername" - {"tomaster":"mastername"}
    Clone a node from master "mastername" - {"frommaster":"mastername"}
    Use Detach mode - {"detach":"yes"}
    Do it by force - {"force":"yes"}

**Returns:**

* The messages of creating Clone target.

**Example1:** 

Create a clone master named "vmmaster" from the node1. :: 


    #curl -X POST -k 'https://127.0.0.1/xcatws/nodes/node1/vmclone?userName=root&userPW=cluster&pretty=1' -H Content-Type:application/json --data '{"tomaster":"vmmaster","detach":"yes"}'
    {
       "node1":{
          "vmclone":"Cloning of node1.hda.qcow2 complete (clone uses 9633.19921875 for a disk size of 30720MB)"
       }
    }

**Example2:** 

Clone the node1 from the clone master named "vmmaster". :: 

    #curl -X POST -k 'https://127.0.0.1/xcatws/nodes/node1/vmclone?userName=root&userPW=cluster&pretty=1' -H Content-Type:application/json --data '{"frommaster":"vmmaster"}'

[URI:/nodes/{noderange}/vmmigrate] - The virtualization resource for migration.
-------------------------------------------------------------------------------

The node should be a virtual machine of kvm, esxi ...

POST - Migrate a node to targe node.
````````````````````````````````````

Refer to the man page: :doc:`rmigrate </guides/admin-guides/references/man1/rmigrate.1>`

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: {"target":"targethost"}.

**Example:** 

Migrate node1 to target host host2. :: 

    #curl -X POST -k 'https://127.0.0.1/xcatws/nodes/node1/vmmigrate?userName=root&userPW=cluster&pretty=1' -H Content-Type:application/json --data '{"target":"host2"}'

Osimage resources
=================

URI list which can be used to query, create osimage resources.

[URI:/osimages] - The osimage resource.
---------------------------------------

GET - Get all the osimage in xCAT.
``````````````````````````````````

Refer to the man page: :doc:`lsdef </guides/admin-guides/references/man1/lsdef.1>`

**Returns:**

* Json format: An array of osimage names.

**Example:** 

Get all the osimage names. :: 


    #curl -X GET -k 'https://127.0.0.1/xcatws/osimages?userName=root&userPW=cluster&pretty=1'
    [
       "sles11.2-x86_64-install-compute",
       "sles11.2-x86_64-install-iscsi",
       "sles11.2-x86_64-install-iscsiibft",
       "sles11.2-x86_64-install-service"
    ]

POST - Create the osimage resources base on the parameters specified in the Data body.
``````````````````````````````````````````````````````````````````````````````````````

Refer to the man page: :doc:`copycds </guides/admin-guides/references/man8/copycds.8>`

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: {iso:isoname\file:filename,params:[{attr1:value1,attr2:value2}]}

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example1:** 

Create osimage resources based on the ISO specified :: 

    #curl -X POST -k 'https://127.0.0.1/xcatws/osimages?userName=root&userPW=cluster&pretty=1' -H Content-Type:application/json --data '{"iso":"/iso/RHEL6.4-20130130.0-Server-ppc64-DVD1.iso"}'

**Example2:** 

Create osimage resources based on an xCAT image or configuration file :: 

    #curl -X POST -k 'https://127.0.0.1/xcatws/osimages?userName=root&userPW=cluster&pretty=1' -H Content-Type:application/json --data '{"file":"/tmp/sles11.2-x86_64-install-compute.tgz"}'

[URI:/osimages/{imgname}] - The osimage resource
------------------------------------------------

GET - Get all the attibutes for the osimage {imgname}.
``````````````````````````````````````````````````````

The keyword ALLRESOURCES can be used as {imgname} which means to get image attributes for all the osimages.

Refer to the man page: :doc:`lsdef </guides/admin-guides/references/man1/lsdef.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...}' pairs.

**Example:** 

Get the attributes for the specified osimage. :: 


    #curl -X GET -k 'https://127.0.0.1/xcatws/osimages/sles11.2-x86_64-install-compute?userName=root&userPW=cluster&pretty=1'
    {
       "sles11.2-x86_64-install-compute":{
          "provmethod":"install",
          "profile":"compute",
          "template":"/opt/xcat/share/xcat/install/sles/compute.sles11.tmpl",
          "pkglist":"/opt/xcat/share/xcat/install/sles/compute.sles11.pkglist",
          "osvers":"sles11.2",
          "osarch":"x86_64",
          "osname":"Linux",
          "imagetype":"linux",
          "otherpkgdir":"/install/post/otherpkgs/sles11.2/x86_64",
          "osdistroname":"sles11.2-x86_64",
          "pkgdir":"/install/sles11.2/x86_64"
       }
    }

PUT - Change the attibutes for the osimage {imgname}.
`````````````````````````````````````````````````````

Refer to the man page: :doc:`chdef </guides/admin-guides/references/man1/chdef.1>`

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: {attr1:v1,attr2:v2...}

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Change the 'osvers' and 'osarch' attributes for the osiamge. :: 

    #curl -X PUT -k 'https://127.0.0.1/xcatws/osimages/sles11.2-ppc64-install-compute/?userName=root&userPW=cluster&pretty=1' -H Content-Type:application/json --data '{"osvers":"sles11.3","osarch":"x86_64"}'

POST - Create the osimage {imgname}.
````````````````````````````````````

Refer to the man page: :doc:`mkdef </guides/admin-guides/references/man1/mkdef.1>`

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: {attr1:v1,attr2:v2]

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Create a osimage obj with the specified parameters. :: 

    #curl -X POST -k 'https://127.0.0.1/xcatws/osimages/sles11.3-ppc64-install-compute?userName=root&userPW=cluster&pretty=1' -H Content-Type:application/json --data '{"osvers":"sles11.3","osarch":"ppc64","osname":"Linux","provmethod":"install","profile":"compute"}'

DELETE - Remove the osimage {imgname}.
``````````````````````````````````````

Refer to the man page: :doc:`rmdef </guides/admin-guides/references/man1/rmdef.1>`

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Delete the specified osimage. :: 

    #curl -X DELETE -k 'https://127.0.0.1/xcatws/osimages/sles11.3-ppc64-install-compute?userName=root&userPW=cluster&pretty=1'

[URI:/osimages/{imgname}/attrs/attr1,attr2,attr3 ...] - The attributes resource for the osimage {imgname}
---------------------------------------------------------------------------------------------------------

GET - Get the specific attributes for the osimage {imgname}.
````````````````````````````````````````````````````````````

The keyword ALLRESOURCES can be used as {imgname} which means to get image attributes for all the osimages.

Refer to the man page: :doc:`lsdef </guides/admin-guides/references/man1/lsdef.1>`

**Returns:**

* Json format: An array of attr:value pairs for the specified osimage.

**Example:** 

Get the specified attributes. :: 

    #curl -X GET -k 'https://127.0.0.1/xcatws/osimages/sles11.2-ppc64-install-compute/attrs/imagetype,osarch,osname,provmethod?userName=root&userPW=cluster&pretty=1'
    {
       "sles11.2-ppc64-install-compute":{
          "provmethod":"install",
          "osname":"Linux",
          "osarch":"ppc64",
          "imagetype":"linux"
       }
    }

[URI:/osimages/{imgname}/instance] - The instance for the osimage {imgname}
---------------------------------------------------------------------------

POST - Operate the instance of the osimage {imgname}.
`````````````````````````````````````````````````````

Refer to the man page: :doc:` </guides/admin-guides/references/>`

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: {action:gen\pack\export,params:[{attr1:value1,attr2:value2...}]}

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example1:** 

Generates a stateless image based on the specified osimage :: 

    #curl -X POST -k 'https://127.0.0.1/xcatws/osimages/sles11.2-x86_64-install-compute/instance?userName=root&userPW=cluster&pretty=1' -H Content-Type:application/json --data '{"action":"gen"}'

**Example2:** 

Packs the stateless image from the chroot file system based on the specified osimage :: 

    #curl -X POST -k 'https://127.0.0.1/xcatws/osimages/sles11.2-x86_64-install-compute/instance?userName=root&userPW=cluster&pretty=1' -H Content-Type:application/json --data '{"action":"pack"}'

**Example3:** 

Exports an xCAT image based on the specified osimage :: 

    #curl -X POST -k 'https://127.0.0.1/xcatws/osimages/sles11.2-x86_64-install-compute/instance?userName=root&userPW=cluster&pretty=1' -H Content-Type:application/json --data '{"action":"export"}'

DELETE - Delete the stateless or statelite image instance for the osimage {imgname} from the file system
````````````````````````````````````````````````````````````````````````````````````````````````````````

Refer to the man page: :doc:`rmimage </guides/admin-guides/references/man1/rmimage.1>`

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Delete the stateless image for the specified osimage :: 

    #curl -X DELETE -k 'https://127.0.0.1/xcatws/osimages/sles11.2-x86_64-install-compute/instance?userName=root&userPW=cluster&pretty=1'

Network Resources
=================

The URI list which can be used to create, query, change and manage network objects.

[URI:/networks] - The network list resource.
--------------------------------------------

This resource can be used to display all the networks which have been defined in the xCAT database.

GET - Get all the networks in xCAT.
```````````````````````````````````

The attributes details for the networks will not be displayed.

Refer to the man page: :doc:`lsdef </guides/admin-guides/references/man1/lsdef.1>`

**Returns:**

* Json format: An array of networks names.

**Example:** 

Get all the networks names from xCAT database. :: 


    #curl -X GET -k 'https://127.0.0.1/xcatws/networks?userName=root&userPW=cluster&pretty=1'
    [
       "network1",
       "network2",
       "network3",
    ]

POST - Create the networks resources base on the network configuration on xCAT MN.
``````````````````````````````````````````````````````````````````````````````````

Refer to the man page: :doc:`makenetworks </guides/admin-guides/references/man8/makenetworks.8>`

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: {attr1:v1,att2:v2,...}.

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Create the networks resources base on the network configuration on xCAT MN. :: 

    #curl -X POST -k 'https://127.0.0.1/xcatws/networks?userName=root&userPW=cluster&pretty=1'

[URI:/networks/{netname}] - The network resource
------------------------------------------------

GET - Get all the attibutes for the network {netname}.
``````````````````````````````````````````````````````

The keyword ALLRESOURCES can be used as {netname} which means to get network attributes for all the networks.

Refer to the man page: :doc:`lsdef </guides/admin-guides/references/man1/lsdef.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...}' pairs.

**Example:** 

Get all the attibutes for network 'network1'. :: 

    #curl -X GET -k 'https://127.0.0.1/xcatws/networks/network1?userName=root&userPW=cluster&pretty=1'
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

PUT - Change the attibutes for the network {netname}.
`````````````````````````````````````````````````````

Refer to the man page: :doc:`chdef </guides/admin-guides/references/man1/chdef.1>`

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: {attr1:v1,att2:v2,...}.

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Change the attributes mgtifname=eth0 and net=10.1.0.0. :: 

    #curl -X PUT -k 'https://127.0.0.1/xcatws/networks/network1?userName=root&userPW=cluster&pretty=1' -H Content-Type:application/json --data '{"mgtifname":"eth0","net":"10.1.0.0"}'

POST - Create the network {netname}. DataBody: {attr1:v1,att2:v2...}.
`````````````````````````````````````````````````````````````````````

Refer to the man page: :doc:`mkdef </guides/admin-guides/references/man1/mkdef.1>`

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: {attr1:v1,att2:v2,...}.

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Create a network with attributes gateway=10.1.0.1, mask=255.255.0.0  :: 

    #curl -X POST -k 'https://127.0.0.1/xcatws/networks/network1?userName=root&userPW=cluster&pretty=1' -H Content-Type:application/json --data '{"gateway":"10.1.0.1","mask":"255.255.0.0"}'

DELETE - Remove the network {netname}.
``````````````````````````````````````

Refer to the man page: :doc:`rmdef </guides/admin-guides/references/man1/rmdef.1>`

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Delete the network network1 :: 

    #curl -X DELETE -k 'https://127.0.0.1/xcatws/networks/network1?userName=root&userPW=cluster&pretty=1'

[URI:/networks/{netname}/attrs/attr1,attr2,...] - The attributes resource for the network {netname}
---------------------------------------------------------------------------------------------------

GET - Get the specific attributes for the network {netname}.
````````````````````````````````````````````````````````````

The keyword ALLRESOURCES can be used as {netname} which means to get network attributes for all the networks.

Refer to the man page: :doc:`lsdef </guides/admin-guides/references/man1/lsdef.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...}' pairs.

**Example:** 

Get the attributes {groups,mgt,netboot} for network network1 :: 

    #curl -X GET -k 'https://127.0.0.1/xcatws/networks/network1/attrs/gateway,mask,mgtifname,net,tftpserver?userName=root&userPW=cluster&pretty=1'
    {
       "network1":{
          "gateway":"9.114.34.254",
          "mask":"255.255.255.0",
             }
    }

Policy Resources
================

The URI list which can be used to create, query, change and manage policy entries.

[URI:/policy] - The policy resource.
------------------------------------

GET - Get all the policies in xCAT.
```````````````````````````````````

It will dislplay all the policy resource.

Refer to the man page: :doc:`lsdef </guides/admin-guides/references/man1/lsdef.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...}' pairs.

**Example:** 

Get all the policy objects. :: 

    #curl -X GET -k 'https://127.0.0.1/xcatws/policy?userName=root&userPW=cluster&pretty=1'
    [
       "1",
       "1.2",
       "2",
       "4.8"
    ]

[URI:/policy/{policy_priority}] - The policy resource
-----------------------------------------------------

GET - Get all the attibutes for a policy {policy_priority}.
```````````````````````````````````````````````````````````

It will display all the policy attributes for one policy resource.

The keyword ALLRESOURCES can be used as {policy_priority} which means to get policy attributes for all the policies.

Refer to the man page: :doc:`lsdef </guides/admin-guides/references/man1/lsdef.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...}' pairs.

**Example:** 

Get all the attribute for policy 1. :: 

    #curl -X GET -k 'https://127.0.0.1/xcatws/policy/1?userName=root&userPW=cluster&pretty=1'
    {
       "1":{
          "name":"root",
          "rule":"allow"
       }
    }

PUT - Change the attibutes for the policy {policy_priority}.
````````````````````````````````````````````````````````````

It will change one or more attributes for a policy.

Refer to the man page: :doc:`chdef </guides/admin-guides/references/man1/chdef.1>`

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: {attr1:v1,att2:v2,...}.

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Set the name attribute for policy 3. :: 


    #curl -X PUT -k 'https://127.0.0.1/xcatws/policy/3?userName=root&userPW=cluster&pretty=1' -H Content-Type:application/json --data '{"name":"root"}'

POST - Create the policy {policyname}. DataBody: {attr1:v1,att2:v2...}.
```````````````````````````````````````````````````````````````````````

It will creat a new policy resource.

Refer to the man page: :doc:`chdef </guides/admin-guides/references/man1/chdef.1>`

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: {attr1:v1,att2:v2,...}.

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Create a new policy 10. :: 

    #curl -X POST -k 'https://127.0.0.1/xcatws/policy/10?userName=root&userPW=cluster&pretty=1' -H Content-Type:application/json --data '{"name":"root","commands":"rpower"}'

DELETE - Remove the policy {policy_priority}.
`````````````````````````````````````````````

Remove one or more policy resource.

Refer to the man page: :doc:`rmdef </guides/admin-guides/references/man1/rmdef.1>`

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Delete the policy 10. :: 

    #curl -X DELETE -k 'https://127.0.0.1/xcatws/policy/10?userName=root&userPW=cluster&pretty=1'

[URI:/policy/{policyname}/attrs/{attr1,attr2,attr3,...}] - The attributes resource for the policy {policy_priority}
-------------------------------------------------------------------------------------------------------------------

GET - Get the specific attributes for the policy {policy_priority}.
```````````````````````````````````````````````````````````````````

It will get one or more attributes of a policy.

The keyword ALLRESOURCES can be used as {policy_priority} which means to get policy attributes for all the policies.

Refer to the man page: :doc:`lsdef </guides/admin-guides/references/man1/lsdef.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...}' pairs.

**Example:** 

Get the name and rule attributes for policy 1. :: 

    #curl -X GET -k 'https://127.0.0.1/xcatws/policy/1/attrs/name,rule?userName=root&userPW=cluster&pretty=1'
    {
       "1":{
          "name":"root",
          "rule":"allow"
       }
    }

Group Resources
===============

The URI list which can be used to create, query, change and manage group objects.

[URI:/groups] - The group list resource.
----------------------------------------

This resource can be used to display all the groups which have been defined in the xCAT database.

GET - Get all the groups in xCAT.
`````````````````````````````````

The attributes details for the group will not be displayed.

Refer to the man page: :doc:`lsdef </guides/admin-guides/references/man1/lsdef.1>`

**Returns:**

* Json format: An array of group names.

**Example:** 

Get all the group names from xCAT database. :: 

    #curl -X GET -k 'https://127.0.0.1/xcatws/groups?userName=root&userPW=cluster&pretty=1'
    [
       "__mgmtnode",
       "all",
       "compute",
       "ipmi",
       "kvm",
    ]

[URI:/groups/{groupname}] - The group resource
----------------------------------------------

GET - Get all the attibutes for the group {groupname}.
``````````````````````````````````````````````````````

Refer to the man page: :doc:`lsdef </guides/admin-guides/references/man1/lsdef.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...}' pairs.

**Example:** 

Get all the attibutes for group 'all'. :: 

    #curl -X GET -k 'https://127.0.0.1/xcatws/groups/all?userName=root&userPW=cluster&pretty=1'
    {
       "all":{
          "members":"zxnode2,nodexxx,node1,node4"
       }
    }

PUT - Change the attibutes for the group {groupname}.
`````````````````````````````````````````````````````

Refer to the man page: :doc:`chdef </guides/admin-guides/references/man1/chdef.1>`

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: {attr1:v1,att2:v2,...}.

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Change the attributes mgt=dfm and netboot=yaboot. :: 


    #curl -X PUT -k 'https://127.0.0.1/xcatws/groups/all?userName=root&userPW=cluster&pretty=1' -H Content-Type:application/json --data '{"mgt":"dfm","netboot":"yaboot"}'

[URI:/groups/{groupname}/attrs/{attr1,attr2,attr3 ...}] - The attributes resource for the group {groupname}
-----------------------------------------------------------------------------------------------------------

GET - Get the specific attributes for the group {groupname}.
````````````````````````````````````````````````````````````

Refer to the man page: :doc:`lsdef </guides/admin-guides/references/man1/lsdef.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...}' pairs.

**Example:** 

Get the attributes {mgt,netboot} for group all :: 


    #curl -X GET -k 'https://127.0.0.1/xcatws/groups/all/attrs/mgt,netboot?userName=root&userPW=cluster&pretty=1'
    {
       "all":{
          "netboot":"yaboot",
          "mgt":"dfm"
       }
    }

Global Configuration Resources
==============================

The URI list which can be used to create, query, change global configuration.

[URI:/globalconf] - The global configuration resource.
------------------------------------------------------

This resource can be used to display all the global configuration which have been defined in the xCAT database.

GET - Get all the xCAT global configuration.
````````````````````````````````````````````

It will display all the global attributes.

Refer to the man page: :doc:`lsdef </guides/admin-guides/references/man1/lsdef.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...}' pairs.

**Example:** 

Get all the global configuration :: 


    #curl -X GET -k 'https://127.0.0.1/xcatws/globalconf?userName=root&userPW=cluster&pretty=1'
    {
       "clustersite":{
          "xcatconfdir":"/etc/xcat",
          "tftpdir":"/tftpboot",
          ...
       }
    }

[URI:/globalconf/attrs/{attr1,attr2 ...}] - The specific global configuration resource.
---------------------------------------------------------------------------------------

GET - Get the specific configuration in global.
```````````````````````````````````````````````

It will display one or more global attributes.

Refer to the man page: :doc:`lsdef </guides/admin-guides/references/man1/lsdef.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...}' pairs.

**Example:** 

Get the 'master' and 'domain' configuration. :: 

    #curl -X GET -k 'https://127.0.0.1/xcatws/globalconf/attrs/master,domain?userName=root&userPW=cluster&pretty=1'
    {
       "clustersite":{
          "domain":"cluster.com",
          "master":"192.168.1.15"
       }
    }

PUT - Change the global attributes.
```````````````````````````````````

It can be used for changing/adding global attributes.

Refer to the man page: :doc:`chdef </guides/admin-guides/references/man1/chdef.1>`

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: {attr1:v1,att2:v2,...}.

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Change/Add the domain attribute. :: 

    #curl -X PUT -k 'https://127.0.0.1/xcatws/globalconf/attrs/domain?userName=root&userPW=cluster&pretty=1' -H Content-Type:application/json --data '{"domain":"cluster.com"}'

DELETE - Remove the site attributes.
````````````````````````````````````

Used for femove one or more global attributes.

Refer to the man page: :doc:`chdef </guides/admin-guides/references/man1/chdef.1>`

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Remove the domain configure. :: 

    #curl -X DELETE -k 'https://127.0.0.1/xcatws/globalconf/attrs/domain?userName=root&userPW=cluster&pretty=1'

Service Resources
=================

The URI list which can be used to manage the host, dns and dhcp services on xCAT MN.

[URI:/services/dns] - The dns service resource.
-----------------------------------------------

POST - Initialize the dns service.
``````````````````````````````````

Refer to the man page: :doc:`makedns </guides/admin-guides/references/man8/makedns.8>`

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Initialize the dns service. :: 

    #curl -X POST -k 'https://127.0.0.1/xcatws/services/dns?userName=root&userPW=cluster&pretty=1'

[URI:/services/dhcp] - The dhcp service resource.
-------------------------------------------------

POST - Create the dhcpd.conf for all the networks which are defined in the xCAT Management Node.
````````````````````````````````````````````````````````````````````````````````````````````````

Refer to the man page: :doc:`makedhcp </guides/admin-guides/references/man8/makedhcp.8>`

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Create the dhcpd.conf and restart the dhcpd. :: 

    #curl -X POST -k 'https://127.0.0.1/xcatws/services/dhcp?userName=root&userPW=cluster&pretty=1'

[URI:/services/host] - The hostname resource.
---------------------------------------------

POST - Create the ip/hostname records for all the nodes to /etc/hosts.
``````````````````````````````````````````````````````````````````````

Refer to the man page: :doc:`makehosts </guides/admin-guides/references/man8/makehosts.8>`

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Create the ip/hostname records for all the nodes to /etc/hosts. :: 

    #curl -X POST -k 'https://127.0.0.1/xcatws/services/host?userName=root&userPW=cluster&pretty=1'

[URI:/services/slpnodes] - The nodes which support SLP in the xCAT cluster
--------------------------------------------------------------------------

GET - Get all the nodes which support slp protocol in the network.
``````````````````````````````````````````````````````````````````

Refer to the man page: :doc:`lsslp </guides/admin-guides/references/man1/lsslp.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...}' pairs.

**Example:** 

Get all the nodes which support slp in the network. :: 

    #curl -X GET -k 'https://127.0.0.1/xcatws/services/slpnodes?userName=root&userPW=cluster&pretty=1'
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

[URI:/services/slpnodes/{CEC|FRAME|MM|IVM|RSA|HMC|CMM|IMM2|FSP...}] - The slp nodes with specific service type in the xCAT cluster
----------------------------------------------------------------------------------------------------------------------------------

GET - Get all the nodes with specific slp service type in the network.
``````````````````````````````````````````````````````````````````````

Refer to the man page: :doc:`lsslp </guides/admin-guides/references/man1/lsslp.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...}' pairs.

**Example:** 

Get all the CMM nodes which support slp in the network. :: 


    #curl -X GET -k 'https://127.0.0.1/xcatws/services/slpnodes/CMM?userName=root&userPW=cluster&pretty=1'
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

Table Resources
===============

URI list which can be used to create, query, change table entries.

[URI:/tables/{tablelist}/nodes/{noderange}] - The node table resource
---------------------------------------------------------------------

For a large number of nodes, this API call can be faster than using the corresponding nodes resource.  The disadvantage is that you need to know the table names the attributes are stored in.

GET - Get attibutes of tables for a noderange.
``````````````````````````````````````````````

**Returns:**

* An object containing each table.  Within each table object is an array of node objects containing the attributes.

**Example1:** 

Get all the columns from table nodetype for node1 and node2. :: 


    #curl -X GET -k 'https://127.0.0.1/xcatws/tables/nodetype/nodes/node1,node2?userName=root&userPW=cluster&pretty=1'
    {
       "nodetype":[
          {
             "provmethod":"rhels6.4-x86_64-install-compute",
             "profile":"compute",
             "arch":"x86_64",
             "name":"node1",
             "os":"rhels6.4"
          },
          {
             "provmethod":"rhels6.3-x86_64-install-compute",
             "profile":"compute",
             "arch":"x86_64",
             "name":"node2",
             "os":"rhels6.3"
          }
       ]
    }

**Example2:** 

Get all the columns from tables nodetype and noderes for node1 and node2. :: 


    #curl -X GET -k 'https://127.0.0.1/xcatws/tables/nodetype,noderes/nodes/node1,node2?userName=root&userPW=cluster&pretty=1'
    {
       "noderes":[
          {
             "installnic":"mac",
             "netboot":"xnba",
             "name":"node1",
             "nfsserver":"192.168.1.15"
          },
          {
             "installnic":"mac",
             "netboot":"pxe",
             "name":"node2",
             "proxydhcp":"no"
          }
       ],
       "nodetype":[
          {
             "provmethod":"rhels6.4-x86_64-install-compute",
             "profile":"compute",
             "arch":"x86_64",
             "name":"node1",
             "os":"rhels6.4"
          },
          {
             "provmethod":"rhels6.3-x86_64-install-compute",
             "profile":"compute",
             "arch":"x86_64",
             "name":"node2",
             "os":"rhels6.3"
          }
       ]
    }

PUT - Change the node table attibutes for {noderange}.
``````````````````````````````````````````````````````

**Parameters:**

* A hash of table names and attribute objects.  DataBody: {table1:{attr1:v1,att2:v2,...}}.

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Change the nodetype.arch and noderes.netboot attributes for nodes node1,node2. :: 

    #curl -X PUT -k 'https://127.0.0.1/xcatws/tables/nodetype,noderes/nodes/node1,node2?userName=root&userPW=cluster&pretty=1' -H Content-Type:application/json --data '{"nodetype":{"arch":"x86_64"},"noderes":{"netboot":"xnba"}}'

[URI:/tables/{tablelist}/nodes/nodes/{noderange}/{attrlist}] - The node table attributes resource
-------------------------------------------------------------------------------------------------

For a large number of nodes, this API call can be faster than using the corresponding nodes resource.  The disadvantage is that you need to know the table names the attributes are stored in.

GET - Get table attibutes for a noderange.
``````````````````````````````````````````

**Returns:**

* An object containing each table.  Within each table object is an array of node objects containing the attributes.

**Example:** 

Get OS and ARCH attributes from nodetype table for node1 and node2. :: 


    #curl -X GET -k 'https://127.0.0.1/xcatws/tables/nodetype/nodes/node1,node2/os,arch?userName=root&userPW=cluster&pretty=1'
    {
       "nodetype":[
          {
             "arch":"x86_64",
             "name":"node1",
             "os":"rhels6.4"
          },
          {
             "arch":"x86_64",
             "name":"node2",
             "os":"rhels6.3"
          }
       ]
    }

[URI:/tables/{tablelist}/rows] - The non-node table resource
------------------------------------------------------------

Use this for tables that don't have node name as the key of the table, for example: passwd, site, networks, polciy, etc.

GET - Get all rows from non-node tables.
````````````````````````````````````````

**Returns:**

* An object containing each table.  Within each table object is an array of row objects containing the attributes.

**Example:** 

Get all rows from networks table. :: 


    #curl -X GET -k 'https://127.0.0.1/xcatws/tables/networks/rows?userName=root&userPW=cluster&pretty=1'
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

[URI:/tables/{tablelist}/rows/{keys}] - The non-node table rows resource
------------------------------------------------------------------------

Use this for tables that don't have node name as the key of the table, for example: passwd, site, networks, polciy, etc.

{keys} should be the name=value pairs which are used to search table. e.g. {keys} should be [net=192.168.1.0,mask=255.255.255.0] for networks table query since the net and mask are the keys of networks table.

GET - Get attibutes for rows from non-node tables.
``````````````````````````````````````````````````

**Returns:**

* An object containing each table.  Within each table object is an array of row objects containing the attributes.

**Example:** 

Get row which net=192.168.1.0,mask=255.255.255.0 from networks table. :: 


    #curl -X GET -k 'https://127.0.0.1/xcatws/tables/networks/rows/net=192.168.1.0,mask=255.255.255.0?userName=root&userPW=cluster&pretty=1'
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

PUT - Change the non-node table attibutes for the row that matches the {keys}.
``````````````````````````````````````````````````````````````````````````````

**Parameters:**

* A hash of attribute names and values.  DataBody: {attr1:v1,att2:v2,...}.

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Create a route row in the routes table. :: 

    #curl -X PUT -k 'https://127.0.0.1/xcatws/tables/routes/rows/routename=privnet?userName=root&userPW=cluster&pretty=1' -H Content-Type:application/json --data '{"net":"10.0.1.0","mask":"255.255.255.0","gateway":"10.0.1.254","ifname":"eth1"}'

DELETE - Delete rows from a non-node table that have the attribute values specified in {keys}.
``````````````````````````````````````````````````````````````````````````````````````````````

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Delete a route row which routename=privnet in the routes table. :: 

    #curl -X DELETE -k 'https://127.0.0.1/xcatws/tables/routes/rows/routename=privnet?userName=root&userPW=cluster&pretty=1'

[URI:/tables/{tablelist}/rows/{keys}/{attrlist}] - The non-node table attributes resource
-----------------------------------------------------------------------------------------

Use this for tables that don't have node name as the key of the table, for example: passwd, site, networks, polciy, etc.

GET - Get specific attibutes for rows from non-node tables.
```````````````````````````````````````````````````````````

**Returns:**

* An object containing each table.  Within each table object is an array of row objects containing the attributes.

**Example:** 

Get attributes mgtifname and tftpserver which net=192.168.1.0,mask=255.255.255.0 from networks table. :: 


    #curl -X GET -k 'https://127.0.0.1/xcatws/tables/networks/rows/net=192.168.1.0,mask=255.255.255.0/mgtifname,tftpserver?userName=root&userPW=cluster&pretty=1'
    {
       "networks":[
          {
             "mgtifname":"eth0",
             "tftpserver":"192.168.1.15"
          }
       ]
    }

