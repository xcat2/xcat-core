Manage Virtual Machine (VMs)
============================

Create the Virtual Machine
----------------------

In this doc, we assume the powerKVM hypervisor host node001 is ready to use.

Create VM Node Definition
^^^^^^^^^^^^^^^^^^^^^^^^^

Define virtual machine vm1, add it to xCAT under the vm group, its ip is x.x.x.x, use makehost to add hostname and ip into /etc/hosts file: ::

  mkdef vm1 groups=vm,all
  chdef vm1 ip=x.x.x.x
  makehosts vm1

Update DNS with this new node: ::

  makedns -n
  makedns -a

Define attributes for the VM
^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Run the chdef command to change the following attributes for the vm1: 

1. Define the virtual cpu number: ::

    chdef vm1 vmcpus=2

2. Define the kvm hypervisor of the virtual machine vm1, it should be set to node001: ::
 
    chdef vm1 vmhost=node001

3. Define the virtual memory size, the unit is Megabit. For example, to define 1GB of memory to vm1: ::

    chdef vm1 vmmemory=1024

   Note: For diskless node, the vmmemory should be set larger than 2048, otherwise the node cannot be booted up. 

4. Define the hardware management module: ::

    chdef vm1 mgt=kvm

5. Define the virtual network card, it should be set to the bridge br0/virb0/default which defined in hypervisor. If no bridge was set explicitly, no network device will be created for the node vm1: ::

    chdef vm1 vmnics=br0

6. The vmnicnicmodel attribute is used to set the type and corresponding driver for the nic. If not set, the default value is 'virtio'.
   :: 

    chdef vm1 vmnicnicmodel=virtio

7. Define the storage for the vm1, three formats for the storage source are supported.

   A. Create storage on a nfs server

      The format is ``nfs://<IP_of_NFS_server>/dir``, that means the kvm disk files will be created at ``nfs://<IP_of_NFS_server>/dir``: ::

       chdef vm1 vmstorage=nfs://<IP_of_NFS_server>/install/vms/

   B. Create storage on a device of hypervisor

      Instead of the format is 'phy:/dev/sdb1': ::

       chdef vm1 vmstorage=phy:/dev/sdb1

   C. Create storage on a directory of hypervisor

      Instead of he format is 'dir:/install/vms': ::

       chdef vm1 vmstorage=dir:///install/vms

    Note: The attribute vmstorage is only necessary for diskfull node. You can ignore it for diskless node. 

8. Define the console attributes for the virtual machine: ::

    chdef vm1 serialport=0 serialspeed=115200

9. (optional)For monitor the installing process from vnc client, set vidpassword value: ::

    chtab node=vm1 vm.vidpassword=abc123

10. Set 'netboot' attribute

    * **[x86_64]**

    ::
 
     chdef vm1 netboot=xnba

    * **[PPC64LE]**
    :: 
  
     chdef vm1 netboot=grub2

    Make sure the grub2 had been installed on your Management Node: ::

      rpm -aq | grep grub2
      grub2-xcat-1.0-1.noarch

    Note: If you are working with xCAT-dep oldder than 20141012, the modules for xCAT shipped grub2 can not support ubuntu LE smoothly. So the following steps needed to complete the grub2 setting. ::

      rm /tftpboot/boot/grub2/grub2.ppc
      cp /tftpboot/boot/grub2/powerpc-ieee1275/core.elf /tftpboot/boot/grub2/grub2.ppc
      /bin/cp -rf /tmp/iso/boot/grub/powerpc-ieee1275/elf.mod /tftpboot/boot/grub2/powerpc-ieee1275/

Make the VM under xCAT
^^^^^^^^^^^^^^^^^^^^^^
If vmstorage is on a nfs server or a device of hypervisor, for example ::

  mkvm vm1

If create the virtual machine kvm1 with 20G hard disk from a large disk directory, for example ::

  mkvm vm1 -s 20G
   
If the vm1 was created successfully, a hard disk file named vm1.hda.qcow2 can be found in vmstorage location. And you can run the lsdef vm1 to see whether the mac attribute has been set automatically.

