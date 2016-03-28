Docker life-cycle management in xCAT
====================================

The Docker linux container technology is currently very popular. xCAT can help managing Docker containers. xCAT, as a system management tool has the natural advantage for supporting multiple operating systems, multiple architectures and large scale clusters.

This document describes how to use xCAT for docker management, from Docker Host setup to docker container operationis. 

**Note:** The document is based on **Docker Version 1.10.x** and **Docker API version 1.22.** And the Docker Host is based on **ubuntu14.04.3 x86_64**. At the time of this writing (February 2016), docker host images are not available for **ppc64** architecture from docker.org. You can search online to find them or build your own.

Setting up Docker Host
----------------------

The **Docker Host** is the bare metal server or virtual machine where Docker containers can run. It will be called *dockerhost* in the following sections. 

The *dockerhost* at a minimum must provide the following:

* An Operating System for running docker daemon
* The certification related files to be used by Docker service for trusted connection.

Preparing osimage for docker host
`````````````````````````````````
The osimage represents the image of the Operating System which will be deployed on the dockerhost. 

Copy files out from DVDs/ISOs and generate  
""""""""""""""""""""""""""""""""""""""""""

::  
   
  copycds ubuntu-14.04.3-server-amd64.iso

Create pkglist and otherpkglist of osimage for dockerhost
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""

The pkglist file should contain the following: ::

 # cat /install/custom/ubuntu1404/ubuntu1404.pkglist
 openssh-server
 ntp
 gawk
 nfs-common
 snmpd
 bridge-utils
 
The otherpkglist file should contain the following: ::

 # cat /install/custom/ubuntu1404/ubuntu1404_docker.pkglist
 docker-engine

Create the osimage for dockerhost
"""""""""""""""""""""""""""""""""
The osimage for dockerhost will be like this: ::

 # lsdef -t osimage ub14.04.03-x86_64-dockerhost
 Object name: ub14.04.03-x86_64-dockerhost
     imagetype=linux
     osarch=x86_64
     osname=Linux
     osvers=ubuntu14.04.3
     otherpkgdir=https://apt.dockerproject.org/repo ubuntu-trusty main,http://cz.archive.ubuntu.com/ubuntu trusty main
     otherpkglist=/install/custom/ubuntu1404/ubuntu1404_docker.pkglist
     pkgdir=/install/ubuntu14.04.3/x86_64
     pkglist=/install/custom/ubuntu1404/ubuntu1404.pkglist
     profile=compute
     provmethod=install
     template=/opt/xcat/share/xcat/install/ubuntu/compute.tmpl

Preparing setup trust connection for docker service and create docker network object
````````````````````````````````````````````````````````````````````````````````````
Currently, a customer defined network object is needed when create a docker container with static IP address, it can be done with the command: ::

 chdef host01 -p postbootscripts="setupdockerhost <netobj_name>=<subnet>/<netmask>@<gateway>[:nicname]"

* netobj_name: the network object to be created, it will be used in *dockernics* when creating docker container 
* subnet/netmask@gateway: the network which the IP address of docker container running on the docker host must be located in. If *nicname* is specified, the *subnet/netmask* must be the subnet of the nic *nicname* located in. And *gateway* shall be the IP address of the nic *nicname*.
* nicname: the physical nic name which will be attached to the network object 

For example, a network object *mynet0* with subnet *10.0.0.0/16* and gateway *10.0.101.1* on nic *eth0* can be created with the command: ::

 chdef host01 -p postbootscripts="setupdockerhost mynet0=10.0.0.0/16@10.0.101.1:eth0"

Start OS provisioning for dockerhost
````````````````````````````````````

Reference :ref:`Initialize the Compute for Deployment<deploy_os>` for how to finish an OS deployment.

Docker instance management
--------------------------

After the dockerhost is ready, a docker instance can be managed through xCAT commands. In xCAT, a docker instance is represented by a node whose definition can be like this: ::

 # lsdef host01c01
 Object name: host01c01
     dockerhost=host01:2375
     dockernics=mynet0
     groups=docker,all
     ip=10.0.120.1
     mac=02:42:0a:00:78:01
     mgt=docker
     postbootscripts=otherpkgs
     postscripts=syslog,remoteshell,syncfiles

The command :doc:`mkdef </guides/admin-guides/references/man1/mkdef.1>` or :doc:`chdef </guides/admin-guides/references/man1/chdef.1>` can be used to create a new docker instance node or change the node attributes. Specify any available unused ip address for *ip* attribute.

After docker instance node is defined, use command `makehosts host01c01` to add node *host01c01* and its IP address *10.0.120.1* into /etc/hosts.

Create docker instance
``````````````````````
::

 mkdocker <node> [image=<image_name>  [command=<command>] [dockerflag=<docker_flags>]]

* node - The node object which represents the docker instance
* image - The image name that the docker instance will use
* command - The command that the docker will run
* dockerflag - A JSON string which will be used as parameters to create a docker. Reference `docker API v1.22 <https://docs.docker.com/engine/reference/api/docker_remote_api_v1.22/>`_ for more information about which parameters can be specified for "dockerflag".

To create the docker instance *host01c01* with image *ubuntu* and command */bin/bash*, use: ::
 
 mkdocker host01c01 image=ubuntu command=/bin/bash dockerflag="{\"AttachStdin\":true,\"AttachStdout\":true,\"AttachStderr\":true,\"OpenStdin\":true}"

Remove docker instance
``````````````````````
::

 rmdocker <node>

The command **rmdocker host01c01** can be used to remove the docker instance *host01c01*.

List docker information
```````````````````````
::

 lsdocker <dockerhost|node> [-l|--logs]

To list all the running docker instances on the dockerhost *host01*, use **lsdocker host01**.

To list the info of docker instance *host01c01*, use **lsdocker host01c01**.

To get log info of docker instance *host01c01*, use **lsdocker host01c01 --logs**.

Start docker instance
`````````````````````
::

 rpower <node> start

Stop docker instance
````````````````````
::

 rpower <node> stop

Restart docker instance
```````````````````````
::

 rpower <node> restart

Pause all processes within a docker instance
````````````````````````````````````````````
::

 rpower <node> pause

Unpause all processes within a docker instance
``````````````````````````````````````````````
::

 rpower <node> unpause

Check docker instance status
````````````````````````````
::

 rpower <node> state
