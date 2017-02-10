/nodes/{noderange}/vmclone
==========================

The clone resource for the virtual node {noderange}.  The node specified should be a virtual machine. 

POST - Create a clone master from node {noderange}, or clone the node {noderange} from a clone master
-----------------------------------------------------------------------------------------------------

Refer to the man page: :doc:`clonevm </guides/admin-guides/references/man1/clonevm.1>`

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: 
    Clone a master named "mastername" - {"tomaster":"mastername"}
    Clone a node from master "mastername" - {"frommaster":"mastername"}
    Use Detach mode - {"detach":"yes"}
    Do it by force - {"force":"yes"}

**Returns:**

* The messages of creating Clone target.

**Examples:** 

#. Create a clone master named "vmmaster" from the node1. :: 


    curl -X POST -k 'https://127.0.0.1/xcatws/nodes/node1/vmclone?userName=root&userPW=cluster&pretty=1' \
       -H Content-Type:application/json --data '{"tomaster":"vmmaster","detach":"yes"}'
    {
       "node1":{
          "vmclone":"Cloning of node1.hda.qcow2 complete (clone uses 9633.19921875 for a disk size of 30720MB)"
       }
    }

#. Clone the node1 from the clone master named "vmmaster". :: 

    curl -X POST -k 'https://127.0.0.1/xcatws/nodes/node1/vmclone?userName=root&userPW=cluster&pretty=1' \
       -H Content-Type:application/json --data '{"frommaster":"vmmaster"}'

