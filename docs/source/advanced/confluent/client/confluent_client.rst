
Starting the confetty client
============================

As the root user, running ``/opt/confluent/bin/confetty`` will open the confetty prompt ::

      [root@c910f02c05p03 ~]# /opt/confluent/bin/confetty
      / ->

Creating a non root user
========================

It's recommenteed to create a non root user to use to connect to confetty

#. Create a non-root user on the management node: ::

      useradd -m xcat

#. As root, create a non-root user in confetty: ::

      /opt/confluent/bin/confetty create users/xcat

#. Set the password for the non-root user: ::

      /opt/confluent/bin/confetty set users/xcat password="mynewpassword"
      password="********"


Connecting to a remote server
=============================


In order to do remote sessions, keys must first be added to ``/etc/confluent``

* /etc/confluent/privkey.pem - private key
* /etc/confluent/srvcert.pem - server cert

If you want to use the xCAT Keys, you can simple copy them into ``/etc/confluent`` ::

    cp /etc/xcat/cert/server-key.pem /etc/confluent/privkey.pem
    cp /etc/xcat/cert/server-cert.pem /etc/confluent/srvcert.pem

The user and password may alternatively be provided via environment variables: ::

    CONFLUENT_USER=xcat
    CONFLUENT_PASSPHRASE="mynewpassword"
    export CONFLUENT_USER CONFLUENT_PASSPHRASE

Start confetty, specify the server IP address:  ::

    confetty -s <remote_ip>

If you want to run a confluent command against another host, could set the CONFLUENT_HOST variable: ::

    CONFLUENT_HOST=<remote_ip>
    export CONFLUENT_HOST