Create osimage object
^^^^^^^^^^^^^^^^^^^^^

After you download the OS ISO, refer to :ref:`create_img` to create osimage objects.

Configure DHCP 
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
::

   makedhcp -n
   makedhcp -a

Prepare the VM for installation
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
::

   nodeset vm1 osimage=<osimage_name>

Start VM Installation 
^^^^^^^^^^^^^^^^^^^^^

::

  rpower vm1 on

If the vm1 was powered on successfully, you can get following information when running 'virsh list' on the kvm hypervisor node001. ::

    virsh list
     Id Name                 State
    --------------------------------   
      6 vm1                 running


Monitoring the Virtual Machine
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

You can use console in xcat management node or kvm hypervisor to monitor the process. 

* On the kvm hypervisor you can use virsh to open text console: ::

   virsh console vm1

* Use rcons/wcons on the xCAT management node to open text console: ::

   cons=kvm
   makeconservercf vm1
   rcons vm1
   wcons vm1

* Connecting to the virtual machine's vnc console

  In order to connect to the virtual machine's console, you need to generate a new set of credentials. You can do it by running: ::

    xcatclient getrvidparms vm1
    vm1: method: kvm
    vm1: textconsole: /dev/pts/0
    vm1: password: JOQTUtn0dUOBv9o3
    vm1: vidproto: vnc
    vm1: server: kvmhost1
    vm1: vidport: 5900

  Note: Now just pick your favorite vnc client and connect to the hypervisor, using the password generated by "getrvidparms". If the vnc client complains the password is not valid, it is possible that your hypervisor and headnode clocks are out of sync! You can sync them by running "ntpdate <ntp server>" on both the hypervisor and the headnode. 


* Use wvid on the xCAT management node
 
  Make sure firewalld service had been stopped. ::

   chkconfig firewalld off

  Note: Forwarding request to systemctl will disable firewalld.service. ::

   rm /etc/systemd/system/basic.target.wants/firewalld.service 
   rm /etc/systemd/system/dbus-org.fedoraproject.FirewallD1.service

  Then, run wvid vm1 on MN::

   wvid vm1

* For powerKVM, we can use kimchi to monitor the installing process

  Open "https://<pkvm_ip>:8001" to open kimchi. There will be a “connect” button you can use below "Actions" button and input Password required:abc123 your have set before mkvm, then you could get the console.


Remove the virtual machine
------------------------ 

Remove the kvm1 even when it is in power on status. ::

    rmvm mv1 -f

Remove the definition of kvm and related storage. ::

    rmvm vm1 -p


Clone the virtual machine
-------------------------

Clone is a concept that create a new node from the old one by reuse most of data that has been installed on the old node. Before creating a new node, a vm (virtual machine) master must be created first. The new node will be created from the vm master. The new node can attach to the vm master or not.
The node can NOT be run without the vm master if choosing to make the node attach to the vm master. The advantage is that the less disk space is needed.

**In attaching mode**

In this mode, all the nodes will be attached to the vm master. Lesser disk space will be used than the general node.
Create the vm master kvmm from a node (vm1) and make the original node kvm2 attaches to the new created vm master: ::

    clonevm vm1 -t kvmm
    vm1: Cloning vm1.hda.qcow2 (currently is 1050.6640625 MB and has a capacity of 4096MB)
    vm1: Cloning of vm1.hda.qcow2 complete (clone uses 1006.74609375 for a disk size of 4096MB)
    vm1: Rebasing vm1.hda.qcow2 from master
    vm1: Rebased vm1.hda.qcow2 from master

After the performing, you can see the following entry has been added into the vmmaster table. ::

    tabdump vmmaster  
    name,os,arch,profile,storage,storagemodel,nics,vintage,originator,comments,disable
    "kvmm","rhels6","x86_64","compute","nfs://<storage_server_ip>/vms/kvm",,"br0","Tue Nov 23 04:18:17 2010","root",,

Clone a new node vm2 from vm master kvmm: ::

    clonevm vm2 -b kvmm

