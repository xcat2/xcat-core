Run xCAT in Docker with Compose (Recommended)
=============================================


An example configuration in the documentation
--------------------------------------------- 

To demonstrate the steps to run xCAT in a Docker container, take a cluster with the following configuration as an example ::


    The name of the docker container running xCAT: xcatmn 
    The hostname of container xcatmn: xcatmn
    The dns domain of the cluster: clusters.com 

    The management network object: mgtnet
    The network bridge of management network on Docker host: mgtbr
    The management network interface on the Docker host facing the compute nodes: eno1
    The IP address of eno1 on Docker host: 10.5.107.1/8
    The IP address of xCAT container in management network: 10.5.107.101

    The service network object: svcnet
    The network bridge of service network on Docker host: svcbr
    The service network interface on the Docker host facing the hardware control points: eno2
    The IP address of eno2 on Docker host: 192.168.0.1/8
    The IP address of xCAT container in service network: 192.168.0.101

 
Install Compose on Docker host
------------------------------

Compose v1.7.0 or above should be installed on Docker host: ::

    curl -L https://github.com/docker/compose/releases/download/1.7.0-rc1/docker-compose-`uname -s`-`uname -m` > /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose


Customize docker-compose file 
-----------------------------

xCAT ships a docker-compose template `docker-compose.yml <https://github.com/immarvin/xcat-docker/blob/master/docker-compose.yml>`_, which is a self-description file including all the configurations to run xCAT in container. You can make up your compose file based on it if you are familiar with `Compose file <https://docs.docker.com/compose/compose-file/>`_ , otherwise, you can simply customize it with the following steps: 

1. Specify the xCAT Docker image

::

    image: [xCAT Docker image name]:[tag]  
 
specify the name and tag of xCAT Docker image, for example "xcat/xcat-ubuntu-x86_64:2.11" 

2. Specify the cluster domain name 

:: 

    extra_hosts:
       - "xcatmn.[cluster domain name] xcatmn:[Container's IP address in management network]"

specify the cluster domain name,i.e, "site.domain" on xCAT Management Node, for example "clusters.com", and the IP address of xCAT Docker container in the management network, such as "10.5.107.101" 

3. Specify the IP address of xCAT container in service network and management network

::

    networks:

      svcnet:
        ipv4_address : [Container's IP address in service network]

      mgtnet:
        ipv4_address : [Container's IP address in management network]  

specify the IP address of Docker container in service network and management network. If the "svcnet" is the same as "mgtnet", the 2 "svcnet" lines should be commented out.

4. Specify the Docker network objects for management network and service network

::

    networks:
      
      #management network, attached to the network interface on Docker host 
      #facing the nodes to provision
      mgtnet:
        driver: "bridge"
        driver_opts: 
          com.docker.network.bridge.name: "mgtbr" 
        ipam: 
          config: 
            - subnet: [subnet of mgtbr in CIDR]
              gateway:[IP address of mgtbr]
        
      #service network, attached to the network interface on
      #Docker host facing the bmc network
      svcnet:
        driver: "bridge"
        driver_opts: 
          com.docker.network.bridge.name: "svcbr" 
        ipam: 
          config: 
            - subnet: [subnet of svcbr in CIDR]
              gateway: [IP address of svcbr]
    
specify the network configuration of bridge networks "mgtnet" and "svcnet", the network configuration of the bridge networks should be same as the network interfaces attached to the bridges. The "mgtnet" and "svcnet" might the same network in some cluster, in this case, you can ignore the lines for "svcnet".  

5. Specify the Data Volumes for xCAT Docker container

::

    volumes:
      #the "/install" volume is used to keep user data in xCAT,
      #such as osimage resources
      #the user data can be accessible if specified
      - [The directory on Docker host mounted to "/install" inside container]:/install
      #the "/.dbbackup" volume is used to backup and restore xCAT DB tables
      #Dockerized xCAT will restore xCAT DB tables if specified
      #"dumpxCATdb -p /.dbbackup" should be run manually to save xCAT DB inside container
      - [The directory on Docker host mounted to save xCAT DB inside container]:/.dbbackup
      #the "/.logs" value is used to keep xCAT logs
      #the xCAT logs will be kept if specified 
      - [The directory on Docker host to save xCAT logs inside container]:/var/log/xcat/

specify the volumes of the xCAT container used to save and restore xCAT data


Start xCAT Docker container with Compose 
----------------------------------------
After the "docker-compose.yml" is ready, the xCAT Docker container can be started with [1]_ ::
  
   docker-compose -f "docker-compose.yml" up -d; \
   ifconfig eno1 0.0.0.0; \
   brctl addif mgtbr eno1; \
   ip link set mgtbr up; \
   docker-compose logs -f

This command starts up the Docker container and attaches the network interface "eno1" of Docker host to the bridge network "mgtbr". It is a little complex due to a Compose bug `#1003 <https://github.com/docker/libnetwork/issues/1003>`_ . The commands should be run successively in one line to avoid breaking the network connection of the network interface of Docker host.

To remove the container, you can run ::

  docker-compose -f "docker-compose.yml" down; \
  ifdown eno1; \
  ifup eno1

To update the xCAT Docker image, you can run ::
  
  docker-compose -f "docker-compose.yml" pull


Known Issues
------------

.. [1]

When you start up xCAT Docker container, you might see an error message at the end of the output like ::

  Couldn't connect to Docker daemon at http+unix://var/run/docker.sock - is it running? If it's at a non-standard location, specify the URL with the DOCKER_HOST environment variable.
   
You can ignore it, the container has already been running. It is a Docker bug `#1214 <https://github.com/docker/compose/issues/1214>`_
   
