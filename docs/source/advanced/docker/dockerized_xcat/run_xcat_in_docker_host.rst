Quick start to use xcat docker image
===================================

From xcat 2.14.6, every time xCAT release a new version, xCAT will relase a xCAT docker image with legacy RPM/DEB packages at same time.
Using ``docker search xcat2`` to list all docker images xCAT has released. xCAT docker image offical organization is ``xcat``, repository is ``xcat2``. ::

    [dockerhost]# sudo docker search xcat2
    NAME               DESCRIPTION                      STARS     OFFICIAL   AUTOMATED
    xcat/xcat2            ...                            ...        ...          ...

xCAT docker images has tags which are the same with xCAT version. Take xcat 2.14.6 for example, the corresponding docker images is ``xcat/xcat2:2.14.6``. This docker image is universal for x86_64 and ppc64le.

Prerequisite
---------------------

The Docker host to run xCAT Docker image should be a baremental or virtual server with Docker installed. For the details on system requirements and Docker installation, refer to `Docker Installation Docs <https://docs.docker.com/engine/installation/>`_.

**[Note]**: If the SELinux or Apparmor on Docker host is enabled, the services/applications inside Docker Container might be confined. To run xCAT in Docker container, SELinux and Apparmor on the Docker host must be disabled.

SELinux can be disabled with: ::

    echo 0 > /selinux/enforce
    sed -i 's/^SELINUX=.*$/SELINUX=disabled/' /etc/selinux/config

AppArmor can be disabled with: ::

    /etc/init.d/apparmor teardown

Pull the xCAT Docker image from DockerHub
-----------------------------------------

To pull the latest xCAT Docker image, run ::

    [dockerhost]# sudo docker pull xcat/xcat2:2.14.6


Run xCAT in Docker container
----------------------------

Now run the xCAT Docker container with the Docker image ``xcat/xcat2:2.14.6`` ::

    [dockerhost]# sudo docker run -d \
         --name xcatmn  \
         --network=host  \
         --hostname xcatmn \
         --privileged   \
         -v /sys/fs/cgroup:/sys/fs/cgroup:ro  \
         -v /xcatdata:/xcatdata     \
         -v /var/log/xcat:/var/log/xcat  \
         -v /customer_data:/customer_data   \
         xcat/xcat2:2.14.6


The descriptions:

* ``name``: assign a name to the container, this name can be used to manipulate the container on Docker host. 
* ``--network=host``: use the host network driver for a container, that container network stack is not isolated from the Docker host.  
* ``hostname``: specify the hostname of container, which is available inside the container.
* ``--privileged=true``: give extended privileges to this container
* ``-v /sys/fs/cgroup:/sys/fs/cgroup:ro``: is **mandatory** configuration for ``xcat2:2.x.x``. 
* ``-v /xcatdata:/xcatdata``: xCAT container will create ``/xcatdata`` volume to store configuration and OS distro data. I.e. xcat important directories ``/install``, ``/tftpboot`` and ``/etc`` will be saved under ``/xcatdata``. If user does not mount this directory to docker host specially, this directory will be mounted under ``/var/lib/docker/volumes/`` implicitly.
* ``-v /var/log/xcat:/var/log/xcat``: all xcat running log will saved under ``/var/log/xcat``. If user does not mount this directory to docker host specially, this directory will be mounted under ``/var/lib/docker/volumes/`` implicitly.
* ``-v /customer_data:/customer_data``: is optional. If customer needs transfer user data between docker host ans docker container, can create this mount directory.
 
Run xCAT command in Docker container
------------------------------------

Now run the xCAT commands in Docker container ::

    [dockerhost]# sudo docker exec -it xcatmn bash 
    [xcatmn]# 



Now container ``xcatmn`` will work as a normal xcat management node, can run xcat command directly.
For example ::

    [xcatmn]# lsxcatd -a