**In detaching mode**

Create a vm master that the original node detaches with the created vm master. ::

    clonevm vm2 -t kvmmd -d
    vm2: Cloning vm2.hda.qcow2 (currently is 1049.4765625 MB and has a capacity of 4096MB)
    vm2: Cloning of vm2.hda.qcow2 complete (clone uses 1042.21875 for a disk size of 4096MB)

Clone the vm3 from the kvmmd with the detaching mode turn on: ::

    clonevm vm3 -b kvmmd -d
    vm3: Cloning kvmmd.hda.qcow2 (currently is 1042.21875 MB and has a capacity of 4096MB)

FAQ
---

1, libvirtd run into problem

   **Issue**: One error as following message: ::

    rpower kvm1 on
    kvm1: internal error no supported architecture for os type 'hvm'

   **Solution**: This error was fixed by restarting libvirtd on the host machine: ::

    xdsh kvmhost1 service libvirtd restart

   Note: In any case that you find there is libvirtd error message in syslog, you can try to restart the libvirtd.

2, Virtual disk has problem

  **Issue**: When running command 'rpower kvm1 on', get the following error message: ::

    kvm1: Error: unable to set user and group to '0:0'
      on '/var/lib/xcat/pools/27f1df4b-e6cb-5ed2-42f2-9ef7bdd5f00f/kvm1.hda.qcow2': Invalid argument:

  **Solution**: try to figure out the nfs:// server was exported correctly. The nfs client should have root authority.

3, VNC client complains the credentials are not valid

   **Issue**: When connecting to the hypervisor using VNC to get a VM console, the vnc client complains with "Authentication failed".

   **Solution**: Check if the clocks on your hypervisor and headnode are in sync! 

4, rpower fails with "qemu: could not open disk image /var/lib/xcat/pools/2e66895a-e09a-53d5-74d3-eccdd9746eb5/vmXYZ.hda.qcow2: Permission denied" error message

   **Issue**: When running rpower on a kvm vm, rpower complains with the following error message: ::

    rpower vm1 on
    vm1: Error: internal error Process exited while reading console log output: char device redirected to /dev/pts/1
    qemu: could not open disk image /var/lib/xcat/pools/2e66895a-e09a-53d5-74d3-eccdd9746eb5/vm1.hda.qcow2: Permission denied: internal error Process exited while reading console log output: char device redirected to /dev/pts/1
    qemu: could not open disk image /var/lib/xcat/pools/2e66895a-e09a-53d5-74d3-eccdd9746eb5/vm1.hda.qcow2: Permission denied
    [root@xcat xCAT_plugin]#

   **Solution**: This might be caused by bad permissions in your NFS server / client (where clients will not mount the share with the correct permissions). Systems like CentOS 6 will have NFS v4 support activated by default. This might be causing the above mentioned problems so one solution is to simply disable NFS v4 support in your NFS server by uncommenting the following option in /etc/sysconfig/nfs: ::

    RPCNFSDARGS="-N 4"

   Finish by restarting your NFS services (i.e. service nfsd restart) and try powering on your VM again...
   Note: if you are running a stateless hypervisor, we advise you to purge the VM (rmvm -p vmXYZ), restart the hypervisor and "mkvm vmXYZ -s 4" to recreate the VM as soon as the hypervisor is up and running.

5, Error: Cannot communicate via libvirt to <host>

   **Issue**: This error mostly caused by the incorrect setting of the ssh tunnel between xCAT management node and <host>.

   **Solution**: Check that xCAT MN could ssh to the <host> without password.

6, Cannot ping to the vm after the first boot of stateful install

   **Issue**: The new installed stateful vm node is not pingable after the first boot, you may see the following error message in the console when vm booting: ::

    ADDRCONF(NETDEV_UP): eth0 link is not ready.

   **Solutoin**: This issue may be caused by the incorrect driver for vm. You can try to change driver to 'virtio' by following steps: :: 

    rmvm kvm1
    chdef kvm1 vmnicnicmodel=virtio
    mkvm kvm1


