Quick Start to Use xCAT Docker Image
====================================

A new Docker image will be published for each new release of xCAT. Use ``docker search xcat2`` to list all Docker images xCAT has released. xCAT Docker image offical organization is ``xcat``, repository is ``xcat2``. ::

    [dockerhost]# sudo docker search xcat2 
    NAME               DESCRIPTION                      STARS     OFFICIAL   AUTOMATED
    xcat/xcat2            ...                            ...        ...          ...

The xCAT Docker images are tagged to match the xCAT releases, If you want to deploy the xCAT 2.14.6 version, pull down the ``xcat/xcat2:2.14.6`` image. xCAT Docker image also has a ``latest`` tag to point to the latest release. Currently xCAT Docker images are based on CentOS.

.. Attention::
    To do discovery for POWER9 bare metal server, please refer to :doc:`xCAT Genesis Base </references/coral/known_issues/genesis_base>`

Prerequisite for Docker Host
----------------------------

* To run xCAT under Docker, the services ``SELinux`` and ``AppArmor`` on Docker host must be disabled.

  SELinux can be disabled with: ::

    echo 0 > /selinux/enforce
    sed -i 's/^SELINUX=.*$/SELINUX=disabled/' /etc/selinux/config

  AppArmor can be disabled with: ::

    /etc/init.d/apparmor teardown


* To run xCAT under Docker the ports described in :doc:`document </advanced/ports/xcat_ports>` should be available. 

  For Linux user, use the following command to verify ports are not used :: 

    netstat -nlp |grep -E ":(3001|3002|68|53|873|80|69|12429|12430|67) "

   
Pull the xCAT Docker Image from DockerHub
-----------------------------------------

To pull the latest xCAT Docker image, run ::

    [dockerhost]# sudo docker pull xcat/xcat2:latest


Run xCAT in Docker Container
----------------------------

Run the xCAT Docker container with the Docker image ``xCAT/xCAT2:latest`` ::


    [dockerhost]# sudo docker run -d \
         --name xcatmn  \
         --network=host  \
         --hostname xcatmn \
         --privileged   \
         -v /sys/fs/cgroup:/sys/fs/cgroup:ro  \
         -v /xcatdata:/xcatdata     \
         -v /var/log/xcat:/var/log/xcat  \
         -v /customer_data:/customer_data   \
         xcat/xcat2:latest


The descriptions:
 
:name:
     Assign a name to the container, this name can be used to manipulate the container on docker host.

:--network=host:
     Use the host network driver for a container, that container network stack is not isolated from the docker host.

:hostname:
    Specify the hostname of container, which is available inside the container.

:--privileged=true:
    Give extended privileges to this container.

:-v /sys/fs/cgroup\:/sys/fs/cgroup\:ro:
    Is **mandatory** configuration to enable systemd in container.

:-v /xcatdata\:/xcatdata:
    xCAT container will create ``/xcatdata`` volume to store configuration and OS distro data. I.e. xCAT important directories ``/install``, ``/tftpboot`` and ``/etc`` will be saved under ``/xcatdata``. If user does not explicitly mount this directory to docker host, this directory will be mounted under ``/var/lib/docker/volumes/``.  

:-v /var/log/xcat\:/var/log/xcat:
   All xCAT running logs are saved under ``/var/log/xcat``. Use this setting to export them to Docker host.

:-v /customer_data\:/customer_data:
    **Is optional**. Use this setting to transfer user data between Docker host and container.

Run xCAT Command in Docker Container
------------------------------------

To enter xCAT Docker container ::

    [dockerhost]# sudo docker exec -it xcatmn bash 
    [xcatmn]# 

Also can enter xCAT Docker container through ``ssh`` ::

    [anynode]# ssh <docker_container_ip> -p 2200

.. Attention::
    Need to set ``site`` table depending on your own environment. 

For example ::

    [xcatmn]# chtab key=master site.value=<docker_host_ip>
 

Now container ``xcatmn`` will work as a normal xCAT management node, can run xCAT commands directly.
For example ::

    [xcatmn]# lsxcatd -a

.. Attention::
    Use of NFS outside of xCAT Docker container is recommended. For NFS service set up inside of xCAT Docker container, mount the shared directory with ``-v`` option when starting xCAT container.
    
