Manage Virtual Machine (VM)
============================


Now the PowerKVM hypervisor "kvmhost1" is ready, this section introduces the VM management in xCAT, including examples on how to create, remove and clone VMs.

Create Virtual Machine
----------------------

Create VM Node Definition
`````````````````````````
Create a virtual machine node object "vm1", assign it to be a member of group "vm", its ip is "192.168.0.1", run ``makehost`` to add an entry in ``/etc/hosts`` file: ::

  mkdef vm1 groups=vm,all
  chdef vm1 ip=192.168.0.1
  makehosts vm1

Update DNS configuration and database: ::

  makedns -n
  makedns -a

Specify VM attributes 
`````````````````````

After the VM object is created, several key attributes need to be specified with ``chdef`` : 

1. the number of virtual cpus in the VM: ::

     chdef vm1 vmcpus=2

2. the kvm hypervisor of the VM: ::
 
     chdef vm1 vmhost=kvmhost1

3. the virtual memory size, with the unit "Megabit". Specify 1GB memory to "vm1" here: ::

     chdef vm1 vmmemory=1024

**Note**: For diskless node, the **vmmemory** should be at least 2048 MB, otherwise the node cannot boot up. 

4. the hardware management module, "kvm" for PowerKVM: ::

    chdef vm1 mgt=kvm

5. Define the virtual network card, it should be set to the bridge "br0" which has been created in the hypervisor. If no bridge is specified, no network device will be created for the VM node "vm1": ::

    chdef vm1 vmnics=br0

6. The **vmnicnicmodel** attribute is used to set the type and corresponding driver for the nic. If not set, the default value is 'virtio'.
   :: 

    chdef vm1 vmnicnicmodel=virtio

7. Define the storage for the vm1, three types of storage source format are supported.

   A. Create storage on a NFS server

      The format is ``nfs://<IP_of_NFS_server>/dir``, that means the kvm disk files will be created at ``nfs://<IP_of_NFS_server>/dir``: ::

        chdef vm1 vmstorage=nfs://<IP_of_NFS_server>/install/vms/

   B. Create storage on a device of hypervisor

      The format is 'phy:/dev/sdb1': ::

        chdef vm1 vmstorage=phy:/dev/sdb1

   C. Create storage on a directory of hypervisor

      The format is 'dir:///var/lib/libvirt/images': ::

        chdef vm1 vmstorage=dir:///var/lib/libvirt/images

   **Note**: The attribute **vmstorage** is only valid for diskful VM node. 

8. Define the **console** attributes for VM: ::

     chdef vm1 serialport=0 serialspeed=115200

9. (optional)For monitoring and access the VM with vnc client, set **vidpassword** value: ::

     chtab node=vm1 vm.vidpassword=abc123

10. (optional)For assigning PCI devices to the VM, set **othersettings** value: ::

     chtab node=vm1 vm.othersettings="devpassthrough:0000:01:00.2" 

    Or: ::

     chtab node=vm1 vm.othersettings="devpassthrough:pci_0000_01_00_2"

    Take assigning SR-IOV VFs to the VM as an example: 

    * Use ``lspci`` to get VFs PCI from hypervisor: ::

        lspci|grep -i "Virtual Function"
          0000:01:00.1 Infiniband controller: Mellanox Technologies MT27700 Family [ConnectX-4 Virtual Function]
          0000:01:00.2 Infiniband controller: Mellanox Technologies MT27700 Family [ConnectX-4 Virtual Function]

    * Set the VFs PCI into ``vm`` table on MN: ::
     
        chtab node=vm1 vm.othersettings="devpassthrough:0000:01:00.1,0000:01:00.2"

11. Set **netboot** attribute

    * **[x86_64]** ::
 
        chdef vm1 netboot=xnba

    * **[PPC64LE]** ::
  
        chdef vm1 netboot=grub2

    Make sure "grub2" had been installed on the management node: ::

        #rpm -aq | grep grub2
        grub2-xcat-1.0-1.noarch


Make virtual machine 
````````````````````

If **vmstorage** is a NFS mounted directory or a device on hypervisor, run ::

  mkvm vm1

To create the virtual machine "vm1" with 20G hard disk on a hypervisor directory, run ::

  mkvm vm1 -s 20G
   
When "vm1" is created successfully, a VM hard disk file with a name like "vm1.sda.qcow2" will be found in the location specified by **vmstorage**. What's more, the **mac** attribute of "vm1" is set automatically, check it with: ::

  lsdef vm1 -i mac

