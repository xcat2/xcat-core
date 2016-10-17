Setup Hypervisor
================


Provision Hypervisor
--------------------


Follow the :ref:`Diskful Installation <diskful_installation>` to provision kvm hypervisor for PowerKVM or RHEV.

 
* **[PowerKVM]**

   Obtain a PowerKVM iso and create PowerKVM osimages with it: :: 

     copycds ibm-powerkvm-3.1.0.0-39.0-ppc64le-gold-201511041419.iso
    
   The following PowerKVM osimage will be created ::
     
     # lsdef -t osimage -o pkvm3.1-ppc64le-install-compute
     Object name: pkvm3.1-ppc64le-install-compute
         imagetype=linux
         osarch=ppc64le
         osdistroname=pkvm3.1-ppc64le
         osname=Linux
         osvers=pkvm3.1
         otherpkgdir=/install/post/otherpkgs/pkvm3.1/ppc64le
         pkgdir=/install/pkvm3.1/ppc64le
         profile=compute
         provmethod=install
         template=/opt/xcat/share/xcat/install/pkvm/compute.pkvm3.ppc64le.tmpl

* **[RHEV]**

   At the time of this writing there is no ISO image availabe for RHEV. Individual RPM packages need to be downloaded.

   * Download *Management-Agent-Power-7* and *Power_Tools-7* RPMs from RedHat to the xCAT management node. Steps below assume all RPMs were downloaded to */install/post/otherpkgs/rhels7.3/ppc64le/RHEV4/4.0-GA* directory.

   * Run ``createrepo .`` in the */install/post/otherpkgs/rhels7.3/ppc64le/RHEV4/4.0-GA* directory.

   * Create new osimage definition based on an existing RH7 osimage definition ::

      mkdef -t osimage -o rhels7.3-ppc64le-RHEV4-install-compute --template rhels7.3-ppc64le-install-compute
   * Modify ``otherpkgdir`` attribute to point to the package directory with downloaded RPMs ::

      chdef -t osimage rhels7.3-ppc64le-RHEV4-install-compute otherpkgdir=/install/post/otherpkgs/rhels7.3/ppc64le/RHEV4/4.0-GA

   * Create a new file */opt/xcat/share/xcat/install/rh/other.pkglist* to list required packages ::

      libvirt 
      qemu-kvm-rhev 
      qemu-kvm-tools-rhev 
      virt-manager-common 
      virt-install

   * Modify ``otherpkglist`` attribute to point to the file from the step above ::

      chdef -t osimage rhels7.3-snap3-ppc64le-RHEV4-install-compute otherpkglist=/opt/xcat/share/xcat/install/rh/other.pkglist

   * The RHEV osimage should look similar to: ::

      Object name: rhels7.3-ppc64le-RHEV4-install-compute
          imagetype=linux
          osarch=ppc64le
          osdistroname=rhels7.3-ppc64le
          osname=Linux
          osvers=rhels7.3
          otherpkgdir=/install/post/otherpkgs/rhels7.3/ppc64le/RHEV4/4.0-GA
          otherpkglist=/opt/xcat/share/xcat/install/rh/other.pkglist
          pkgdir=/install/rhels7.3/ppc64le
          pkglist=/install/custom/install/rh/compute.rhels7.ppc64le.pkglist
          profile=compute
          provmethod=install
          template=/opt/xcat/share/xcat/install/rh/compute.rhels7.tmpl

#. Customize the hypervisor node definition to create network bridge

   xCAT ships a postscript **xHRM** to create a network bridge on kvm host during installation/netbooting. Specify the **xHRM** with appropriate parameters in  **postscripts** attibute. Here is some examples on this:

   To create a bridge with default name 'default' against the installation network device which was specified by **installnic** attribute ::

     chdef kvmhost1 -p postscripts="xHRM bridgeprereq"

   To create a bridge named 'br0' against the installation network device which was specified by **installnic** attribute(recommended) ::

     chdef kvmhost1 -p postscripts="xHRM bridgeprereq br0"

   To create a bridge named 'br0' against the network device 'eth0' ::

     chdef kvmhost1 -p postscripts="xHRM bridgeprereq eth0:br0"

   **Note**: The network bridge name you use should not be the virtual bridges created by libvirt installation  [1]_. 


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

