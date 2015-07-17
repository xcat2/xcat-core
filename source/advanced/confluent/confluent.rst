Getting Started 
---------------

For xCAT 2.9.1 and later, confluent is intended to be used in conjunction with xCAT. 
The following documentation assumes that xCAT is already installed and configured on the management node.

Download
--------

confluent
~~~~~~~~~

rpms
^^^^

The latest confluent rpms are built and provided for your convenience:  `confluent rpms <https://sourceforge.net/projects/xcat/files/confluent/rpms>`_.  However, the rpms are not built on a regular release schedule.  To use the latest code base, consider building the rpms from :ref:`label_confluent_source`.

The following example downloads the confluent tar package and creates a local repository on your management node::

    mkdir ~/confluent
    cd ~/confluent
    wget https://path-to-confluent/confluent-X.X-repo.tbz2
    tar jxvf confluent-X.X-repo.tbz2
    cd confluent-X.X
    ./mklocalrepo.sh 

.. _label_confluent_source:

source
^^^^^^

To build from source, ensure your development machine has the correct development packages to create rpms, then execute hte following:

    * Clone the git repo:  ::

        git clone https://github.com/xcat2/confluent.git

    * Build the ``confluent-server`` and ``confluent-client`` packages: ::

        cd confluent/confluent_server ; ./buildrpm ; cd -
        cd confluent/confluent_client ; ./buildrpm ; cd -


confluent-dep
~~~~~~~~~~~~~

The latest confluent dependency packages are provided for your convenience: `confluent-deps <http://sourceforge.net/projects/xcat/files/confluent-dep/>`_ 

The following example describes the steps for **rhels7.1** on **ppc64le**::

    mkdkir ~/confluent
    cd ~/confluent
    wget https://path/to/confluent-dep/rh7/ppc64le/confluent-dep-rh7-ppc64le.tar.bz2
    tar -jxvf confluent-dep-rh7-ppc64le.tar.bz2
    cd confluent-dep-rh7-ppc64le/
    ./mklocalrepo.sh 

**Note:** If the OS/architecture you are looking for is not provided under confluent-dep, 
please send an email to the xcat-users mailing list: xcat-users@lists.sourceforge.net


Install 
-------

*confluent and confluent-deps must be downloaded to the management node before installing*

xCAT 2.9.1 began shipping a new rpm ``xCAT-confluent``.  

Installing ``xCAT-confluent`` via yum will pull in the confluent dependencies::

    yum install xCAT-confluent

You may find it helpful to add the confluent paths into your system path::

    CONFLUENTROOT=/opt/confluent
    export PATH=$CONFLUENTROOT/bin:$PATH
    export MANPATH=$CONFLUENTROOT/share/man:$MANPATH

Configuration
-------------

Starting/Stopping confluent
^^^^^^^^^^^^^^^^^^^^^^^^^^^

To start confluent::

    service confluent start

To stop confluent::
   
    service confluent stop

If you want confluent daemon to start automatically at bootup, add confluent service to ``chkconfig``::

    chkconfig --add confluent

Replacing conserver with confluent
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

A new keyword, ``consoleservice``, has been added to the xCAT site table to allow the system administrator to control between **conserver** and **confluent**.  If ``consoleservice`` is not set, default behavior is to use **conserver**.

Set the consoleservice to confluent::

    chdef -t site consoleservice='confluent'

Run ``makeconfluentcfg`` to create the confluent configuration files::

    makeconfluentcfg

Use ``rcons`` as before to start the console session.::

    rcons <singlenode>

    # If using confluent, a timestamp will be shown on the 
    # console title next to the node name
    <singlenode> [15:05]
    


Web Browser access
------------------

Confluent-api and confluent-consoles are able to be accessed from the browser.
It is **highly** recommended that you create a non-root user to access the sessions::

    Create the non-root user on the management node
    # useradd -m vhu

    Create a non-root user in confetty
    # /opt/confluent/bin/confetty create users/vhu

    Set the password for the non-root user
    # /opt/confluent/bin/confetty set users/vhu password="mynewpassword"
    password="********"

Rest Explorer
^^^^^^^^^^^^^

TODO: some intro text

Configure the httpd configuration for confluent-api by creating a ``confluent.conf`` file under ``/etc/httpd/conf.d/`` directory::

    The example uses server ip: 10.2.5.3 and port 4005

    cat /etc/httpd/conf.d/confluent.conf
    LoadModule proxy_http_module modules/mod_proxy_http.so
    <Location /confluent-api>
            ProxyPass http://10.2.5.3:4005
    </Location>
   
    #restart httpd  
    service httpd restart

Now point your browser to: ``http://<server ip>:<port>`` and log in with the non-root user and password created above. 

Confluent consoles
^^^^^^^^^^^^^^^^^^

confluent-web is provided in a subdirectory under the confluent project `confluent_web <https://sourceforge.net/p/xcat/confluent/ci/master/tree/confluent_web/>`_

Download the content of that directory to ``/var/www/html/confluent`` and point your browser to::

    http://<server ip>/confluent/consoles.html


