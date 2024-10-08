
####
vm.5
####

.. highlight:: perl


****
NAME
****


\ **vm**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **vm Attributes:**\   \ *node*\ , \ *mgr*\ , \ *host*\ , \ *migrationdest*\ , \ *storage*\ , \ *storagemodel*\ , \ *storagecache*\ , \ *storageformat*\ , \ *cfgstore*\ , \ *memory*\ , \ *cpus*\ , \ *nics*\ , \ *nicmodel*\ , \ *bootorder*\ , \ *clockoffset*\ , \ *virtflags*\ , \ *master*\ , \ *vncport*\ , \ *textconsole*\ , \ *powerstate*\ , \ *beacon*\ , \ *datacenter*\ , \ *cluster*\ , \ *guestostype*\ , \ *othersettings*\ , \ *physlots*\ , \ *vidmodel*\ , \ *vidproto*\ , \ *vidpassword*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


Virtualization parameters


**************
vm Attributes:
**************



\ **node**\ 
 
 The node or static group name
 


\ **mgr**\ 
 
 The function manager for the virtual machine
 


\ **host**\ 
 
 The system that currently hosts the VM
 


\ **migrationdest**\ 
 
 A noderange representing candidate destinations for migration (i.e. similar systems, same SAN, or other criteria that xCAT can use
 


\ **storage**\ 
 
 A list of storage files or devices to be used.  i.e. dir:///cluster/vm/<nodename> or nfs://<server>/path/to/folder/
 


\ **storagemodel**\ 
 
 Model of storage devices to provide to guest
 


\ **storagecache**\ 
 
 Select caching scheme to employ.  E.g. KVM understands 'none', 'writethrough' and 'writeback'
 


\ **storageformat**\ 
 
 Select disk format to use by default (e.g. raw versus qcow2)
 


\ **cfgstore**\ 
 
 Optional location for persistent storage separate of emulated hard drives for virtualization solutions that require persistent store to place configuration data
 


\ **memory**\ 
 
 Megabytes of memory the VM currently should be set to.
 


\ **cpus**\ 
 
 Number of CPUs the node should see.
 


\ **nics**\ 
 
 Network configuration parameters.  Of the general form [physnet:]interface,.. Generally, interface describes the vlan entity (default for native, tagged for tagged, vl[number] for a specific vlan.  physnet is a virtual switch name or port description that is used for some virtualization technologies to construct virtual switches.  hypervisor.netmap can map names to hypervisor specific layouts, or the descriptions described there may be used directly here where possible. A macvtap device can be created by adding the "|direct" suffix to the interface name.
 


\ **nicmodel**\ 
 
 Model of NICs that will be provided to VMs (i.e. e1000, rtl8139, virtio, etc)
 


\ **bootorder**\ 
 
 Boot sequence (i.e. net,hd)
 


\ **clockoffset**\ 
 
 Whether to have guest RTC synced to "localtime" or "utc"  If not populated, xCAT will guess based on the nodetype.os contents.
 


\ **virtflags**\ 
 
 General flags used by the virtualization method.
           For example, in Xen it could, among other things, specify paravirtualized setup, or direct kernel boot.  For a hypervisor/dom0 entry, it is the virtualization method (i.e. "xen").  For KVM, the following flag=value pairs are recognized:
             imageformat=[raw|fullraw|qcow2]
                 raw is a generic sparse file that allocates storage on demand
                 fullraw is a generic, non-sparse file that preallocates all space
                 qcow2 is a sparse, copy-on-write capable format implemented at the virtualization layer rather than the filesystem level
             clonemethod=[qemu-img|reflink]
                 qemu-img allows use of qcow2 to generate virtualization layer copy-on-write
                 reflink uses a generic filesystem facility to clone the files on your behalf, but requires filesystem support such as btrfs
             placement_affinity=[migratable|user_migratable|pinned]
 


\ **master**\ 
 
 The name of a master image, if any, this virtual machine is linked to.  This is generally set by clonevm and indicates the deletion of a master that would invalidate the storage of this virtual machine
 


\ **vncport**\ 
 
 Tracks the current VNC display port (currently not meant to be set
 


\ **textconsole**\ 
 
 Tracks the Psuedo-TTY that maps to the serial port or console of a VM
 


\ **powerstate**\ 
 
 This flag is used by xCAT to track the last known power state of the VM.
 


\ **beacon**\ 
 
 This flag is used by xCAT to track the state of the identify LED with respect to the VM.
 


\ **datacenter**\ 
 
 Optionally specify a datacenter for the VM to exist in (only applicable to VMWare)
 


\ **cluster**\ 
 
 Specify to the underlying virtualization infrastructure a cluster membership for the hypervisor.
 


\ **guestostype**\ 
 
 This allows administrator to specify an identifier for OS to pass through to virtualization stack.  Normally this should be ignored as xCAT will translate from nodetype.os rather than requiring this field be used
 


\ **othersettings**\ 
 
 This is a semicolon-delimited list of key-value pairs to be included in a vmx file of VMware or KVM. DO NOT use 'chdef <node> -p|-m vmothersetting=...' to add options to it or delete options from it because chdef uses commas, not semicolons, to separate items.
           Hugepage on POWER systems:
              Specify the hugepage and/or bsr (Barrier Synchronization Register) values, e.g., 'hugepage:1,bsr:2'.
           KVM CPU mode:
              Specify how the host CPUs are utilized, e.g., 'cpumode:host-passthrough', 'cpumode:host-model'. With the passthrough mode, the performance of x86 VMs can be improved significantly.
           KVM CPU pinning:
              Specify which host CPUs are used, e.g., 'vcpupin:'0-15,^8', where '-' denotes the range and '^' denotes exclusion. This option allows a comma-delimited list.
           KVM memory binding:
              Specify which nodes that host memory are used, e.g., 'membind:0', where the memory in node0 of the hypervisor is used. /sys/devices/system/node has node0 and node8 on some POWER systems, node0 and node1 on some x86_64 systems. This option allows a guest VM to access specific memory regions.
           PCI passthrough:
              PCI devices can be assigned to a virtual machine for exclusive usage, e.g., 'devpassthrough:pci_0001_01_00_0,pci_0000_03_00_0'. A PCI device can also be expressed as 'devpassthrough:0001:01:00.1'. The devices are put in a comma-delimited list. The PCI device names can be obtained by running \ **virsh nodedev-list**\  on the host.
           VM machine type:
              Specify a machine type for VM creation on the host, e.g., 'machine:pc'. Typical machine types are pc, q35, and pseries.
 


\ **physlots**\ 
 
 Specify the physical slots drc index that will assigned to the partition, the delimiter is ',', and the drc index must started with '0x'. For more details, reference manpage for 'lsvm'.
 


\ **vidmodel**\ 
 
 Model of video adapter to provide to guest.  For example, qxl in KVM
 


\ **vidproto**\ 
 
 Request a specific protocol for remote video access be set up.  For example, spice in KVM.
 


\ **vidpassword**\ 
 
 Password to use instead of temporary random tokens for VNC and SPICE access
 


\ **comments**\ 



\ **disable**\ 




********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

