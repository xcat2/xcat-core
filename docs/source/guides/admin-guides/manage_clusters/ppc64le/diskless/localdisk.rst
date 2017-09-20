.. include:: ../../../common/deployment/enable_localdisk.rst

``Note``:
    * `localdisk` feature won't syncronize the files/directories defined in `litefile` table from diskless image to local disk at the node boot time. It might casue issue to the application which depends on some of those directories. For example, the ``httpd`` service cannot be started if ``/var/log/`` is defined in `litefile` table. To work around this, you may copy the required contents to local disk and restart service manually at the first time.

    * To keep the contents on local disk after you use ``enablepart=yes`` to do partitioin, make sure to set ``enablepart=no`` in partitioin configuration file after the node is booted.