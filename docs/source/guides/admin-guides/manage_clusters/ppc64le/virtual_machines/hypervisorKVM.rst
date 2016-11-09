Install and Configure Hypervisor
================================

Provision Hypervisor
--------------------

**[PowerKVM]**
``````````````

   .. include:: pKVMHypervisor.rst

**[RHEV]**
``````````

   .. include:: RHEVHypervisor.rst

#. Customize the hypervisor node definition to create network bridge

   xCAT ships a postscript **xHRM** to create a network bridge on kvm host during installation/netbooting. Specify the **xHRM** with appropriate parameters in  **postscripts** attibute. For example:

   * To create a bridge named 'br0' against the installation network device specified by **installnic**: ::

        chdef kvmhost1 -p postscripts="xHRM bridgeprereq br0"

   * To create a bridge with default name 'default' against the installation network device specified by **installnic**: ::

        chdef kvmhost1 -p postscripts="xHRM bridgeprereq"

   * To create a bridge named 'br0' against the network device 'eth0': ::

        chdef kvmhost1 -p postscripts="xHRM bridgeprereq eth0:br0"

   **Note**: The network bridge name you use should not be the virtual bridges (vbrX) created by libvirt installation  [1]_. 


#. Customize the hypervisor node definition to mount the shared kvm storage directory on management node **(optional)**

   If the shared kvm storage directory on the management node has been exported, it can be mounted on PowerKVM hypervisor for virtual machines hosting. 

   An easy way to do this is to create another postscript named "mountvms" which creates a directory **/install/vms** on hypervisor and then mounts **/install/vms** from the management node, the content of "mountvms" can be: ::

     logger -t xcat "Install: setting vms mount in fstab"
     mkdir -p /install/vms
     echo "$MASTER:/install/vms /install/vms nfs \
           rsize=8192,wsize=8192,timeo=14,intr,nfsvers=2 1 2" >> /etc/fstab


   Then set the file permission and specify the script in **postscripts** attribute of hypervisor node definition: ::

     chmod 755 /install/postscripts/mountvms
     chdef kvmhost1 -p postscripts=mountvms

#. Provision the hypervisor node with the osimage ::

    nodeset kvmhost1 osimage=<osimage_name>
    rpower kvmhost1 boot


Create network bridge on hypervisor 
------------------------------------

To launch VMs, a network bridge must be created on the KVM hypervisor. 

If the hypervisor is provisioned successfully according to the steps described above, a network bridge will be created and attached to a physical interface. This can be checked by running ``brctl show`` on the hypervisor to show the network bridge information, please make sure a network bridge has been created and configured according to the parameters passed to postscript "xHRM" ::

   # brctl show
   bridge name     bridge id               STP enabled     interfaces
   br0             8000.000000000000       no              eth0


If the network bridge is not created or configured successfully, run "xHRM" with **updatenode** on managememt node to create it manually:::

   updatenode kvmhost1  -P "xHRM bridgeprereq eth0:br0"

Start libvirtd service
----------------------

Verify **libvirtd** service is running: ::

   systemctl status libvirtd

If service is not running, it can be started with: ::

   systemctl start libvirtd

.. [1] Every standard libvirt installation provides NAT based connectivity to virtual machines out of the box using the "virtual bridge" interfaces (virbr0, virbr1, etc)  Those will be created by default.

