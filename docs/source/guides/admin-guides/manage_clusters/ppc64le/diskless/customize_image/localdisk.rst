.. include:: ../../../common/deployment/enable_localdisk.rst

.. note:: ``enablepart=yes`` in partition file will partition the local disk at every boot. If you want to preserve the contents on local disk at next boot, change to ``enablepart=no`` after the initial provision. A log file ``/.sllocal/log/localdisk.log`` on the target node can be used for debugging.
