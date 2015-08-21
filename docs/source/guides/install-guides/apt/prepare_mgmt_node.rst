Prepare the Management Node
===========================

These steps prepare the Management Node or xCAT Installation

Install an OS on the Management Node
------------------------------------

Install one of the supported operating systems :ref:`ubuntu-os-support-label` on to your target management node

  .. include:: ../common/install_guide.rst
     :start-after: BEGIN_install_os_mgmt_node
     :end-before: END_install_os_mgmt_node

Configure the Base OS Repository
--------------------------------

**TODO**

Set up Network
--------------

The management node IP address should be set to a **static** ip address.  

Modify the ``ifcfg-<nic>`` file under ``/etc/sysconfig/network-scripts`` and configure a static IP address.