Now a VM "vm1" is created, it can be provisioned like any other nodes in xCAT. The VM node can be powered on by: ::

  rpower vm1 on

If "vm1" is powered on successfully, the VM status can be obtained by running the following command on management node ::

  rpower vm1 status

or running the following command on the kvm hypervisor "kvmhost1" ::

    #virsh list
     Id Name                 State
    --------------------------------   
      6 vm1                 running


Monitoring the Virtual Machine
``````````````````````````````

When the VM has been created and powered on, choose one of the following methods to monitor and access it. 

* Open the console on kvm hypervisor: ::

   virsh console vm1

* Use **rcons/wcons** on xCAT management node to open text console: ::

   chdef vm1 cons=kvm
   makeconservercf vm1
   rcons vm1

* Connect to virtual machine through vnc console

  In order to connect the virtual machine's vnc server, a new set of credentials need to be generated by running: ::

    xcatclient getrvidparms vm1
    vm1: method: kvm
    vm1: textconsole: /dev/pts/0
    vm1: password: JOQTUtn0dUOBv9o3
    vm1: vidproto: vnc
    vm1: server: kvmhost1
    vm1: vidport: 5900

  **Note**: Now just pick a favorite vnc client to connect the hypervisor, with the password generated by ``getrvidparms``. If the vnc client complains "the password is not valid",  the reason might be that the hypervisor and headnode clocks are out of sync! Please try to sync them by running ``ntpdate <ntp server>`` on both the hypervisor and the headnode. 


* Use wvid on management node
 
  Make sure **firewalld** service is stopped, disable it if not: ::

    chkconfig firewalld off

  or ::

    systemctl disable firewalld


  Then, run ``wvid`` on MN::

    wvid vm1

* For PowerKVM,  **kimchi** on the kvm hypervisor can be used to monitor and access the VM.


Remove the virtual machine
--------------------------

Remove the VM "vm1" even when it is in "power-on" status: ::

    rmvm vm1 -f

Remove the definition of "vm1" and related storage: ::

    rmvm vm1 -p


Clone the virtual machine
-------------------------

**Clone** is an operation that creating a VM from an existed one by inheriting most of its attributes and data. 

The general step of **clone** a VM is like this: first creating a **VM master** , then creating a VM with the newly created **VM master** in **attaching** or **detaching** mode.


**In attaching mode**

In this mode, all the newly created VMs are attached to the VM master. Since the image of the newly created VM only includes the differences from the VM master, which requires less disk space. The newly created VMs can NOT run without the VM master. 

An example is shown below:

Create the VM master "vm5" from a VM node "vm1": ::

    #clonevm vm1 -t vm5
    vm1: Cloning vm1.sda.qcow2 (currently is 1050.6640625 MB and has a capacity of 4096MB)
    vm1: Cloning of vm1.sda.qcow2 complete (clone uses 1006.74609375 for a disk size of 4096MB)
    vm1: Rebasing vm1.sda.qcow2 from master
    vm1: Rebased vm1.sda.qcow2 from master

The newly created VM master "vm5" can be found in the **vmmaster** table. ::

    #tabdump vmmaster  
    name,os,arch,profile,storage,storagemodel,nics,vintage,originator,comments,disable
    "vm5","<os>","<arch>","compute","nfs://<storage_server_ip>/vms/kvm",,"br0","<date>","root",,

Clone a new node vm2 from VM master vm5: ::

    clonevm vm2 -b vm5

**In detaching mode**

Create a VM master "vm6" . ::

    #clonevm vm2 -t vm6 -d
    vm2: Cloning vm2.sda.qcow2 (currently is 1049.4765625 MB and has a capacity of 4096MB)
    vm2: Cloning of vm2.sda.qcow2 complete (clone uses 1042.21875 for a disk size of 4096MB)

Clone a VM "vm3" from the VM master "vm6" in detaching mode: ::

    #clonevm vm3 -b vm6 -d
    vm3: Cloning vm6.sda.qcow2 (currently is 1042.21875 MB and has a capacity of 4096MB)

Migrate Virtual Machines
------------------------

Virtual machine migration is a process that moves the virtual machines (guests) between different hypervisors (hosts).

Note: The VM storage directory should be accessible from both hypervisors (hosts).

Migrate the VM "kvm1" from hypervisor "hyp01" to hypervisor "hyp02": ::

    #rmigrate kvm1 hyp02
    kvm1: migrated to hyp02

