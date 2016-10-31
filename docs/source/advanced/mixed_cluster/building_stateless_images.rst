Building Stateless/Diskless Images
==================================

A **stateless**, or **diskless**, provisioned nodes is one where the operating system image is deployed and loaded into memory.  The Operating System (OS) does not store its files directly onto persistent storage (i.e hard disk drive, shared drive, usb, etc) and so subsequent rebooting of the machine results in loss of any state changes that happened while the machine was running.

To deploy stateless compute nodes, you must first create a stateless image.  The "netboot" osimages created from ``copycds`` in the **osimage** table are sample osimage definitions that can be used for deploying stateless nodes. 

In a homogeneous cluster, the management node is the same hardware architecture and running the same Operating System (OS) as the compute nodes, so ``genimage`` can directly be executed from the management node. 

The issues arises in a heterogeneous cluster, where the management node is running a different level operating system *or* hardware architecture as the compute nodes in which to deploy the image.  The ``genimage`` command that builds stateless images depends on various utilities provided by the base operating system and needs to be run on a node with the same hardware architecture and *major* Operating System release as the nodes that will be booted from the image. 

Same Operating System, Different Architecture
---------------------------------------------

The following describes creating stateless images of the same Operating System, but different hardware architecture.   The example will use the following nodes:  ::

        Management Node: xcatmn (ppc64)
        Target node:     n01 (x86_64)

#. On xCAT management node, ``xcatmn``, select the osimage you want to create from the list of osimage definitions.  To list out the osimage definitions: ::

        lsdef -t osimage 

#. **optional:** Create a copy of the osimage definition that you want to modify.  

   To take the sample ``rhels6.3-x86_64-netboot-compute`` osimage definition and create a copy called ``mycomputeimage``, run the following command: ::

	lsdef -t osimage -z rhels6.3-x86_64-netboot-compute | sed 's/^[^ ]\+:/mycomputeimage:/' | mkdef -z

#. To obtain the ``genimage`` command to execute on ``n01``, execute the ``genimage`` command with the ``--dryrun`` option: ::

	genimage --dryrun mycomputeimage
	
   The result output will look similar to the following: ::

	Generating image:
        cd /opt/xcat/share/xcat/netboot/rh;
        ./genimage -a x86_64 -o rhels6.3 -p compute --permission 755 --srcdir /install/rhels6.3/x86_64 --pkglist \
        /opt/xcat/share/xcat/netboot/rh/compute.rhels6.x86_64.pkglist --otherpkgdir /install/post/otherpkgs/rhels6.3/x86_64 --postinstall \
        /opt/xcat/share/xcat/netboot/rh/compute.rhels6.x86_64.postinstall --rootimgdir /install/netboot/rhels6.3/x86_64/compute mycomputeimage
 
          
#. Go to the target node, ``n01`` and run the following:

   #. mount the ``/install`` directory from the xCAT Management Node: ::
        
       mkdir /install
       mount -o soft xcatmn:/install /install
        
   #. Copy the executable files from the ``/opt/xcat/share/xcat/netboot`` from the xCAT Management node to the target node: ::

       mkdir -p /opt/xcat/share/xcat/
       scp -r xcatmn:/opt/xcat/share/xcat/netboot /opt/xcat/share/xcat/

#. Execute the ``genimage`` command obtained from the ``--dryrun``: ::

        cd /opt/xcat/share/xcat/netboot/rh;
        ./genimage -a x86_64 -o rhels6.3 -p compute --permission 755 --srcdir /install/rhels6.3/x86_64 --pkglist \
         /opt/xcat/share/xcat/netboot/rh/compute.rhels6.x86_64.pkglist --otherpkgdir /install/post/otherpkgs/rhels6.3/x86_64 --postinstall \
         /opt/xcat/share/xcat/netboot/rh/compute.rhels6.x86_64.postinstall --rootimgdir /install/netboot/rhels6.3/x86_64/compute mycomputeimage


   **If problems creating the stateless image, provide a local directory for --rootimgdir:** ::
  
        mkdir -p /tmp/compute

   Rerun ``genimage``, replacing ``--rootimgdir /tmp/compute``: ::

        cd /opt/xcat/share/xcat/netboot/rh;
        ./genimage -a x86_64 -o rhels6.3 -p compute --permission 755 --srcdir /install/rhels6.3/x86_64 --pkglist \
         /opt/xcat/share/xcat/netboot/rh/compute.rhels6.x86_64.pkglist --otherpkgdir /install/post/otherpkgs/rhels6.3/x86_64 --postinstall \
         /opt/xcat/share/xcat/netboot/rh/compute.rhels6.x86_64.postinstall --rootimgdir /tmp/compute mycomputeimage
 
   Then copy the contents from ``/tmp/compute`` to ``/install/netboot/rhels6.3/compute`` 


#. Now return to the management node and execute ``packimage`` on the osimage and continue provisioning the node ::

       packimage mycomputeimage
