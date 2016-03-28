Run xCAT in Docker with Compose
===============================


An example configuration in the documentation
--------------------------------------------- 

To demonstrate the steps to run xCAT in a Docker container, take a cluster with the following configuration as an example ::

    The network interface on the Docker host facing the compute nodes: eno1
    The IP address of eno1 on Docker host: 10.5.107.1/8
    The IP address of container xcatmn: 10.5.107.101
    The dns domain of the cluster: clusters.com 

 
Install Compose on Docker host
------------------------------

Compose v1.7.0 or above should be installed on Docker host: ::

    curl -L https://github.com/docker/compose/releases/download/1.7.0-rc1/docker-compose-`uname -s`-`uname -m` > /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose


Customize docker-compose file 
-----------------------------

xCAT shippes a docker-compose template `docker-compose.yml <https://github.com/immarvin/xcat-docker/blob/master/docker-compose.yml>`_, which is a self-description file including all the configurations to run xCAT in container. You can make up your compose file based on it if you are familiar with `Compose file <https://docs.docker.com/compose/compose-file/>`_ , otherwise, you can simply customize it with the following steps: 
::

    image: [xCAT docker image name]:[tag]  
 
specify the name and tag of xCAT Docker image, for example "xcat/xcat-ubuntu-x86_64:2.11" 
:: 
    extra_hosts:
       - "xcatmn.[cluster domain name] xcatmn:[Container's IP address in provision network]"

specify the cluster domain name, fox example "clusters.com", and the IP address of container running xCAT Docker image, such as "10.0.0.101" 
::
    networks:

      hwmgtnet:
        ipv4_address : [Container's IP address in hardware management network]

      provnet:
        ipv4_address : [Container's IP address in provision network]  

specify the IP address of Docker container in hardware management network and provision network. Sometimes, the "hwmgtnet" is the same as "provnet", the "hwmgtnet" should be omitted by commented the 2 lines out
::

    networks:
      
      #provision network, attached to the network interface on Docker host 
      #facing the nodes to provision
      provnet:
        driver: "bridge"
        driver_opts: 
          com.docker.network.bridge.name: "provbr" 
        ipam: 
          config: 
            - subnet: [subnet of provbr in CIDR]
              gateway:[IP address of provbr]
        
      #hardware management network, attached to the network interface on
      #Docker host facing the bmc network
      hwmgtnet:
        driver: "bridge"
        driver_opts: 
          com.docker.network.bridge.name: "hwmgtbr" 
        ipam: 
          config: 
            - subnet: [subnet of hwmgtbr in CIDR]
              gateway: [IP address of hwmgtbr]
    
specify the network configuration of bridge networks "provnet" and "hwmgtnet", the network configuration of the bridge networks should be same as the network interfaces attached to the bridges. 
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
  
   docker-compose -f "docker-compose.yml" up -d; ifconfig eno1 0.0.0.0; brctl addif provbr eno1; ip link set provbr up;docker-compose logs -f

This command starts up the Docker container and attaches the network interface "eno1" of Docker host to the bridge network "provbr". It is a little complex due to a Compose bug `#1003 <https://github.com/docker/libnetwork/issues/1003>`_ . The commands should be run successively in one line to avoid breaking the network connection of the network interface of Docker host.

To remove the container, you can run ::

  docker-compose -f "docker-compose.yml" down;ifdown eno1;ifup eno1

To update the xCAT Docker image, you can run ::
  
  docker-compose -f "docker-compose.yml" pull


Known Issues
------------

.. [1] When you start up xCAT Docker container, you might see an error message at the end of the output like: ::
    
   "Couldn't connect to Docker daemon at http+unix://var/run/docker.sock - is it running?
   If it's at a non-standard location, specify the URL with the DOCKER_HOST environment variable."
please do not worry and just ignore it, the container has already been running. It is a Docker bug `#1214 <https://github.com/docker/compose/issues/1214>`_ 
   
