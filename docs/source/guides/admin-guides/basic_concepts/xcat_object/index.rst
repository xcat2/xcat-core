xCAT Objects
============

Basically, xCAT has 20 types of objects. They are: ::

    auditlog    boottarget    eventlog    firmware        group
    kit         kitcomponent  kitrepo     monitoring      network
    node        notification  osdistro    osdistroupdate  osimage
    policy      rack          route       site            zone

This section will introduce you to several important types of objects and give you an overview of how to view and manipulate them.

You can get the detail description of each object by ``man <object type>`` e.g. ``man node``.

* **node Object**

  The **node** is the most important object in xCAT. Any physical server, virtual machine or SP (Service Processor for Hardware Control) can be defined as a node object. 

  For example, I have a physical server which has the following attributes: ::

    groups: all,x86_64 
        The groups that this node belongs to.
    arch: x86_64 
        The architecture of the server is x86_64.
    bmc: 10.4.14.254 
        The IP of BMC which will be used for hardware control.
    bmcusername: ADMIN 
        The username of bmc.
    bmcpassword: admin
        The password of bmc.
    mac: 6C:AE:8B:1B:E8:52
        The mac address of the ethernet adapter that will be used to 
        deploy OS for the node.
    mgt: ipmi
        The management method which will be used to manage the node. 
        This node will use ipmi protocol.
    netboot: xnba
        The network bootloader that will be used to deploy OS for the node.
    provmethod: rhels7.1-x86_64-install-compute
        The osimage that will be deployed to the node.

  I want to name the node to be **cn1** (Compute Node #1) in xCAT. Then I define this node in xCAT with following command: ::

    $mkdef -t node cn1 groups=all,x86_64 arch=x86_64 bmc=10.4.14.254 
                       bmcusername=ADMIN bmcpassword=admin mac=6C:AE:8B:1B:E8:52 
                       mgt=ipmi netboot=xnba provmethod=rhels7.1-x86_64-install-compute

  After the define, I can use ``lsdef`` command to display the defined node: ::

    $lsdef cn1
    Object name: cn1
        arch=x86_64
        bmc=10.4.14.254
        bmcpassword=admin
        bmcusername=ADMIN
        groups=all,x86_64
        mac=6C:AE:8B:1B:E8:52
        mgt=ipmi
        netboot=xnba
        postbootscripts=otherpkgs
        postscripts=syslog,remoteshell,syncfiles
        provmethod=rhels7.1-x86_64-install-compute

  Then I can try to remotely **power on** the node **cn1**: ::

    $rpower cn1 on

* **group Object**

  **group** is an object which includes multiple **node object**. When you set **group** attribute for a **node object** to a group name like **x86_64**, the group **x86_64** is automatically generated and the node is assigned to the group.

  The benefits of using **group object**:

  * **Handle multiple nodes through group**

    I defined another server **cn2** which is similar with **cn1**, then my group **x86_64** has two nodes: **cn1** and **cn2**. ::

      $ lsdef -t group x86_64
      Object name: x86_64
        cons=ipmi
        members=cn1,cn2

    Then I can power on all the nodes in the group **x86_64**. ::

      $ rpower x86_64 on

  * **Inherit attributes from group**

    If the **group object** of **node object** has certain attribute that **node object** does not have, the node will inherit this attribute from its **group**.

    I set the **cons** attribute for the **group object x86_64**. ::

      $ chdef -t group x86_64 cons=ipmi
        1 object definitions have been created or modified.

      $ lsdef -t group x86_64
      Object name: x86_64
         cons=ipmi
         members=cn1,cn2

    The I can see the **cn1** inherits the attribute **cons** from the group **x86_64**: ::

      $ lsdef cn1
      Object name: cn1
          arch=x86_64
          bmc=10.4.14.254
          bmcpassword=admin
          bmcusername=ADMIN
          cons=ipmi
          groups=all,x86_64
          mac=6C:AE:8B:1B:E8:52
          mgt=ipmi
          netboot=xnba
          postbootscripts=otherpkgs
          postscripts=syslog,remoteshell,syncfiles
          provmethod=rhels7.1-x86_64-install-compute

    It is useful to define common attributes in **group object** so that newly added node will inherit them automatically. Since the attributes are defined in the **group object**, you don't need to touch the individual nodes attributes.

  * **Use Regular Expression to generate value for node attributes**

    This is powerful feature in xCAT that you can generate individual attribute value from node name instead of assigning them one by one. Refer to :doc:`Use Regular Expression in xCAT Database Table <../xcat_db/regexp_db>`.

* **osimage Object**

  An **osimage** object represents an Operating System which can be deployed in xCAT. xCAT always generates several default **osimage** objects for certain Operating System when executing ``copycds`` command to generate the package repository for the OS.

  You can display all the defined **osimage** object: ::

    $ lsdef -t osimage

  Display the detail attributes of one **osimage** named **rhels7.1-x86_64-install-compute**: ::

    $ lsdef -t osimage rhels7.1-x86_64-install-compute  
    Object name: rhels7.1-x86_64-install-compute        
        imagetype=linux                                 
        osarch=x86_64                                   
        osdistroname=rhels7.1-x86_64                    
        osname=Linux                                    
        osvers=rhels7.1                                 
        otherpkgdir=/install/post/otherpkgs/rhels7.1/x86_64
        pkgdir=/install/rhels7.1/x86_64                 
        pkglist=/opt/xcat/share/xcat/install/rh/compute.rhels7.pkglist
        profile=compute                                 
        provmethod=install                              
        synclists=/root/syncfiles.list                  
        template=/opt/xcat/share/xcat/install/rh/compute.rhels7.tmpl

  This **osimage** represents a **Linux** **rhels7.1** Operating System. The package repository is in **/install/rhels7.1/x86_64** and the packages which will be installed is listed in the file **/opt/xcat/share/xcat/install/rh/compute.rhels7.pkglist** ...

  I can bind the **osimage** to **node** when I want to deploy **osimage rhels7.1-x86_64-install-compute** on my **node cn1**: ::

    $ nodeset cn1 osimage=rhels7.1-x86_64-install-compute

  Then in the next network boot, the node **cn1** will start to deploy **rhles7.1**.

* **Manipulating Objects**

  You already saw that I used the commands ``mkdef``, ``lsdef``, ``chdef`` to manipulate the objects. xCAT has 4 objects management commands to manage all the xCAT objects.

  * ``mkdef`` : create object definitions
  * ``chdef`` : modify object definitions
  * ``lsdef`` : list object definitions
  * ``rmdef`` : remove object definitions 

  To get the detail usage of the commands, refer to the man page. e.g. ``man mkdef``

**Get Into the Detail of the xCAT Objects:**

.. toctree::
   :maxdepth: 2

   node.rst
   group.rst
   osimage.rst

