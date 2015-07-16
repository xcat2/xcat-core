

Starting the confetty client
============================

As the root user, running ``/opt/confluent/bin/confetty`` will open the confetty prompt ::

      [root@c910f02c05p03 ~]# /opt/confluent/bin/confetty
      / -> 

Creating a non root user
========================

It's recommenteed to create a non root user to use to connect to confetty

#. Create a non-root user on the management node: ::

      useradd -m vhu

#. As root, create a non-root user in confetty: ::

      /opt/confluent/bin/confetty create users/vhu

#. Set the password for the non-root user: ::

      /opt/confluent/bin/confetty set users/vhu password="mynewpassword"
      password="********"


Connecting to a remote server 
=============================


In order to do remote sessions, keys must first be added to ``/etc/confluent``

* /etc/confluent/privkey.pem - private key 
* /etc/confluent/srvcert.pem - server cert

If you want to use the xCAT Keys, you can simple copy them into ``/etc/confluent`` ::

    cp /etc/xcat/cert/server-key.pem /etc/confluent/privkey.pem
    cp /etc/xcat/cert/server-cert.pem /etc/confluent/srvcert.pem 


Start confetty, specify the server IP address:  ::

    confetty -s 127.0.0.1



TODO: Add text for exporting user/pass into environment

 
