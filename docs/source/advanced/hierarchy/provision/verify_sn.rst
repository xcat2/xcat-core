Verify Service Node Installation
================================

* ssh to the service nodes. You should not be prompted for a password.
* Check to see that the xcat daemon ``xcatd`` is running.
* Run some database command on the service node, e.g ``tabdump site``, or ``nodels``, and see that the database can be accessed from the service node.
* Check that ``/install`` and ``/tftpboot`` are mounted on the service node from the Management Node, if appropriate.
* Make sure that the Service Node has name resolution for all nodes it will service.
* Run ``updatenode <compute node> -V -s`` on management node and verify output contains ``Running command on <service node>`` that indicates the command from management node is sent to service node to run against compute node target.

See :doc:`Appendix B <../appendix/appendix_b_diagnostics>` for possible solutions.
