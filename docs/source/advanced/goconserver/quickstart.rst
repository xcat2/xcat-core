Quickstart
==========

To enable ``goconserver``

#. For switching from ``conserver``, shall stop it first

   #. stop ``conserver``

       systemctl stop conserver.service

   #. (Optional) for service nodes:

       chdef -t group -o service setupconserver=2

       xdsh service 'systemctl stop conserver.service'

#. To start and configure ``goconserver``

       makegocons

   The new console logs will start logging to ``/var/log/consoles/<node>.log``

#. To check the console status of nodes, use:

       makegocons -q
