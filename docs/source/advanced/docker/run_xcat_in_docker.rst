Run xCAT in Docker Container
============================

`Docker <https://www.docker.com/>`_ is a popular application containment environment. With Docker, applications/Services are shipped as **Docker images** and run in **Docker containers**. **Docker containers** include the application and all of its dependencies, but share the kernel with other containers. They run as an isolated process in userspace on the host operating system. The server on which  **Docker containers** run is called **Docker host**.

When running xCAT in Docker container, you do not have to worry about the xCAT installation and configuration on different OS and hardware platforms, just focus on the cluster management work with xCAT.


Prerequisite: setup Docker host
--------------------------------

You can select a baremental or virtual server with the Docker installed as a Docker host. For the details on system requirements and Docker installation, please refer to `Docker Docs <https://docs.docker.com/>`_. 

**Note:** 

1. **Docker image** can only run on the **Docker host** with the same architecture. Since xCAT currently only ships x86_64 and ppc64le Docker images, running xCAT in Docker requires x86_64 or ppc64le **Docker hosts**.

2. **Docker v1.10** introduces significant enhancements and changes from previous releases, please make sure the Docker release installed on Docker host is newer than Docker v1.10.


Shutdown the SELinux/Apparmor on Docker host
--------------------------------------------

If the SELinux or Apparmor on Docker host is enabled, the services/applications inside Docker Container might be confined. To run xCAT in Docker container, SELinux and Apparmor on the Docker host must be disabled. 

SELinux can be disabled with: ::

    echo 0 > /selinux/enforce
    sed -i 's/^SELINUX=.*$/SELINUX=disabled/' /etc/selinux/config

AppArmor can be disabled with: ::

    /etc/init.d/apparmor teardown


Pull the xCAT Docker image from DockerHub:
------------------------------------------

Now xCAT ships xCAT 2.11 Docker images(x86_64 and ppc64le) on the `DockerHub <https://hub.docker.com/u/xcat/>`_:

To pull the xCAT 2.11 Docker for x86_64, run ::

    [root@dockerhost1 ~]# sudo docker pull xcat/xcat-ubuntu-x86_64        
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


Play with xCAT
--------------

Once xCAT Docker container is run, you can use xCAT with the shell inside the container. Since the ssh service has also been enabled on the Docker container startup, you can also connect to the container via ssh, the default password for the user "root" is "cluster".

Once you attach or ssh to the container, you will find that xCAT is running and configured, you can play with xCAT and manage your cluster now. 

Currently, since xCAT can only generate the diskless osimages of Linux distributions with the same OS version and architecture with xCAT MN. If you need to provision diskless osimages besides ubuntu x86_64 with xCAT running in the Docker, you can use ``imgexport`` and ``imgimport`` to import the diskless osimages generated before.

Save and Restore xCAT data 
----------------------------

It is not recommended to save data in Docker image. "/install" directory inside Docker container is the right place to backup xCAT DB tables, save osimage resource files and other user data. 

You can specify a directory on the Docker host as a data volume for the "/install" directory inside container. xCAT will preserve several directories under "/install" for special use:

* save the osimage resources under "/install"
* save xCAT logs under "/install/.logs" directory 
* create a directory "/install/.dbbackup" as the place to save and restore xCAT DB tables. You can save the xCAT DB tables with ``dumpxCATdb -p /install/.dbbackup/`` and xCAT will restore the tables on the container start up.

