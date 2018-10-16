Enable the HTTPS protocol for REST API
======================================

To improve the security between the REST API clients and server, enabling the secure transfer protocol (https) is the default configuration.

* **[RHEL6/7/8 (x86_64/ppc64/ppc64le) and RHEL5 (x86_64)]** ::

    yum install mod_ssl
    service httpd restart
    yum install perl-JSON

* **[RHEL5 (ppc64)]**

  Uninstall httpd.ppc64 and install httpd.ppc: ::

    rpm -e --nodeps httpd.ppc64
    rpm -i httpd.ppc mod_ssl.ppc

* **[SLES10/11/12 (x86_64/ppc64)]** ::

    a2enmod ssl
    a2enflag SSL
    /usr/bin/gensslcert
    cp /etc/apache2/vhosts.d/vhost-ssl.template /etc/apache2/vhosts.d/vhost-ssl.conf
    Insert line 'NameVirtualHost *:443' before the line '## SSL Virtual Host Context'
    /etc/init.d/apache2 restart
    zypper install perl-JSON

* **[Ubuntu]** ::

    sudo a2enmod ssl
    ln -s ../sites-available/default-ssl.conf  /etc/apache2/sites-enabled/ssl.conf
    sudo service apache2 restart

    # verify it is loaded:

    sudo apache2ctl -t -D DUMP_MODULES | grep ssl
    apt-get install libjson-perl

.. note:: If use of non-secure HTTP protocol is required, edit ``/etc/httpd/conf.d/xcat-ws.conf`` for RHEL or ``/etc/apache2/conf.d/xcat-ws.conf`` for others and change ``RewriteEngine On`` to ``RewriteEngine Off``, then restart httpd or apache.

Enable the Certificate of HTTPs Server (Optional)
=================================================

Enabling the certificate functionality of https server is useful for the Rest API client to authenticate the server.

The certificate for xcatd has already been generated when installing xCAT, it can be reused by the https server. To enable the server certificate authentication, the hostname of xCAT MN must be a fully qualified domain name (FQDN). The REST API client also must use this FQDN when accessing the https server. If the hostname of the xCAT MN is not a FQDN, you need to change the hostname first.

Typically the hostname of the xCAT MN is initially set to the NIC which faces to the cluster (usually an internal/private NIC). If you want to enable the REST API for public client, set the hostname of xCAT MN to one of the public NIC.

To change the hostname, edit ``/etc/sysconfig/network`` (RHEL) or ``/etc/HOSTNAME`` (SLES) and run:  ::

    hostname <newFQDN>

After changing the hostname, run the xcat command ``xcatconfig`` to generate a new server certificate based on the correct hostname: ::

    xcatconfig -c

.. note:: If you had previously generated a certificate for non-root userids to use xCAT, you must regenerate them using ``/opt/xcat/share/xcat/scripts/setup-local-client.sh <username>``

The steps to configure the certificate for https server: ::

    export sslcfgfile=/etc/httpd/conf.d/ssl.conf              # rhel
    export sslcfgfile=/etc/apache2/vhosts.d/vhost-ssl.conf    # sles
    export sslcfgfile=/etc/apache2/sites-enabled/ssl.conf     # ubuntu

    sed -i 's/^\(\s*\)SSLCertificateFile.*$/\1SSLCertificateFile \/etc\/xcat\/cert\/server-cred.pem/' $sslcfgfile
    sed -i 's/^\(\s*SSLCertificateKeyFile.*\)$/#\1/' $sslcfgfile

    service httpd restart        # rhel
    service apache2 restart      # sles/ubuntu

The REST API client needs to download the xCAT certificate CA from the xCAT http server to authenticate the certificate of the server. ::

    cd /root
    wget http://<xcat MN>/install/postscripts/ca/ca-cert.pem

When accessing the REST API, the certificate CA must be specified and the FQDN of the https server must be used. For example: ::

    curl -X GET --cacert /root/ca-cert.pem 'https://<FQDN of xCAT MN>/xcatws/nodes?userName=root&userPW=<root-pw>'

.. attention:: Some operations like 'create osimage' (i.e.  copycds) may require a longer time to complete  and may result in a "504 Gateway Timeout" error. To avoid this, modify the ``httpd.conf`` file and extend the timeout to a larger value: ``Timeout: 600``

Set Up an Account for Web Service Access
========================================

User needs a username and password to access the REST API. When the REST API request is passed to xcatd, the username and password will be verified based on the :doc:`xCAT passwd Table </guides/admin-guides/references/man5/passwd.5>`, and then xcatd will look in the :doc:`xCAT policy Table </guides/admin-guides/references/man5/policy.5>` to see if the user is allowed to perform the requested operation.

The account with key of **xcat** will be used for the REST API authentication. The username and password should be passed in as the attirbutes of URL:

:userName: Pass the username of the account
:userPW: Pass the password of the account (xCAT 2.10)
:password: Pass the password of the account (xCAT earlier than 2.10)

You can use the root userid for your API calls, but we recommend you create a new userid (for example wsuser) for the API calls and give it the specific privileges you want it to have.

Use root Account
----------------

The certificate and ssh keys for **root** account has been created during the install of xCAT. The public ssh key also has been uploaded to compute node so that xCAT MN can ssh to CN without password. Then the only thing left to do is to add the password for the **root** in the passwd table. ::

    tabch key=xcat,username=root passwd.password=<root-pw>

Use non-root Account
--------------------

Create new user and setup the password and policy rules. ::

    # create a user
    useradd -u <wsuid> <wsuser>
    # set the password
    passwd <wsuser>
    # add password to passwd table
    tabch key=xcat,username=<wsuser> passwd.password=<wspw>
    # add user to policy table
    mkdef -t policy 6 name=<wsuser> rule=allow

.. note:: Using the ``tabch`` command, you can use the salted password from ``/etc/shadow`` into the xCAT password table instead of a clear text password.

Identical user with the same name and uid need to be created on each compute node. ::

    # create a user
    useradd -u <wsuid> <wsuser>
    # set the password
    passwd <wsuser>

Create the SSL certificate under that user's home directory so that user can be authenticated to xCAT. This is done by running the following command on the Management node as root: ::

    /opt/xcat/share/xcat/scripts/setup-local-client.sh <wsuser>

When running this command you'll see SSL certificates created. Enter "y" where prompted and take the defaults.

To enable the POST method of resources like nodeshell, nodecopy, updating and filesyncing for the non-root user, you need to enable the ssh communication between xCAT MN and CN without password. Log in as <username> and run following command: ::

    xdsh <noderange> -K

Run a test request to see if everything is working: ::

    curl -X GET --cacert /root/ca-cert.pem 'https://<xcat-mn-host>/xcatws/nodes?userName=<wsuser>&userPW=<wspw>'

or if you did not set up the certificate: ::

    curl -X GET -k 'https://<xcat-mn-host>/xcatws/nodes?userName=<wsuser>&userPW=<wspw>'

You should see some output that includes your list of nodes.

If errors returned, check ``/var/log/httpd/ssl_error_log`` on xCAT MN.

.. note:: When passwords are changed, make sure to update the xCAT ``passwd`` table.  The REST API service uses passwords stored there to authenticate users.

