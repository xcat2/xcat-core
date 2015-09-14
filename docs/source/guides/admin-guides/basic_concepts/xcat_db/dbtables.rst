Key xCAT Tables
===============

They are many tables in xCAT databse to store various categories of information. This section only introduces several key xCAT tables which need to be initialized or viewed explicitly. For the complete reference on xCAT tables, please refer to the page <todo> or run ``tabdump -d <table name>``.

site
----
Global settings for the whole cluster. This table is different from the other tables in that each attribute is just named in the key column, rather than having a separate column for each attribute. Refer to the :doc:`Global Configuration </guides/admin-guides/basic_concepts/global_cfg/index>` page for the global attributes. 

policy
------
Controls who has authority to run specific xCAT operations. It is basically the Access Control List (ACL) for xCAT. It is sorted on the priority field before evaluating. Please run ``tabdump -d policy`` for details.

passwd
------
Contains default userids and passwords for xCAT to access cluster components. In most cases, xCAT will also actually set the userid/password in the relevant component when it is being configured or installed. Userids/passwords for specific cluster components can be overidden in other tables, e.g. ``mpa`` , ``ipmi`` , ``ppchcp`` , etc.

networks
--------
Describes the networks in the cluster and info necessary to set up nodes on that network.

auditlog
--------
Contains the audit log data.

eventlog
--------
Stores the events occurred.
