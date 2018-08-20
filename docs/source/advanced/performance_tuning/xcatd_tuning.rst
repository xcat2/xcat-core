Tuning xCAT Daemon Attributes
==================================

For large clusters, you consider changing the default settings in ``site`` table to improve the performance on a large-scale cluster or if you are experiencing timeouts or failures in these areas:

**consoleondemand** : When set to ``yes``, conserver connects and creates the console output for a node only when the user explicitly opens the console using rcons or wcons. Default is ``no`` on Linux, ``yes`` on AIX. Setting this to ``yes`` can reduce the load conserver places on your xCAT management node. If you need this set to ``no``, you may then need to consider setting up multiple servers to run the conserver daemon, and specify the correct server on a per-node basis by setting each node's conserver attribute.

**nodestatus** : If set to ``n``, the ``nodelist.status`` column will not be updated during the node deployment, node discovery and power operations. Default is ``y``, always update ``nodelist.status``. Setting this to ``n`` for large clusters can eliminate one node-to-server contact and one xCAT database write operation for each node during node deployment, but you will then need to determine deployment status through some other means.

**precreatemypostscripts** : (``yes/1`` or ``no/0``, only for Linux). Default is ``no``. If ``yes``, it will instruct xcat at ``nodeset`` and ``updatenode`` time to query the database once for all of the nodes passed into the command and create the ``mypostscript`` file for each node, and put them in a directory in ``site.tftpdir`` (such as: ``/tftpboot``). This prevents ``xcatd`` from having to create the ``mypostscript`` files one at a time when each deploying node contacts it, so it will speed up the deployment process. (But it also means that if you change database values for these nodes, you must rerun ``nodeset``.) If **precreatemypostscripts** is set to ``no``, the ``mypostscript`` files will not be generated ahead of time. Instead they will be generated when each node is deployed.

**svloglocal** : if set to ``1``, syslog on the service node will not get forwarded to the mgmt node. The default is to forward all syslog messages. The tradeoff on setting this attribute is reducing network traffic and log size versus having local management node access to all system messages from across the cluster.

**skiptables** : a comma separated list of tables to be skipped by ``dumpxCATdb``. A recommended setting is ``auditlog,eventlog`` because these tables can grow very large. Default is to skip no tables.

**dhcplease** : The lease time for the DHCP client. The default value is *43200*.

**xcatmaxconnections** : Number of concurrent xCAT protocol requests before requests begin queueing. This applies to both client command requests and node requests, e.g. to get postscripts. Default is ``64``.

**xcatmaxbatchconnections** : Number of concurrent xCAT connections allowed from the nodes. Number must be less than **xcatmaxconnections**.

**useflowcontrol** : If ``yes``, the postscript processing on each node contacts ``xcatd`` on the MN/SN using a lightweight UDP packet to wait until ``xcatd`` is ready to handle the requests associated with postscripts.  This prevents deploying nodes from flooding ``xcatd`` and locking out admin interactive use. This value works with the **xcatmaxconnections** and **xcatmaxbatch** attributes. If the value is ``no``, nodes sleep for a random time before contacting ``xcatd``, and retry. The default is ``no``. Not supported on AIX.


These attributes may be changed based on the size of your cluster. For a large cluster, it is better to enable **useflowcontrol** and set ``xcatmaxconnection = 356``, ``xcatmaxbatchconnections = 300``. Then the daemon will only allow 300 concurrent connections from the nodes. This will allow 56 connections still to be available on the management node for xCAT commands (e.g ``nodels``).
