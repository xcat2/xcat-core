Quickstart
==========

#. For refresh xCAT installation, run the command below to start and configure ``goconserver``

    makegocons

  The new console logs will start logging to ``/var/log/consoles/<node>.log``

#. For xCAT updating, and use ``conserver`` before, following the step below to enable ``goconserver``

   #. stop ``conserver`` on management node

       systemctl stop conserver.service

   #. For hierarchical cluster, shall also stop ``conserver`` on **service nodes**, and config ``goconserver`` as console server:

       xdsh service 'systemctl stop conserver.service'

       chdef -t group -o service setupconserver=2

   #. start and configure ``goconserver``

       makegocons

     The new console logs will start logging to ``/var/log/consoles/<node>.log``

#. To check the console status of nodes, use:

       makegocons -q
