
Getting Started
===============

Confluent is intended to be used in conjunction with xCAT.
The following documentation assumes that xCAT is already installed and configured on the management node.

Download confluent
==================

To build from source, ensure your machine has the correct development packages to build rpms, then execute the following:

    * Clone the git repo:  ::

        git clone https://github.com/xcat2/confluent.git

    * Build the ``confluent-server`` and ``confluent-client`` packages: ::

        cd confluent/confluent_server ; ./buildrpm ; cd -
        cd confluent/confluent_client ; ./buildrpm ; cd -


Install
=======

dependency
----------

The following example describes the steps for **rhels7.5** on **ppc64le**::

    yum install libffi-devel.ppc64le
    yum install openssl-devel
    pip install crypto pyasn1 pycrypto eventlet pyparsing netifaces scrapy pysnmp paramiko pyghmi pyte


confluent
---------

Installing ``xCAT-confluent`` via rpm::

    rpm -ivh /root/rpmbuild/RPMS/noarch/confluent_server-*.noarch.rpm --nodeps
    rpm -ivh /root/rpmbuild/RPMS/noarch/confluent_client-*.noarch.rpm --nodeps

You may find it helpful to add the confluent paths into your system path::

    CONFLUENTROOT=/opt/confluent
    export PATH=$CONFLUENTROOT/bin:$PATH
    export MANPATH=$CONFLUENTROOT/share/man:$MANPATH


Configuration
=============

Starting/Stopping confluent
---------------------------

To start confluent::

    service confluent start

To stop confluent::

    service confluent stop

If you want confluent daemon to start automatically at bootup, add confluent service to ``chkconfig``::

    chkconfig confluent on


Replacing conserver with confluent
----------------------------------

A new keyword, ``consoleservice``, has been added to the xCAT site table to allow the system administrator to control between **conserver** and **confluent**.  If ``consoleservice`` is not set, default behavior is to use **conserver**.

Set the consoleservice to confluent::

    chdef -t site consoleservice='confluent'

Run ``makeconfluentcfg`` to create the confluent configuration files::

    makeconfluentcfg

Use ``rcons`` as before to start the console session.::

    rcons <singlenode>


Web Browser access
==================

Confluent-api and confluent-consoles are able to be accessed from the browser.
It is **highly** recommended that you create a non-root user to access the sessions::

    Create the non-root user on the management node
    # useradd -m xcat

    Create a non-root user in confetty
    # /opt/confluent/bin/confetty create users/xcat

    Set the password for the non-root user
    # /opt/confluent/bin/confetty set users/xcat password="mynewpassword"
    password="********"

Rest Explorer
=============

Configure the httpd configuration for confluent-api by creating a ``confluent.conf`` file under ``/etc/httpd/conf.d/`` directory::

    The example uses server ip: 10.2.5.3 and port 4005

    # cat /etc/httpd/conf.d/confluent.conf
    LoadModule proxy_http_module modules/mod_proxy_http.so
    <Location /confluent-api>
            ProxyPass http://10.2.5.3:4005
    </Location>

    # restart httpd
    service httpd restart

Now point your browser to: ``http://<server ip>:<port>`` and log in with the non-root user and password created above.

Confluent consoles
==================

confluent-web is provided in a subdirectory under the confluent project `confluent_web <https://github.com/xcat2/confluent/tree/master/confluent_web/>`_

Download the content of that directory to ``/var/www/html/confluent`` and point your browser to::

    http://<server ip>/confluent/consoles.html


