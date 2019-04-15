Quick Start to Use xCAT Docker Image
====================================

Every time xCAT release a new version, xCAT will relase a xCAT docker image with legacy RPM/DEB packages at same time.
Using ``docker search xcat2`` to list all docker images xCAT has released. xCAT docker image offical organization is ``xcat``, repository is ``xcat2``. ::

    [dockerhost]# sudo docker search xCAT2
    NAME               DESCRIPTION                      STARS     OFFICIAL   AUTOMATED
    xcat/xcat2            ...                            ...        ...          ...

The xCAT docker images are tagged to match the xCAT releases, If you want to deploy the xCAT 2.14.6 version, pull down the ``xcat/xcat2:2.14.6`` image. Currently xCAT docker image was built based on CentOS.


Prerequisite
------------

To run xCAT under Docker, the services ``SELinux`` and ``AppArmor`` must be disabled

SELinux can be disabled with: ::

    echo 0 > /selinux/enforce
    sed -i 's/^SELINUX=.*$/SELINUX=disabled/' /etc/selinux/config

AppArmor can be disabled with: ::

    /etc/init.d/apparmor teardown

Pull the xCAT Docker Image from DockerHub
-----------------------------------------

To pull the latest xCAT docker image, run ::

    [dockerhost]# sudo docker pull xCAT/xCAT2:2.14.6


Run xCAT in Docker Container
----------------------------

Now run the xCAT docker container with the docker image ``xCAT/xCAT2:2.14.6`` ::

    [dockerhost]# sudo docker run  --rm -d \
         --name xcatmn  \
         --network=host  \
         --hostname xcatmn \
         --privileged   \
         -v /sys/fs/cgroup:/sys/fs/cgroup:ro  \
         -v /xCATdata:/tmp/xcatdata     \
         -v /var/log/xCAT:/var/log/xCAT  \
         -v /customer_data:/customer_data   \
         xCAT/xCAT2:2.14.6 cp -a /xcatdata /tmp


The descriptions:
 
:name:
     Assign a name to the container, this name can be used to manipulate the container on docker host.

:--network=host:
     Use the host network driver for a container, that container network stack is not isolated from the docker host.

:hostname:
    Specify the hostname of container, which is available inside the container.

:--privileged=true:
    Specify the hostname of container, which is available inside the container.

:-v /sys/fs/cgroup\:/sys/fs/cgroup\:ro:
    Is **mandatory** configuration to enable systemd in container.

:-v /xcatdata\:/tmp/xcatdata:
    xCAT container will create ``/xCATdata`` volume to store configuration and OS distro data. I.e. xCAT important directories ``/install``, ``/tftpboot`` and ``/etc`` will be saved under ``/xCATdata``. If user does not mount this directory to docker host specially, this directory will be mounted under ``/var/lib/docker/volumes/`` implicitly.

:-v /customer_data\:/customer_data:
    Is optional. If customer needs transfer user data between docker host ans docker container, can create this mount directory.

Run xCAT Command in Docker Container
------------------------------------

Now run the xCAT commands in docker container ::

    [dockerhost]# sudo docker exec -it xcatmn bash 
    [xcatmn]# 


Now container ``xcatmn`` will work as a normal xCAT management node, can run xCAT command directly.
For example ::

    [xcatmn]# lsxcatd -a
