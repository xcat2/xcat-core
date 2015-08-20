Service Nodes 101
=================

Service Nodes are similar to the xCAT Management Node in that each service Nodes runs an instance of the xCAT daemon: ``xcatd``.  ``xcatd``'s communicate with each other using the same XML/SSL protocol that the xCAT client uses to communicate with ``xcatd`` on the Management Node. 

The Service Nodes need to communicate with the xCAT database running on the Management Node.  This is done using the remote client capabilities of the database.  This is why the default SQLite database cannot be used.

The xCAT Service Nodes are installed with a special xCAT package ``xCATsn`` which tells ``xcatd`` running on the node to behave as a Service Node and not the Management Node.

