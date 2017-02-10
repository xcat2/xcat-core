/osimages/{imgname}
===================

The osimage resource

GET - Get all the attibutes for the osimage {imgname}
-----------------------------------------------------

The keyword ALLRESOURCES can be used as {imgname} which means to get image attributes for all the osimages.

Refer to the man page: :doc:`lsdef </guides/admin-guides/references/man1/lsdef.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...}' pairs.

**Example:** 

Get the attributes for the specified osimage. :: 

    curl -X GET -k 'https://127.0.0.1/xcatws/osimages/sles11.2-x86_64-install-compute?userName=root&userPW=cluster&pretty=1'
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


PUT - Change the attibutes for the osimage {imgname}
----------------------------------------------------

Refer to the man page: :doc:`chdef </guides/admin-guides/references/man1/chdef.1>`

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: {attr1:v1,attr2:v2...}

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Change the 'osvers' and 'osarch' attributes for the osiamge. :: 

    curl -X PUT -k 'https://127.0.0.1/xcatws/osimages/sles11.2-ppc64-install-compute/?userName=root&userPW=cluster&pretty=1' \
       -H Content-Type:application/json --data '{"osvers":"sles11.3","osarch":"x86_64"}'

POST - Create the osimage {imgname}
-----------------------------------

Refer to the man page: :doc:`mkdef </guides/admin-guides/references/man1/mkdef.1>`

**Parameters:**

* Json format: An object which includes multiple 'att:value' pairs. DataBody: {attr1:v1,attr2:v2]

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Create a osimage obj with the specified parameters. :: 

    curl -X POST -k 'https://127.0.0.1/xcatws/osimages/sles11.3-ppc64-install-compute?userName=root&userPW=cluster&pretty=1' \
       -H Content-Type:application/json --data '{"osvers":"sles11.3","osarch":"ppc64","osname":"Linux","provmethod":"install","profile":"compute"}'

DELETE - Remove the osimage {imgname}
-------------------------------------

Refer to the man page: :doc:`rmdef </guides/admin-guides/references/man1/rmdef.1>`

**Returns:**

* No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}.

**Example:** 

Delete the specified osimage. :: 

    curl -X DELETE -k 'https://127.0.0.1/xcatws/osimages/sles11.3-ppc64-install-compute?userName=root&userPW=cluster&pretty=1'

