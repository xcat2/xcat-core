Appendix D: Set up Hierarchical Conserver
=========================================

To allow you to open the rcons from the Management Node using the
conserver daemon on the Service Nodes, do the following:

* Set nodehm.conserver to be the service node (using the ip that faces the
  management node) ::

    chdef -t <noderange> conserver=<servicenodeasknownbytheMN>
    makeconservercf
    service conserver stop
    service conserver start
