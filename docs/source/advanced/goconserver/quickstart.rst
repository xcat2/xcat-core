Quickstart
==========

To enable ``goconserver``, execute the following steps:

#. Install the ``goconserver`` RPM: ::

      yum install goconserver


#. If upgrading xCAT running ``conserver``, stop it first: ::

      systemctl stop conserver.service


#. Start ``goconserver`` and create the console configuration files with a single command ::

      makegocons

   The new console logs will start logging to ``/var/log/consoles/<node>.log``