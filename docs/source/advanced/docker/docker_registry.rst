Docker Registry in xCAT
=======================

Docker Registry is a stateless, highly scalable server side application that stores and lets you distribute Docker images.

This document describes how to set up a local private docker registry on Ubuntu 15.04 on x86_64.

**Note:** Ensure that docker registry is not already set up on this docker host.

Setting Up Docker Host
----------------------

Install Docker version 1.6.0 or newer.

Setting Up Docker Registry Manually
-----------------------------------

Docker registry needed to be set up on xCAT's MN.

This section describes two methods of setting up docker registry manually.

First, create some folders where files for this tutorial will live. ::

    mkdir /docker-registry && cd $_
    mkdir certs

Copy xCAT server certificate and key to certs folder. ::

    cp /etc/xcat/cert/server-cert.pem certs/domain.crt
    cp /etc/xcat/cert/server-key.pem certs/domain.key

Method 1: Start Docker Registry Directly
````````````````````````````````````````

Create Configuration File
'''''''''''''''''''''''''

Define configuration file ``docker-registry`` under ``/docker-registry/`` folder as below. ::
  
    #!/bin/bash

    docker_command=$1
    if [ $docker_command = "start" ]; then
        docker_ps_result=$(docker ps -a | grep "registry")
        if [ -z $docker_ps_result ]; then
            docker run -d -p 5000:5000 --restart=always --name registry \
              -v `pwd`/data:/data \
              -e REGISTRY_STORAGE_FILESYSTEM_ROOTDIRECTORY=/data \
              -v `pwd`/certs:/certs \
              -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/domain.crt \
              -e REGISTRY_HTTP_TLS_KEY=/certs/domain.key \
              registry:2
        else
            docker start registry
        fi
    elif [ $docker_command = "stop" ]; then
        docker stop registry
    else
        echo "The parameter is wrong."
    fi

Starting Docker Registry as a Service
'''''''''''''''''''''''''''''''''''''

Create ``docker-registry.service`` file in ``/etc/systemd/system/``, add the following contents to it. ::

    [Unit]
    Description=Docker Registry

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    WorkingDirectory=/docker-registry
    ExecStart=/bin/bash docker-registry start
    ExecStop=/bin/bash docker-registry stop

    [Install]
    WantedBy=default.target

Start registry service: ::

    service docker-registry start

Method 2: Managing Docker Registry with Compose
```````````````````````````````````````````````

Docker Compose it is a tool for defining and running Docker applications. It could help setting up registry. 

Install Docker Compose
''''''''''''''''''''''

Compose can also be run inside a container, from a small bash script wrapper. To install compose as a container run: ::

    curl -L https://github.com/docker/compose/releases/download/1.5.2/docker-compose-`uname -s`-`uname -m` > /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose

Create Configuration File
'''''''''''''''''''''''''

Define configuration file ``docker-compose.yml`` under ``/docker-registry/`` folder as below. ::

    registry:
      restart: always
      image: registry:2
      ports:
        - 5000:5000
      environment:
        REGISTRY_STORAGE_FILESYSTEM_ROOTDIRECTORY: /data
        REGISTRY_HTTP_TLS_CERTIFICATE: /certs/domain.crt
        REGISTRY_HTTP_TLS_KEY: /certs/domain.key
      volumes:
        - ./data:/data
        - ./certs:/certs

The environment section sets environment variables in the Docker registry container. The Docker registry app knows to check this environment variable when it starts up and to start saving its data to the ``/data`` folder as a result.

Starting Docker Registry as a Service
'''''''''''''''''''''''''''''''''''''

Create ``docker-registry.service`` file in ``/etc/systemd/system/``, add the following contents to it. ::

    [Uint]
    Description=Docker Registry

    [Service]
    Type=simple
    Restart=on-failure
    RestartSec=30s
    WorkingDirectory=/docker-registry
    ExecStart=/usr/local/bin/docker-compose up

    [Install]
    WantedBy=default.target

Start registry service: ::

    service docker-registry start

Accessing Docker Registry from other docker host
------------------------------------------------

Copy ca.crt file from xCAT MN to a client machine. Client machine must be a docker host. ::

    scp username@xCAT_MN_ip:/etc/xcat/cert/ca.pem /etc/docker/certs.d/domainname:5000/ca.crt

List Available Images in Registry
`````````````````````````````````````
::

    curl -k https://domainname:5000/v2/_catalog 

Pull Images from Registry
`````````````````````````  
Just use the "tag" image name, which includes the domain name, port, and image name. ::

    docker pull domainname:5000/imagename

Push Images to Registry
```````````````````````

Before the image can be pushed to the registry, it must be tagged with the location of the private registry. ::

    docker tag imagename domainname:5000/imagename

Now we can push that image to our registry. ::

    docker push domainname:5000/imagename

**note:** If there is a problem with the CA certificate, edit the file ``/etc/default/docker`` so that there is a line that reads: ``DOCKER_OPTS="--insecure-registry domianname:5000"`` . Then restart Docker daemon ``service docker restart`` .


