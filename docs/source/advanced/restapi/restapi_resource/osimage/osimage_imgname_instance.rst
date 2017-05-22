/osimages/{imgname}/instance
============================

The instance for the osimage {imgname}

POST - Operate the instance of the osimage {imgname}
----------------------------------------------------

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: {action:gen\pack\export,params:[{attr1:value1,attr2:value2...}]}

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Examples:** 

#. Generates a stateless image based on the specified osimage :: 

    curl -X POST -k 'https://127.0.0.1/xcatws/osimages/sles11.2-x86_64-install-compute/instance?userName=root&userPW=cluster&pretty=1' \
       -H Content-Type:application/json --data '{"action":"gen"}'

#. Packs the stateless image from the chroot file system based on the specified osimage :: 

    curl -X POST -k 'https://127.0.0.1/xcatws/osimages/sles11.2-x86_64-install-compute/instance?userName=root&userPW=cluster&pretty=1' \
       -H Content-Type:application/json --data '{"action":"pack"}'

#. Exports an xCAT image based on the specified osimage :: 

    curl -X POST -k 'https://127.0.0.1/xcatws/osimages/sles11.2-x86_64-install-compute/instance?userName=root&userPW=cluster&pretty=1' \
       -H Content-Type:application/json --data '{"action":"export"}'

DELETE - Delete the stateless or statelite image instance for the osimage {imgname} from the file system
--------------------------------------------------------------------------------------------------------

Refer to the man page: :doc:`rmimage </guides/admin-guides/references/man1/rmimage.1>`

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Delete the stateless image for the specified osimage :: 

    curl -X DELETE -k 'https://127.0.0.1/xcatws/osimages/sles11.2-x86_64-install-compute/instance?userName=root&userPW=cluster&pretty=1'

