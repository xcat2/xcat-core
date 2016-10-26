Run xCAT in Docker with Docker native commands
==============================================


Pull the xCAT Docker image from DockerHub
-----------------------------------------

Now xCAT ships xCAT Docker images(x86_64 and ppc64le) on the `DockerHub <https://hub.docker.com/u/xcat/>`_:

To pull the latest xCAT Docker image for x86_64, run ::

    sudo docker pull xcat/xcat-ubuntu-x86_64        

On success, you will see the pulled Docker image on Docker host ::

     [root@dockerhost1 ~]# sudo docker images
     REPOSITORY                 TAG                 IMAGE ID            CREATED             VIRTUAL SIZE
     xcat/xcat-ubuntu-x86_64   latest              3a3631463e83        2 days ago          643 MB


An example configuration in the documentation
--------------------------------------------- 

To demonstrate the steps to run xCAT in a Docker container, take a cluster with the following configuration as an example ::

    Docker host: dockerhost1
    The name of the docker container running xCAT: xcatmn 
    The hostname of container xcatmn: xcatmn

    The management network object: mgtnet
    The network bridge of management network on Docker host: mgtbr
    The management network interface on the Docker host facing the compute nodes: eno1
    The IP address of eno1 on Docker host: 10.5.107.1/8
    The IP address of xCAT container in management network: 10.5.107.101

    The dns domain of the cluster: clusters.com 


Create a customized Docker network on the Docker host
-----------------------------------------------------

**Docker Networks** provide complete isolation for containers, which gives you control over the networks your containers run on. To run xCAT in Docker, you should create a customized bridge network according to the cluster network plan, instead of using the default bridge network created on Docker installation. 

As an example, we create a customized bridge network "mgtbr" which is attached to the network interface "eno1" facing the compute nodes and inherits the network configuration of "eno1". Since the commands to create the network will break the network connection on "eno1", you'd better run the commands in one line instead of running them seperatly ::   

    sudo docker network create --driver=bridge --gateway=10.5.107.1 --subnet=10.5.107.0/8 -o "com.docker.network.bridge.name"="mgtbr" mgtnet; \
    ifconfig eno1 0.0.0.0; \
    brctl addif mgtbr eno1; \
    ip link set mgtbr up

* ``--driver=bridge`` specify the network driver to be "bridge"
* ``--gateway=10.5.107.1`` specify the network gateway to be the IP address of "eno1" on Docker host. which will also be the IP address of network bridge "mgtbr"
* ``--subnet=10.5.107.0/8`` speify the subnet in CIDR format to be the subnet of "eno1"
* ``com.docker.network.bridge.name"="mgtbr"`` specify the bridge name of management network 
* ``ifconfig eno1 0.0.0.0`` delete the IP address of "eno1"
* ``brctl addif mgtbr eno1`` attach the bridge "br0" to network interface "eno1"
* ``ip link set mgtbr up`` change the state of "br0" to UP

When the network is created, you can list it with ``sudo docker network ls`` and get the information of it with ``sudo docker inspect mgtnet``.


Run xCAT in Docker container
----------------------------

Now run the xCAT Docker container with the Docker image "xcat/xcat-ubuntu-x86_64" and connect it to the newly created customized Docker network "mgtnet" ::

    sudo docker run -it --privileged=true  --hostname=xcatmn --name=xcatmn --add-host="xcatmn.clusers.com xcatmn:10.5.107.101" --volume /docker/xcatdata/:/install --net=mgtnet --ip=10.5.107.101  xcat/xcat-ubuntu-x86_64

* use ``--privileged=true`` to give extended privileges to this container
* use ``--hostname`` to specify the hostname of the container, which is available inside the container
* use ``--name`` to assign a name to the container, this name can be used to manipulate the container on Docker host 
* use ``--add-host="xcatmn.clusers.com xcatmn:10.5.107.101"`` to write the ``/etc/hosts`` entries of Docker container inside container. Since xCAT use the FQDN(Fully Qualified Domain Name) to determine the cluster domain on startup, make sure the format to be "<FQDN> <hostname>: <IP Address>", otherwise, you need to set the cluster domain with ``chdef -t site -o clustersite domain="clusters.com"`` inside the container manually
* use ``--volume /docker/xcatdata/:/install`` to mount a pre-created "/docker/xcatdata" directory on Docker host to "/install" directory inside container as a data volume. This is optional, it is mandatory if you want to backup and restore xCAT data.
* use ``--net=mgtnet`` to connect the container to the Docker network "mgtnet"
* use ``--ip=10.5.107.101`` to specify the IP address of the xCAT Docker container


