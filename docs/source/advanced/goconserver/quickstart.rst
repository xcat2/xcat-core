Quickstart
----------

To enable ``goconserver``, execute the following steps: 

#. Install the ``goconserver`` RPM: ::

      yum install goconserver 


#. If upgrading an existing xCAT installation, stop ``conserver``: ::

      service conserver stop 


#. Create the console configuration files and start ``goconserver``: ::

      makegocons 

   The new console logs will start logging to ``/var/log/consoles/<node>.log``



