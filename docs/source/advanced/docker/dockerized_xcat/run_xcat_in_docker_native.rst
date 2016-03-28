Run xCAT in Docker with Docker native commands
==============================================


Pull the xCAT Docker image from DockerHub
-----------------------------------------

Now xCAT ships xCAT Docker images(x86_64 and ppc64le) on the `DockerHub <https://hub.docker.com/u/xcat/>`_:

To pull the xCAT 2.11 Docker for x86_64, run ::

    [root@dockerhost1 ~]# sudo docker pull xcat/xcat-ubuntu-x86_64:2.11        
    Using default tag: latest
    latest: Pulling from xcat/xcat-ubuntu-x86_64
    118aadd1f859: Already exists 
    41402770caf2: Already exists 
    a5051dd98acd: Already exists 
    a3ed95caeb02: Already exists 
    b084cef63fa6: Already exists 
    f993e0b41814: Already exists 
    70da11abb463: Already exists 
    ef43498c5fbc: Already exists 
    Digest: sha256:1dd0b80d4ff91ed9ddd11a3f16c10d33553cf2acf358f72575d9290596a89157
    Status: Image is up to date for xcat/xcat-ubuntu-x86_64:latest

On success, you will see the pulled Docker image on Docker host ::

     [root@dockerhost1 ~]# sudo docker images
     REPOSITORY                 TAG                 IMAGE ID            CREATED             VIRTUAL SIZE
     xcat/xcat-ubuntu-x86_64   latest              3a3631463e83        2 days ago          643 MB


An example configuration in the documentation
--------------------------------------------- 

To demonstrate the steps to run xCAT in a Docker container, take a cluster with the following configuration as an example ::

    Docker host: dockerhost1
    The network interface on the Docker host facing the compute nodes: eno1
    The IP address of eno1 on Docker host: 10.5.107.1/8
    The customized docker bridge: br0
    The name of the docker container running xCAT: xcatmn 
    The hostname of container xcatmn: xcatmn
    The IP address of container xcatmn: 10.5.107.101
    The dns domain of the cluster: clusters.com 


Create a customized Docker network on the Docker host
-----------------------------------------------------

**Docker Networks** provide complete isolation for containers, which gives you control over the networks your containers run on. To run xCAT in Docker, you should create a customized bridge network according to the cluster network plan, instead of using the default bridge network created on Docker installation. 

As an example, we create a customized bridge network "subnet1" which is attached to the network interface "eno1" facing the compute nodes and inherits the network configuration of "eno1". Since the commands to create the network will break the network connection on "eno1", you'd better run the commands in one line instead of running them seperatly ::   

    [root@dockerhost1 ~]# sudo docker network create --driver=bridge --gateway=10.5.107.1 --subnet=10.5.107.0/8 --ip-range=10.5.107.100/30 -o "com.docker.network.bridge.name"="br0" -o "com.docker.network.bridge.host_binding_ipv4"="10.5.107.1" subnet1;ip addr del dev eno1 10.5.107.1/8;brctl addif br0 eno1;ip link set br0 up

* ``--driver=bridge`` specify the network driver to be "bridge"
* ``--gateway=10.5.107.1`` specify the network gateway to be the IP address of "eno1" on Docker host
* ``--subnet=10.5.107.0/8`` speify the subnet in CIDR format to be the subnet of "eno1"
* ``--ip-range=10.5.107.100/30`` specify the sub-range to allocate container IP, this should be a segment of subnet specified with "--subnet"
* ``-o "com.docker.network.bridge.name"="br0" -o "com.docker.network.bridge.host_binding_ipv4"="10.5.107.1"`` specify the specific options for "bridge" driver. ``com.docker.network.bridge.name"="br0"`` specify the name of the bridge created to be "br0", ``"com.docker.network.bridge.host_binding_ipv4"="10.5.107.1"`` specify the IP address of the bridge "br0", which is the IP address of the network interface "eno1"  
* ``ip addr del dev eno1 10.5.107.1/8`` delete the IP address of "eno1"
* ``brctl addif br0 eno1`` attach the bridge "br0" to network interface "eno1"
* ``ip link set br0 up`` change the state of "br0" to UP

When the network is created, you can list it with ``sudo docker network ls`` and get the information of it with ``sudo docker inspect subnet1``.


Run xCAT in Docker container
----------------------------

Now run the xCAT Docker container with the Docker image "xcat/xcat-ubuntu-x86_64" and connect it to the newly created customized Docker network "subnet1" ::

    [root@dockerhost1 ~]# sudo docker run -it --privileged=true  --hostname=xcatmn --name=xcatmn --add-host="xcatmn.clusers.com xcatmn:10.5.107.101" --volume /docker/xcatdata/:/install --net=subnet1 --ip=10.5.107.101  xcat/xcat-ubuntu-x86_64

* use ``--privileged=true`` to give extended privileges to this container
* use ``--hostname`` to specify the hostname of the container, which is available inside the container
* use ``--name`` to assign a name to the container, this name can be used to manipulate the container on Docker host 
* use ``--add-host="xcatmn.clusers.com xcatmn:10.5.107.101"`` to write the ``/etc/hosts`` entries of Docker container inside container. Since xCAT use the FQDN(Fully Qualified Domain Name) to determine the cluster domain on startup, please make sure the format to be "<FQDN> <hostname>: <IP Address>", otherwise, you need to set the cluster domain with ``chdef -t site -o clustersite domain="clusters.com"`` inside the container manually
* use ``--volume /docker/xcatdata/:/install`` to mount a pre-created "/docker/xcatdata" directory on Docker host to "/install" directory inside container as a data volume. This is optional, it is mandatory if you want to backup and restore xCAT data.
* use ``--net=subnet1`` to connect the container to the Docker network "subnet1"
* use ``--ip=10.5.107.101`` to specify the IP address of the Docker container


