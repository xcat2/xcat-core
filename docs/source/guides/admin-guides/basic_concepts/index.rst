Basic Concepts
==============

xCAT is not hard to use but you still need to learn some basic concepts of xCAT before starting to manage a real cluster.

* **xCAT Objects**

  The unit which can be managed in the xCAT is defined as an object. xCAT abstracts several types of objects from the cluster information to represent the physical or logical entities in the cluster. Each xCAT object has a set of attributes, each attribute is mapped from a specified field of a xCAT database table. The xCAT users can get cluster information and perform cluster management work through operations against the objects.

* **xCAT Database**

  All the data for the xCAT Objects (node, group, network, osimage, policy ... and global configuration) are stored in xCAT Database. Tens of tables are created as the back-end of xCAT Objects. Generally the data in the database is used by user through **xCAT Objects**. But xCAT also offers a bunch of commands to handle the database directly.

* **Global Configuration**

  xCAT has a bunch of **Global Configuration** for xCAT user to control the behaviors of xCAT. Some of the configuration items are mandatory for an xCAT cluster that you must set them correctly before starting to use xCAT.

* **xCAT Network**

  xCAT's goal is to manage and configure a significant number of servers remotely and automatically through a central management server. All the hardware discovery/management, OS deployment/configuration and application install/configuration are performed through network. You need to have a deep understand of how xCAT will use network before setting up a cluster.

**Get Into the Detail of the Cencepts:**

.. toctree::
   :maxdepth: 2

   xcat_object/index.rst
   xcat_db/index.rst
   global_cfg/index.rst
   network_planning/index.rst
   node_type.rst
