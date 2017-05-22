/osimages
=========

The osimage resource.

GET - Get all the osimage in xCAT
---------------------------------

Refer to the man page: :doc:`lsdef </guides/admin-guides/references/man1/lsdef.1>`

**Returns:**

* Json format: An array of osimage names.

**Example:** 

Get all the osimage names. :: 


    curl -X GET -k 'https://127.0.0.1/xcatws/osimages?userName=root&userPW=cluster&pretty=1'
    [
       "sles11.2-x86_64-install-compute",
       "sles11.2-x86_64-install-iscsi",
       "sles11.2-x86_64-install-iscsiibft",
       "sles11.2-x86_64-install-service"
    ]

POST - Create the osimage resources base on the parameters specified in the Data body
-------------------------------------------------------------------------------------

Refer to the man page: :doc:`copycds </guides/admin-guides/references/man8/copycds.8>`

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: {iso:isoname\file:filename,params:[{attr1:value1,attr2:value2}]}

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Examples::**

#. Create osimage resources based on the ISO specified :: 

    curl -X POST -k 'https://127.0.0.1/xcatws/osimages?userName=root&userPW=cluster&pretty=1' \
       -H Content-Type:application/json --data '{"iso":"/iso/RHEL6.4-20130130.0-Server-ppc64-DVD1.iso"}'

#. Create osimage resources based on an xCAT image or configuration file :: 

    curl -X POST -k 'https://127.0.0.1/xcatws/osimages?userName=root&userPW=cluster&pretty=1' \
       -H Content-Type:application/json --data '{"file":"/tmp/sles11.2-x86_64-install-compute.tgz"}'

