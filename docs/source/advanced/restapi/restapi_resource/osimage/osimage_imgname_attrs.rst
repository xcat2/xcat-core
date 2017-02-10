/osimages/{imgname}/attrs/{attr1,attr2,attr3,...}
=================================================

The attributes resource for the osimage {imgname}

GET - Get the specific attributes for the osimage {imgname}
-----------------------------------------------------------

The keyword ALLRESOURCES can be used as {imgname} which means to get image attributes for all the osimages.  Refer to the man page: :doc:`lsdef </guides/admin-guides/references/man1/lsdef.1>`

**Returns:**

* Json format: An array of attr:value pairs for the specified osimage.

**Example:** 

Get the specified attributes. :: 

    curl -X GET -k 'https://127.0.0.1/xcatws/osimages/sles11.2-ppc64-install-compute/attrs/imagetype,osarch,osname,provmethod?userName=root&userPW=cluster&pretty=1'
    {
       "sles11.2-ppc64-install-compute":{
          "provmethod":"install",
          "osname":"Linux",
          "osarch":"ppc64",
          "imagetype":"linux"
       }
    }

