Docker life-cycle management in xCAT
====================================

The docker technology is very hot those days, xCAT as a system management tool have the natural advantage to support docker. Such as multiple OS, multiple archs and large scale clusters for Docker Host are supported. 

In this document, it describes how does xCAT do docker management, from Docker Host setup to docker container operation. 

**Note:** The document is based on **Docker Version 1.9.1** and **Docker API version 1.21.** And the Docker Host is based on **ubuntu14.04.3 x86_64**.  

Setting up Docker Host
----------------------

The **Docker Host** is the bare metal server or virtual machine where Docker container can run on. It will be called *dockerhost* in the following sections. 

The *dockerhost* at least contains the following priorities:

* An Operating System the docker daemon can be running
* An Bridge which can be used by Docker Container to create virtual network adapter on
* The certificating related files to be used by Docker service for trust connection.

Preparing osimage for docker host
`````````````````````````````````
The osimage represent the image of the Operating System which will be deployed on the dockerhost. 

Copy files out from DVDs/ISOs and generate  
""""""""""""""""""""""""""""""""""""""""""

::  
   
  copycds ubuntu-14.04.3-server-amd64.iso

Create pkglist and otherpkglist of osimage for dockerhost
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""

The pkglist will be like this ::

 # cat /install/custom/ubuntu1404/ubuntu1404.pkglist
 openssh-server
 ntp
 gawk
 nfs-common
 snmpd
 bridge-utils
 
The otherpkglist will be like this ::

 # cat /install/custom/ubuntu1404/ubuntu1404_docker.pkglist
 docker-engine

Create the osimage for dockerhost
"""""""""""""""""""""""""""""""""
The osimage for dockerhost will be like this ::

 # lsdef -t osimage ub14.04.03-x86_64-dockerhost
 Object name: ub14.04.03-x86_64-dockerhost
     imagetype=linux
     osarch=x86_64
     osname=Linux
     osvers=ubuntu14.04.3
     otherpkgdir=https://apt.dockerproject.org/repo ubuntu-trusty main
     otherpkglist=/install/custom/ubuntu1404/ubuntu1404_docker.pkglist
     pkgdir=/install/ubuntu14.04.3/x86_64
     pkglist=/install/custom/ubuntu1404/ubuntu1404.pkglist
     profile=compute
     provmethod=install
     template=/opt/xcat/share/xcat/install/ubuntu/compute.tmpl

Preparing config bridge for dockerhost
``````````````````````````````````````
Currently, the script *xHRM* can be used to config bridge based on a network adapter. In can be replaced by *confignetworks* in the future. To have the dockerhost configure bridge during OS provisioning. The command below can be used: ::

 chdef host01 -p postbootscripts="xHRM bridgeprereq eth0:mydocker0"

The script above means configure bridge "mydocker0" based on "eth0". Please **don't modify bridge name "mydocker0"** since it will be used when setting up docker service on dockerhost.

Preparing setup trust connection for docker service
```````````````````````````````````````````````````

::

 chdef host01 -p postbootscripts="setupdockerhost"

Start OS provisioning for dockerhost
````````````````````````````````````

Please reference :ref:`Initialize the Compute for Deployment<deploy_os>` for more about how to finish an OS deployment.

Setup docker instance network configuration tool on dockerhost(Optional)
````````````````````````````````````````````````````````````````````````

Currently, Docker doesn't provide native supporting to configure specified ip address for docker instance that is runing or will be run on the dockerhost, but `pipework <https://github.com/jpetazzo/pipework>`_ can do this. So, after dockerhost is up and running, the "pipework" is suggest to be set up on it.

First, download the "pipework" ::
    
 git clone https://github.com/jpetazzo/pipework.git
 
Then copy the script "pipework" to "/usr/bin/pipework" ::
   
 cp ./pipework/pipework /usr/bin/pipework 

The *pipework* is depended on "arping", so the package "iputils-arping" needed to be installed ::

 apt-get install iputils-arping

Docker instance management
--------------------------

After the dockerhost is ready, a docker instance can be managed through xCAT command. In xCAT, a docker instance is represented by a node whose definition can be like this: ::

 # lsdef host01c01
 Object name: host01c01
     dockerhost=host01:2375
     groups=docker,all
     ip=<x.x.x.x>
     mgt=docker
     postbootscripts=otherpkgs
     postscripts=syslog,remoteshell,syncfiles

The command :doc:`mkdef </guides/admin-guides/references/man1/mkdef.1>` or :doc:`chdef </guides/admin-guides/references/man1/chdef.1>` can be used to create a new docker instance node or change the node attributes.

Create docker instance
``````````````````````
::

 mkdocker <node> [image=<image_name>  [command=<command>] [dockerflag=<docker_flags>]]

* node - The node object which represent the docker instance
* image - The image name that the docker instance will use
* command - The command that the docker will run
* dockerflag - A JSON string which will be used as parameters to create a docker. Please reference `docker API v1.21 <https://docs.docker.com/engine/reference/api/docker_remote_api_v1.21/>`_ for more information about which parameters can be specified for "dockerflag".

To create the docker instance *host01c01* with image "ubuntu" and command "/bin/bash", you can use: ::
 
 mkdocker host01c01 image=ubuntu command=/bin/bash dockerflag="{\"AttachStdin\":true,\"AttachStdout\":true,\"AttachStderr\":true,\"OpenStdin\":true}"

**Note**: The *mkdocker* can not pull image automatically if the image specified is not exist on dockerhost. So please pull image manually with *docker pull <image>* in dockerhost before running *mkdocker*.  

Remove docker instance
``````````````````````
::

 rmdocker <node>

The command *rmdocker host01c01* can be used to remove the docker instance *host01c01*.

List docker information
```````````````````````
::

 lsdocker <dockerhost|node> [-l|--logs]

To list all the running docker instance on the dockerhost *host01*, please use *lsdocker host01*.

To list the info of docker instance "host01c01", please use *lsdocker host01c01*.

To get log info of docker instance "host01c01", please use *lsdocker host01c01 --logs*.

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

Configure docker instance IP address(Optional)
``````````````````````````````````````````````

Currently, the IP address set in *ip* attribute of the node can not be configured to the docker instance automatically. To do so, the following steps are needed:

* Create docker instance with network disabled

::

 mkdocker host01c01 image=ubuntu command=/bin/bash dockerflag="{\"AttachStdin\":true,\"AttachStdout\":true,\"AttachStderr\":true,\"OpenStdin\":true,\"NetworkDisabled\":true}"

* Configure ip for docker instance after it is started
 
 Please reference section "Setup docker instance network configuration tool on dockerhost" above to setup "pipework" on dockerhost before running the following command: 

::
 
 pipework mydocker0 host01c01 <instance_ip>/<netmask>@<gateway_ip>
