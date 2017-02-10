/nodes/{noderange}/vm
=====================

The virtualization node {noderange}.  The node specified should be a virtual machine. 

PUT - Change the configuration for the virtual machine {noderange}
------------------------------------------------------------------

Refer to the man page: :doc:`chvm </guides/admin-guides/references/man1/chvm.1>`

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: 
    Set memory size - {"memorysize":"sizeofmemory(MB)"}
    Add new disk - {"adddisk":"sizeofdisk1(GB),sizeofdisk2(GB)"}
    Purge disk - {"purgedisk":"scsi_id1,scsi_id2"}

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

#. Set memory to 3000MB. :: 

    curl -X PUT -k 'https://127.0.0.1/xcatws/nodes/node1/vm?userName=root&userPW=cluster&pretty=1' 
       -H Content-Type:application/json --data '{"memorysize":"3000"}'

#. Add a new 20G disk. ::

    curl -X PUT -k 'https://127.0.0.1/xcatws/nodes/node1/vm?userName=root&userPW=cluster&pretty=1' \
       -H Content-Type:application/json --data '{"adddisk":"20G"}'

#. Purge the disk 'hdb'. :: 

    curl -X PUT -k 'https://127.0.0.1/xcatws/nodes/node1/vm?userName=root&userPW=cluster&pretty=1' \
       -H Content-Type:application/json --data '{"purgedisk":"hdb"}'

POST - Create the vm node {noderange}
-------------------------------------

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

    curl -X POST -k 'https://127.0.0.1/xcatws/nodes/node1/vm?userName=root&userPW=cluster&pretty=1' \
       -H Content-Type:application/json --data '{"disksize":"30G","memorysize":"2048","cpucount":"2"}'

DELETE - Remove the vm node {noderange}
---------------------------------------

Refer to the man page: :doc:`rmvm </guides/admin-guides/references/man1/rmvm.1>`

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: 
    Purge disk - {"purge":"yes"}
    Do it by force - {"force":"yes"}

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Remove the vm node1 by force and purge the disk. :: 

    curl -X DELETE -k 'https://127.0.0.1/xcatws/nodes/node1/vm?userName=root&userPW=cluster&pretty=1' \
       -H Content-Type:application/json --data '{"force":"yes","purge":"yes"}'

