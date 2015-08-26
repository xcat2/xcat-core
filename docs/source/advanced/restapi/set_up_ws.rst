Set Up Web Service for REST API
===============================

The following steps describe how to setup the WEB Service to use the REST API

Enable the HTTPS service for REST API
-------------------------------------

To improve the security between the REST API client and server, enabling the HTTPS service on the xCAT management is recommended. And the REST API client should use the 'https' to access web server instead of the 'http'. 

* RHEL 6 (x86_64/ppc64) and RHEL 5 (x86_64) ::

		yum install mod_ssl
		service httpd restart
		yum install perl-JSON

* RHEL 5 (ppc64) ::

  Uninstall httpd.ppc64 and install httpd.ppc: ::

		rpm -e --nodeps httpd.ppc64 
		rpm -i httpd.ppc mod_ssl.ppc

* SLES 10/11 (x86_64/ppc64) ::

		a2enmod ssl
		a2enflag SSL
		/usr/bin/gensslcert
		cp /etc/apache2/vhosts.d/vhost-ssl.template /etc/apache2/vhosts.d/vhost-ssl.conf
		Insert line 'NameVirtualHost *:443' before the line '## SSL Virtual Host Context'
		/etc/init.d/apache2 restart
		zypper install perl-JSON

* Ubuntu ::

		sudo a2enmod ssl
		ln -s ../sites-available/default-ssl.conf  /etc/apache2/sites-enabled/ssl.conf
		sudo service apache2 restart

  verify it is loaded: ::

		sudo apache2ctl -t -D DUMP_MODULES | grep ssl
		apt-get install libjson-perl

Enable the Certificate of HTTPs Server (Optional)
-------------------------------------------------

Enabling the certificate functionality of https server is useful for the Rest API client to authenticate the server. 

Since a certificate for xcatd has already been generated when installing xCAT, it can be reused by the https server. To enable the server certificate authentication, the hostname of xCAT MN must be a fully qualified domain name (FQDN) that the REST API client must use when accessing the https server. If the hostname of the xCAT MN is not a FQDN, you need to change the hostname. Also, typically the hostname of the xCAT MN is initially set to correspond to the NIC that faces the cluster, which is usually an internal/private NIC. If you want to be able to use the REST API from a remote client, you should make the xCAT MN hostname correspond to the public NIC. To change the hostname, edit /etc/sysconfig/network (RHEL) or /etc/HOSTNAME (SLES) and run: :: 

    hostname <newFQDN>

Rerun xcatconfig to generate a new server certificate with the correct hostname. ::

    xcatconfig -c

Notes: If you had previously generated a certificate for non-root userids to use xCAT, you must regenerate them using: /opt/xcat/share/xcat/scripts/setup-local-client.sh<username>

The steps to configure the certificate for https server: ::

		export sslcfgfile=/etc/httpd/conf.d/ssl.conf              # rhel
		export sslcfgfile=/etc/apache2/vhosts.d/vhost-ssl.conf    # sles
		export sslcfgfile=/etc/apache2/sites-enabled/ssl.conf     # ubuntu
	
		sed -i 's/^\(\s*\)SSLCertificateFile.*$/\1SSLCertificateFile \/etc\/xcat\/cert\/server-cred.pem/' $sslcfgfile
		sed -i 's/^\(\s*\)SSLCertificateKeyFile.*$/\1SSLCertificateKeyFile \/etc\/xcat\/cert\/server-cred.pem/' $sslcfgfile

		service httpd restart        # rhel
		service apache2 restart      # sles/ubuntu

The REST API client needs to download the xCAT certificate CA from the xCAT http server to authenticate the certificate of the server. ::

	cd /root
	wget http://<xcat MN>/install/postscripts/ca/ca-cert.pem

When accessing using the REST API, the certificate CA must be specified and the FQDN of the https server hostname must be used. For example: ::

  curl -X GET --cacert /root/ca-cert.pem 'https://<FQDN of xCAT MN>/xcatws/nodes?userName=root& \
      userPW=cluster'

Extend the Timeout of Web Server
--------------------------------

Some operations like 'create osimage' (copycds) need a long time (longer than 3 minutes sometimes) to complete. It would fail with a timeout (504 Gateway Time-out) if the timeout setting in the web server is not extended: ::

	For rhel
		sed -i 's/^Timeout.*/Timeout 600/' /etc/httpd/conf/httpd.conf
		service htttd restart
	For sles
		echo "Timeout 600" >> /etc/apache2/httpd.conf
		service apache2 restart
		
Set Up an Account for Web Service Access
----------------------------------------

The REST API calls need to provide a username and password. When this request is passed to xcatd, it will first verify that this user/pw is in the xCAT TODO:passwd table, and then xcatd will look in the TODO:policy table to see if that user is allowed to do the requested operation.

The account which key is **xcat** will be used for the REST API authentication. The username and password should be passed in with the attirbutes:
userName: Pass the username of the account
userPW: Pass the password of the account (xCAT 2.10)
password: Pass the password of the account (xCAT earlier than 2.10)

You can use the root userid for your API calls, but we recommend you create a new userid (for example wsuser) for the API calls and give it the specific privileges you want it to have.

Use root Account
~~~~~~~~~~~~~~~

Since the certificate and ssh keys for **root** account has been created during the install of xCAT. And the public ssh key has been uploaded to computer node so that xCAT MN can ssh to CN without password. Then the only thing needs to do is to add the password for the **root** in the passwd table. ::

		tabch key=xcat,username=root passwd.password=<root-pw>
	
Use non-root Account
~~~~~~~~~~~~~~~~~~~

Create new user and setup the password and policy rules. ::

		useradd wsuser
		passwd wsuser     # set the password
		tabch key=xcat,username=wsuser passwd.password=cluster
		mkdef -t policy 6 name=wsuser rule=allow

Note: in the tabch command above you can put the salted password (from /etc/shadow) in the xCAT passwd table instead of the clear text password, if you prefer. 

Create the SSL certificate under that user's home directory so that user can be authenticated to xCAT. This is done by running the following command on the Management node as root: ::

		/opt/xcat/share/xcat/scripts/setup-local-client.sh <username>

When running this command you'll see SSL certificates created. Enter "y" where prompted and take the defaults. 

To enable the POST method of resources like nodeshell,nodecopy,updating,filesyncing for the non-root user, you need to enable the ssh communication between xCAT MN and CN without password. Log in as <username> and run following command: ::

		xdsh <noderange> -K

Refer to the doc to TODO:[Granting_Users_xCAT_privileges] for details. 

Run a test request to see if everything is working: ::

		curl -X GET --cacert /root/ca-cert.pem \
		'https://<xcat-mn-host>/xcatws/nodes?userName=<user>&userPW=<password>'

or if you did not set up the certificate: ::

		curl -X GET -k 'https://<xcat-mn-host>/xcatws/nodes?userName=<user>&userPW=<password>'

You should see some output that includes your list of nodes. 
