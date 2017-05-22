/globalconf
===========

This resource can be used to display all the global configuration which have been defined in the xCAT database.

GET - Get all the xCAT global configuration
-------------------------------------------

It will display all the global attributes.

Refer to the man page: :doc:`lsdef </guides/admin-guides/references/man1/lsdef.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...}' pairs.

**Example:** 

Get all the global configuration :: 


    curl -X GET -k 'https://127.0.0.1/xcatws/globalconf?userName=root&userPW=cluster&pretty=1'
    {
       "clustersite":{
          "xcatconfdir":"/etc/xcat",
          "tftpdir":"/tftpboot",
          ...
       }
    }


