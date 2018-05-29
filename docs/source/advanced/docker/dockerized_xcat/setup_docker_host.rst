Setup Docker host
=================

Install Docker Engine
---------------------

The Docker host to run xCAT Docker image should be a baremental or virtual server with Docker v1.10 or above installed. For the details on system requirements and Docker installation, refer to `Docker Installation Docs <https://docs.docker.com/engine/installation/>`_. 

.. note:: Docker images can only run on Docker hosts with the same architecture.  Since xCAT only ships x86_64 and ppc64le Docker images, running xCAT in Docker requires x86_64 or ppc64 Docker Hosts.

Shutdown the SELinux/Apparmor on Docker host
--------------------------------------------

If the SELinux or Apparmor on Docker host is enabled, the services/applications inside Docker Container might be confined. To run xCAT in Docker container, SELinux and Apparmor on the Docker host must be disabled. 

SELinux can be disabled with: ::

    echo 0 > /selinux/enforce
    sed -i 's/^SELINUX=.*$/SELINUX=disabled/' /etc/selinux/config

AppArmor can be disabled with: ::

    /etc/init.d/apparmor teardown


