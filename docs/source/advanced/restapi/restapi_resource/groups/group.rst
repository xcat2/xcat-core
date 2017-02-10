/groups
=======

This resource can be used to display all the groups which have been defined in the xCAT database.

GET - Get all the groups in xCAT
--------------------------------

The attributes details for the group will not be displayed.

Refer to the man page: :doc:`lsdef </guides/admin-guides/references/man1/lsdef.1>`

**Returns:**

* Json format: An array of group names.

**Example:** 

Get all the group names from xCAT database. :: 

    curl -X GET -k 'https://127.0.0.1/xcatws/groups?userName=root&userPW=cluster&pretty=1'
    [
       "__mgmtnode",
       "all",
       "compute",
       "ipmi",
       "kvm",
    ]
