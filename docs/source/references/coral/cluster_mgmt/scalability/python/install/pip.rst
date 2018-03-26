Using pip
=========

A alternative method for installing the Python dependencies is using ``pip``.  

#. Download ``pip`` using one of the following methods:

   #. ``pip`` is provided in the EPEL repo as: ``python2-pip``

   #. Follow the instructions to install from here: https://pip.pypa.io/en/stable/installing/

#. Use ``pip`` to install the following Python libraries: ::

      pip install gevent docopt requests paramiko scp 


#. Install ``xCAT-openbmc-py`` using ``rpm`` with ``--nodeps``: ::

        cd xcat-core
        rpm -ihv xCAT-openbmc-py*.rpm  --nodeps


