Verify Service Node Installation
================================

* ssh to the service nodes. You should not be prompted for a password.
* Check to see that the xcat daemon xcatd is running.
* Run some database command on the service node, e.g tabdump site, or nodels,
  and see that the database can be accessed from the service node.
* Check that ``/install`` and ``/tftpboot`` are mounted on the service node
  from the Management Node, if appropriate.
* Make sure that the Service Node has Name resolution for all nodes, it will
  service.
