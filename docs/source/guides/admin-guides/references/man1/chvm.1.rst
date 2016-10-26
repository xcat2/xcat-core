
######
chvm.1
######

.. highlight:: perl


****
NAME
****


\ **chvm**\  - Changes HMC-, DFM-, IVM-, and zVM-managed partition profiles or virtual machines. For Power 775, chvm could be used to change the octant configuration values for generating LPARs; change the I/O slots assignment to LPARs within the same CEC.


********
SYNOPSIS
********


\ **chvm**\  [\ **-h**\ | \ **-**\ **-help**\ ]

\ **chvm**\  [\ **-v**\ | \ **-**\ **-version**\ ]

PPC (with HMC) specific:
========================


\ **chvm**\  [\ **-V**\ | \ **-**\ **-verbose**\ ] \ *noderange*\  [\ **-p**\  \ *profile*\ ]

\ **chvm**\  [\ **-V**\ | \ **-**\ **-verbose**\ ] \ *noderange*\  \ *attr*\ =\ *val*\  [\ *attr*\ =\ *val*\ ...]


PPC (using Direct FSP Management) specific:
===========================================


\ **chvm**\  \ *noderange*\  \ **-**\ **-p775**\  [\ **-p**\  \ *profile*\ ]

\ **chvm**\  \ *noderange*\  \ **-**\ **-p775**\  \ **-i id**\  [\ **-m**\  \ *memory_interleaving*\ ] \ **-r**\  \ *partition_rule*\ 

\ **chvm**\  \ *noderange*\  [\ **lparname**\ ={ \* | \ *name*\ }]

\ **chvm**\  \ *noderange*\  [\ **vmcpus=**\  \ *min/req/max*\ ] [\ **vmmemory=**\  \ *min/req/max*\ ] [\ **vmothersetting=hugepage:N,bsr:N**\ ] [\ **add_physlots=**\  \ *drc_index1,drc_index2...*\ ] [\ **add_vmnics=**\  \ *vlan1[,vlan2..]]*\  [\ **add_vmstorage=<N|viosnode:slotid**\ >] [\ **-**\ **-vios**\ ] [\ **del_physlots=**\  \ *drc_index1,drc_index2...*\ ] [\ **del_vadapter=**\  \ *slotid*\ ]


KVM specific:
=============


\ **chvm**\  \ *noderange*\  [\ **-**\ **-cpupin**\  \ *hostcpuset*\ ]

\ **chvm**\  \ *noderange*\  [\ **-**\ **-membind**\  \ *numanodeset*\ ]

\ **chvm**\  \ *noderange*\  [\ **-**\ **-devpassthru**\  \ *pcidevice*\ ...]

\ **chvm**\  \ *noderange*\  [\ **-**\ **-devdetach**\  \ *pcidevice*\ ...]


VMware/KVM specific:
====================


\ **chvm**\  \ *noderange*\  [\ **-a**\  \ *size*\ ] [\ **-d**\  \ *disk*\ ] [\ **-p**\  \ *disk*\ ] [\ **-**\ **-resize**\  \ *disk*\ =\ *size*\ ] [\ **-**\ **-cpus**\  \ *count*\ ] [\ **-**\ **-mem**\  \ *memory*\ ]


zVM specific:
=============


\ **chvm**\  \ *noderange*\  [\ **-**\ **-add3390**\  \ *disk_pool*\  \ *device_address*\  \ *size*\  \ *mode*\  \ *read_password*\  \ *write_password*\  \ *multi_password*\ ]

\ **chvm**\  \ *noderange*\  [\ **-**\ **-add3390active**\  \ *device_address*\  \ *mode*\ ]

\ **chvm**\  \ *noderange*\  [\ **-**\ **-add9336**\  \ *disk_pool*\  \ *device_address*\  \ *size*\  \ *mode*\  \ *read_password*\  \ *write_password*\  \ *multi_password*\ ]

\ **chvm**\  \ *noderange*\  [\ **-**\ **-adddisk2pool**\  \ *function*\  \ *region*\  \ *volume*\  \ *group*\ ]

\ **chvm**\  \ *noderange*\  [\ **-**\ **-addnic**\  \ *device_address*\  \ *type*\  \ *device_count*\ ]

\ **chvm**\  \ *noderange*\  [\ **-**\ **-addpagespool**\  \ *volume_address*\  \ *volume_label*\  \ *volume_use*\  \ *system_config_name*\  \ *system_config_type*\  \ *parm_disk_owner*\  \ *parm_disk_number*\  \ *parm_disk_password*\ ]

\ **chvm**\  \ *noderange*\  [\ **-**\ **-addprocessor**\  \ *device_address*\ ]

\ **chvm**\  \ *noderange*\  [\ **-**\ **-addprocessoractive**\  \ *device_address*\  \ *type*\ ]

\ **chvm**\  \ *noderange*\  [\ **-**\ **-addvdisk**\  \ *device_address*\  \ *size*\ ]

\ **chvm**\  \ *noderange*\  [\ **-**\ **-addzfcp**\  \ *pool*\  \ *device_address*\  \ *loaddev*\  \ *size*\  \ *tag*\  \ *wwpn*\  \ *lun*\ ]

\ **chvm**\  \ *noderange*\  [\ **-**\ **-connectnic2guestlan**\  \ *device_address*\  \ *lan*\  \ *owner*\ ]

\ **chvm**\  \ *noderange*\  [\ **-**\ **-connectnic2vswitch**\  \ *device_address*\  \ *vswitch*\ ]

\ **chvm**\  \ *noderange*\  [\ **-**\ **-copydisk**\  \ *target_address*\  \ *source_node*\  \ *source_address*\ ]

\ **chvm**\  \ *noderange*\  [\ **-**\ **-dedicatedevice**\  \ *virtual_device*\  \ *real_device*\  \ *mode*\ ]

\ **chvm**\  \ *noderange*\  [\ **-**\ **-deleteipl**\ ]

\ **chvm**\  \ *noderange*\  [\ **-**\ **-disconnectnic**\  \ *device_address*\ ]

\ **chvm**\  \ *noderange*\  [\ **-**\ **-formatdisk**\  \ *device_address*\  \ *multi_password*\ ]

\ **chvm**\  \ *noderange*\  [\ **-**\ **-grantvswitch**\  \ *vswitch*\ ]

\ **chvm**\  \ *noderange*\  [\ **-**\ **-purgerdr**\ ]

\ **chvm**\  \ *noderange*\  [\ **-**\ **-removedisk**\  \ *device_address*\ ]

\ **chvm**\  \ *noderange*\  [\ **-**\ **-removenic**\  \ *device_address*\ ]

\ **chvm**\  \ *noderange*\  [\ **-**\ **-removeprocessor**\  \ *device_address*\ ]

\ **chvm**\  \ *noderange*\  [\ **-**\ **-removeloaddev**\  \ *wwpn*\  \ *lun*\ ]

\ **chvm**\  \ *noderange*\  [\ **-**\ **-removezfcp**\  \ *device_address*\  \ *wwpn*\  \ *lun*\ ]

\ **chvm**\  \ *noderange*\  [\ **-**\ **-replacevs**\  \ *directory_entry*\ ]

\ **chvm**\  \ *noderange*\  [\ **-**\ **-setipl**\  \ *ipl_target*\  \ *load_parms*\  \ *parms*\ ]

\ **chvm**\  \ *noderange*\  [\ **-**\ **-setpassword**\  \ *password*\ ]

\ **chvm**\  \ *noderange*\  [\ **-**\ **-setloaddev**\  \ *wwpn*\  \ *lun*\ ]

\ **chvm**\  \ *noderange*\  [\ **-**\ **-sharevolume**\  \ *volume_address*\  \ *share_enable*\ ]

\ **chvm**\  \ *noderange*\  [\ **-**\ **-undedicatedevice**\  \ *device_address*\ ]



***********
DESCRIPTION
***********


PPC (with HMC) specific:
========================


The chvm command modifies the partition profile for the partitions specified in noderange. A partitions current profile can be read using lsvm, modified, and piped into the chvm command, or changed with the -p flag.

This command also supports to change specific partition attributes by specifying one or more "attribute equals value" pairs in command line directly, without whole partition profile.


PPC (using Direct FSP Management) specific:
===========================================


For Power 755(use option \ *--p775*\  to specify):

chvm could be used to change the octant configuration values for generating LPARs. chvm is designed to set the Octant configure value to split the CPU and memory for partitions, and set Octant Memory interleaving value. The chvm will only set the pending attributes value. After chvm, the CEC needs to be rebooted manually for the pending values to be enabled. Before reboot the cec, the administrator can use chvm to change the partition plan. If the the partition needs I/O slots, the administrator should use chvm to assign the I/O slots.

chvm is also designed to assign the I/O slots to the new LPAR. Both the current IO owning lpar and the new IO owning lpar must be powered off before an IO assignment. Otherwise, if the I/O slot is belonged to an Lpar and the LPAR is power on, the command will return an error when trying to assign that slot to a different lpar.

The administrator should use lsvm to get the profile content, and then edit the content, and add the node name with ":" manually before the I/O which will be assigned to the node. And then the profile can be piped into the chvm command, or changed with the -p flag.

For normal power machine:

chvm could be used to modify the resources assigned to partitions. The admin shall specify the attributes with options \ *vmcpus*\ , \ *vmmemory*\ , \ *add_physlots*\ , \ *vmothersetting*\ , \ *add_vmnics*\  and/or \ *add_vmstorage*\ . If nothing specified, nothing will be returned.


zVM specific:
=============


The chvm command modifes the virtual machine's configuration specified in noderange.



*******
OPTIONS
*******


Common:
=======



\ **-h**\ 
 
 Display usage message.
 


\ **-v**\ 
 
 Command Version.
 



PPC (with HMC) specific:
========================



\ **-p**\  \ *profile*\ 
 
 Name of an existing partition profile.
 


\ *attr*\ =\ *val*\ 
 
 Specifies one or more "attribute equals value" pairs, separated by spaces.
 


\ **-V**\ 
 
 Verbose output.
 



PPC (using Direct FSP Management) specific:
===========================================



\ **-**\ **-p775**\ 
 
 Specify the operation is for Power 775 machines.
 


\ **-i**\ 
 
 Starting numeric id of the newly created partitions. For Power 775 using Direct FSP Management, the id value only could be \ **1**\ , \ **5**\ , \ **9**\ , \ **13**\ , \ **17**\ , \ **21**\ , \ **25**\  and \ **29**\ . Shall work with option \ **-**\ **-p775**\ .
 


\ **-m**\ 
 
 memory interleaving. The setting value only could be \ **1**\  or \ **2**\ . \ **2**\  means \ **non-interleaved**\  mode (also 2MC mode), the memory cannot be shared across the processors in an octant. \ **1**\  means \ **interleaved**\  mode (also 8MC mode) , the memory can be shared. The default value is \ **1**\ . Shall work with option \ **-**\ **-p775**\ .
 


\ **-r**\ 
 
 partition rule. Shall work with option \ **-**\ **-p775**\ .
 
 If all the octants configuration value are same in one CEC,  it will be  " \ **-r**\   \ **0-7**\ :\ *value*\ " .
 
 If the octants use the different configuration value in one cec, it will be "\ **-r**\  \ **0**\ :\ *value1*\ ,\ **1**\ :\ *value2*\ ,...\ **7**\ :\ *value7*\ ", or "\ **-r**\  \ **0**\ :\ *value1*\ ,\ **1-7**\ :\ *value2*\ " and so on.
 
 The octants configuration value for one Octant could be  \ **1**\ , \ **2**\ , \ **3**\ , \ **4**\ , \ **5**\ . The meanings of the octants configuration value  are as following:
 
 
 .. code-block:: perl
 
   1 -- 1 partition with all cpus and memory of the octant
   2 -- 2 partitions with a 50/50 split of cpus and memory
   3 -- 3 partitions with a 25/25/50 split of cpus and memory
   4 -- 4 partitions with a 25/25/25/25 split of cpus and memory
   5 -- 2 partitions with a 25/75 split of cpus and memory
 
 


\ **-p**\  \ *profile*\ 
 
 Name of I/O slots assignment profile. Shall work with option \ **-**\ **-p775**\ .
 


\ **lparname**\ ={\ **\\* | name**\ }
 
 Set LPAR name for the specified lpars. If '\*' specified, it means to get names from xCAT database and then set them for the specified lpars. If a string is specified, it only supports single node and the string will be set for the specified lpar. The user can use lsvm to check the lparnames for lpars.
 


\ **vmcpus=value**\  \ **vmmemory=value**\  \ **add_physlots=value**\  \ **vmothersetting=value**\ 
 
 To specify the parameters that will be modified.
 


\ **add_vmnics=value**\  \ **add_vmstorage=value**\  [\ **-**\ **-vios**\ ]
 
 To create new virtual adapter for the specified node.
 


\ **del_physlots=drc_index1,drc_index2...**\ 
 
 To delete physical slots which are specified by the \ *drc_index1,drc_index2...*\ .
 


\ **del_vadapter=slotid**\ 
 
 To delete a virtual adapter specified by the \ *slotid*\ .
 



VMware/KVM specific:
====================



\ **-a**\  \ *size*\ 
 
 Add a new Hard disk with size defaulting to GB.  Multiple can be added with comma separated values.
 


\ **-**\ **-cpus**\  \ *count*\ 
 
 Set the number of CPUs.
 


\ **-d**\  \ *disk*\ 
 
 Deregister the Hard disk but leave the backing files.  Multiple can be done with comma separated values.  The disks are specified by SCSI id.
 


\ **-**\ **-mem**\  \ *memory*\ 
 
 Set the memory, defaults to MB.
 


\ **-p**\  \ *disk*\ 
 
 Purge the Hard disk.  Deregisters and deletes the files.  Multiple can be done with comma separated values.  The disks are specified by SCSI id.
 


\ **-**\ **-resize**\  \ *disk*\ =\ *size*\ 
 
 Change the size of the Hard disk.  The disk in \ *qcow2*\  format can not be set to less than it's current size. The disk in \ *raw*\  format can be resized smaller, use caution. Multiple disks can be resized by using comma separated \ *disk*\ \ **=**\ \ *size*\  pairs.  The disks are specified by SCSI id.  Size defaults to GB.
 



KVM specific:
=============



\ **-**\ **-cpupin hostcpuset**\ 
 
 To pin guest domain virtual CPUs to physical host CPUs specified with \ *hostcpuset*\ .
 \ *hostcpuset*\  is a list of physical CPU numbers. Its syntax is a comma separated list and a special
 markup using '-' and '^' (ex. '0-4', '0-3,^2') can also be allowed. The '-' denotes the range and
 the '^' denotes exclusive.
 
 Note: The expression is sequentially evaluated, so "0-15,^8" is identical to "9-14,0-7,15" but not
 identical to "^8,0-15".
 


\ **-**\ **-membind numanodeset**\ 
 
 It is possible to restrict a guest to allocate memory from the specified set of NUMA nodes \ *numanodeset*\ . 
 If the guest vCPUs are also pinned to a set of cores located on that same set of NUMA nodes, memory
 access is local and improves memory access performance.
 


\ **-**\ **-devpassthru pcidevice1,pcidevice2...**\ 
 
 The PCI passthrough gives a guest VM direct access to I/O devices \ *pcidevice1,pcidevice2...*\ . 
 The PCI devices are assigned to a virtual machine, and the virtual machine can use this I/O exclusively.
 The devices list are a list of comma separated PCI device names delimited with comma, the PCI device names can be obtained by running \ **virsh nodedev-list**\  on the host.
 


\ **-**\ **-devdetach pcidevice1,pcidevice2...**\ 
 
 To detaching the PCI devices which are attached to VM guest via PCI passthrough from the VM guest. The devices list are a list of comma separated PCI device names delimited with comma, the PCI device names can be obtained by running \ **virsh nodedev-list**\  on the host.
 



zVM specific:
=============



\ **-**\ **-add3390**\  \ *disk_pool*\  \ *device_address*\  \ *size*\  \ *mode*\  \ *read_password*\  \ *write_password*\  \ *multi_password*\ 
 
 Adds a 3390 (ECKD) disk to a virtual machine's directory entry. The device address can be automatically assigned by specifying 'auto'. The size of the disk can be specified in GB, MB, or the number of cylinders.
 


\ **-**\ **-add3390active**\  \ *device_address*\  \ *mode*\ 
 
 Adds a 3390 (ECKD) disk that is defined in a virtual machine's directory entry to that virtual server's active configuration.
 


\ **-**\ **-add9336**\  \ *disk_pool*\  \ *device_address*\  \ *size*\  \ *mode*\  \ *read_password*\  \ *write_password*\  \ *multi_password*\ 
 
 Adds a 9336 (FBA) disk to a virtual machine's directory entry. The device address can be automatically assigned by specifying 'auto'. The size of the disk can be specified in GB, MB, or the number of blocks.
 


\ **-**\ **-adddisk2pool**\  \ *function*\  \ *region*\  \ *volume*\  \ *group*\ 
 
 Add a disk to a disk pool defined in the EXTENT CONTROL. Function type can be either: (4) Define region as full volume and add to group OR (5) Add existing region to group.  The disk has to already be attached to SYSTEM.
 


\ **-**\ **-addnic**\  \ *device_address*\  \ *type*\  \ *device_count*\ 
 
 Adds a network adapter to a virtual machine's directory entry (case sensitive).
 


\ **-**\ **-addpagespool**\  \ *volume_addr*\  \ *volume_label*\  \ *volume_use*\  \ *system_config_name*\  \ *system_config_type*\  \ *parm_disk_owner*\  \ *parm_disk_number*\  \ *parm_disk_password*\ 
 
 Add a full volume page or spool disk to the virtual machine.
 


\ **-**\ **-addprocessor**\  \ *device_address*\ 
 
 Adds a virtual processor to a virtual machine's directory entry.
 


\ **-**\ **-addprocessoractive**\  \ *device_address*\  \ *type*\ 
 
 Adds a virtual processor to a virtual machine's active configuration (case sensitive).
 


\ **-**\ **-addvdisk**\  \ *device_address*\  \ *size*\ 
 
 Adds a v-disk to a virtual machine's directory entry.
 


\ **-**\ **-addzfcp**\  \ *pool*\  \ *device_address*\  \ *loaddev*\  \ *size*\  \ *tag*\  \ *wwpn*\  \ *lun*\ 
 
 Add a zFCP device to a device pool defined in xCAT. The device must have been 
 carved up in the storage controller and configured with a WWPN/LUN before it can 
 be added to the xCAT storage pool. z/VM does not have the ability to communicate 
 directly with the storage controller to carve up disks dynamically. xCAT will 
 find the a zFCP device in the specified pool that meets the size required, if 
 the WWPN and LUN are not given. The device address can be automatically assigned 
 by specifying 'auto'. The WWPN/LUN can be set as the LOADDEV in the directory
 entry if (1) is specified as the 'loaddev'.
 


\ **-**\ **-connectnic2guestlan**\  \ *device_address*\  \ *lan*\  \ *owner*\ 
 
 Connects a given network adapter to a GuestLAN.
 


\ **-**\ **-connectnic2vswitch**\  \ *device_address*\  \ *vswitch*\ 
 
 Connects a given network adapter to a VSwitch.
 


\ **-**\ **-copydisk**\  \ *target_address*\  \ *source_node*\  \ *source_address*\ 
 
 Copy a disk attached to a given virtual server.
 


\ **-**\ **-dedicatedevice**\  \ *virtual_device*\  \ *real_device*\  \ *mode*\ 
 
 Adds a dedicated device to a virtual machine's directory entry.
 


\ **-**\ **-deleteipl**\ 
 
 Deletes the IPL statement from the virtual machine's directory entry.
 


\ **-**\ **-disconnectnic**\  \ *device_address*\ 
 
 Disconnects a given network adapter.
 


\ **-**\ **-formatdisk**\  \ *disk_address*\  \ *multi_password*\ 
 
 Formats a disk attached to a given virtual server (only ECKD disks supported). The disk should not be linked to any other virtual server. This command is best used after add3390().
 


\ **-**\ **-grantvswitch**\  \ *vswitch*\ 
 
 Grant vSwitch access for given virtual machine.
 


\ **-**\ **-purgerdr**\ 
 
 Purge the reader belonging to the virtual machine
 


\ **-**\ **-removedisk**\  \ *device_address*\ 
 
 Removes a minidisk from a virtual machine's directory entry.
 


\ **-**\ **-removenic**\  \ *device_address*\ 
 
 Removes a network adapter from a virtual machine's directory entry.
 


\ **-**\ **-removeprocessor**\  \ *device_address*\ 
 
 Removes a processor from an active virtual machine's configuration.
 


\ **-**\ **-removeloaddev**\  \ *wwpn*\  \ *lun*\ 
 
 Removes the LOADDEV statement from a virtual machines's directory entry.
 


\ **-**\ **-removezfcp**\  \ *device_address*\  \ *wwpn*\  \ *lun*\ 
 
 Removes a given SCSI/FCP device belonging to the virtual machine.
 


\ **-**\ **-replacevs**\  \ *directory_entry*\ 
 
 Replaces a virtual machine's directory entry. The directory entry can be echoed into stdin or a text file.
 


\ **-**\ **-setipl**\  \ *ipl_target*\  \ *load_parms*\  \ *parms*\ 
 
 Sets the IPL statement for a given virtual machine.
 


\ **-**\ **-setpassword**\  \ *password*\ 
 
 Sets the password for a given virtual machine.
 


\ **-**\ **-setloaddev**\  \ *wwpn*\  \ *lun*\ 
 
 Sets the LOADDEV statement in the virtual machine's directory entry.
 


\ **-**\ **-undedicatedevice**\  \ *device_address*\ 
 
 Delete a dedicated device from a virtual machine's active configuration and directory entry.
 




************
RETURN VALUE
************


0 The command completed successfully.

1 An error has occurred.


********
EXAMPLES
********


PPC (with HMC) specific:
========================


1. To change the partition profile for lpar4 using the configuration data in the file /tmp/lparfile, enter:


.. code-block:: perl

  cat /tmp/lparfile | chvm lpar4


Output is similar to:


.. code-block:: perl

  lpar4: Success


2. To change the partition profile for lpar4 to the existing profile 'prof1', enter:


.. code-block:: perl

  chvm lpar4 -p prof1


Output is similar to:


.. code-block:: perl

  lpar4: Success


3. To change partition attributes for lpar4 by specifying attribute value pairs in command line, enter:


.. code-block:: perl

  chvm lpar4 max_mem=4096


Output is similar to:


.. code-block:: perl

  lpar4: Success



PPC (using Direct FSP Management) specific:
===========================================


1. For Power 775, to create a new partition lpar1 on the first octant of the cec cec01, lpar1 will use all the cpu and memory of the octant 0, enter:


.. code-block:: perl

  mkdef -t node -o lpar1 mgt=fsp groups=all parent=cec01   nodetype=lpar   hcp=cec01


then:


.. code-block:: perl

  chvm lpar1 --p775 -i 1 -m 1 -r 0:1


Output is similar to:


.. code-block:: perl

  lpar1: Success
  cec01: Please reboot the CEC cec1 firstly, and then use chvm to assign the I/O slots to the LPARs


2. For Power 775, to create new partitions lpar1-lpar8 on the whole cec cec01, each LPAR will use all the cpu and memory of each octant, enter:


.. code-block:: perl

  mkdef -t node -o lpar1-lpar8 nodetype=lpar  mgt=fsp groups=all parent=cec01  hcp=cec01


then:


.. code-block:: perl

  chvm lpar1-lpar8 --p775 -i 1 -m 1 -r 0-7:1


Output is similar to:


.. code-block:: perl

  lpar1: Success
  lpar2: Success
  lpar3: Success
  lpar4: Success
  lpar5: Success
  lpar6: Success
  lpar7: Success
  lpar8: Success
  cec01: Please reboot the CEC cec1 firstly, and then use chvm to assign the I/O slots to the LPARs


3. For Power 775 cec1, to create new partitions lpar1-lpar9, the lpar1 will use 25% CPU and 25% memory of the first octant, and lpar2 will use the left CPU and memory of the first octant. lpar3-lpar9 will use all the cpu and memory of each octant, enter:


.. code-block:: perl

  mkdef -t node -o lpar1-lpar9 mgt=fsp groups=all parent=cec1   nodetype=lpar   hcp=cec1


then:


.. code-block:: perl

  chvm lpar1-lpar9 --p775 -i 1 -m 1  -r 0:5,1-7:1


Output is similar to:


.. code-block:: perl

  lpar1: Success
  lpar2: Success
  lpar3: Success
  lpar4: Success
  lpar5: Success
  lpar6: Success
  lpar7: Success
  lpar8: Success
  lpar9: Success
  cec1: Please reboot the CEC cec1 firstly, and then use chvm to assign the I/O slots to the LPARs


4.To change the I/O slot profile for lpar4 using the configuration data in the file /tmp/lparfile, the I/O slots information is similar to:


.. code-block:: perl

  4: 514/U78A9.001.0123456-P1-C17/0x21010202/2/1
  4: 513/U78A9.001.0123456-P1-C15/0x21010201/2/1
  4: 512/U78A9.001.0123456-P1-C16/0x21010200/2/1


then run the command:


.. code-block:: perl

  cat /tmp/lparfile | chvm lpar4 --p775


5. To change the I/O slot profile for lpar1-lpar8 using the configuration data in the file /tmp/lparfile. Users can use the output of lsvm.and remove the cec information, and  modify the lpar id  before each I/O, and run the command as following:


.. code-block:: perl

  chvm lpar1-lpar8 --p775 -p /tmp/lparfile


6. To change the LPAR name, enter:


.. code-block:: perl

  chvm lpar1 lparname=test_lpar01


Output is similar to:


.. code-block:: perl

  lpar1: Success


7. For Normal Power machine, to modify the resource assigned to a partition:

Before modify, the resource assigned to node 'lpar1' can be shown with:


.. code-block:: perl

  lsvm lpar1


The output is similar to:


.. code-block:: perl

  lpar1: Lpar Processor Info:
  Curr Processor Min: 1.
  Curr Processor Req: 4.
  Curr Processor Max: 16.
  lpar1: Lpar Memory Info:
  Curr Memory Min: 1.00 GB(4 regions).
  Curr Memory Req: 4.00 GB(16 regions).
  Curr Memory Max: 32.00 GB(128 regions).
  lpar1: 1,513,U78AA.001.WZSGVU7-P1-T7,0x21010201,0xc03(USB Controller)
  lpar1: 1,512,U78AA.001.WZSGVU7-P1-T9,0x21010200,0x104(RAID Controller)
  lpar1: 1/2/2
  lpar1: 128.


To modify the resource assignment:


.. code-block:: perl

  chvm lpar1 vmcpus=1/2/16 vmmemory=1G/8G/32G add_physlots=0x21010202


The output is similar to:


.. code-block:: perl

  lpar1: Success


The resource information after modification is similar to:


.. code-block:: perl

  lpar1: Lpar Processor Info:
  Curr Processor Min: 1.
  Curr Processor Req: 2.
  Curr Processor Max: 16.
  lpar1: Lpar Memory Info:
  Curr Memory Min: 1.00 GB(4 regions).
  Curr Memory Req: 8.00 GB(32 regions).
  Curr Memory Max: 32.00 GB(128 regions).
  lpar1: 1,514,U78AA.001.WZSGVU7-P1-C19,0x21010202,0xffff(Empty Slot)
  lpar1: 1,513,U78AA.001.WZSGVU7-P1-T7,0x21010201,0xc03(USB Controller)
  lpar1: 1,512,U78AA.001.WZSGVU7-P1-T9,0x21010200,0x104(RAID Controller)
  lpar1: 1/2/2
  lpar1: 128.


Note: The physical I/O resources specified with \ *add_physlots*\  will be appended to the specified partition. The physical I/O resources which are not specified but belonged to the partition will not be removed. For more information about \ *add_physlots*\ , refer to lsvm(1)|lsvm.1.


VMware/KVM specific:
====================



.. code-block:: perl

  chvm vm1 -a 8,16 --mem 512 --cpus 2


Output is similar to:


.. code-block:: perl

  vm1: node successfully changed



zVM specific:
=============


1. To adds a 3390 (ECKD) disk to a virtual machine's directory entry:


.. code-block:: perl

   chvm gpok3 --add3390 POOL1 0101 2G MR


Output is similar to:


.. code-block:: perl

   gpok3: Adding disk 0101 to LNX3... Done


2. To add a network adapter to a virtual machine's directory entry:


.. code-block:: perl

   chvm gpok3 --addnic 0600 QDIO 3


Output is similar to:


.. code-block:: perl

   gpok3: Adding NIC 0900 to LNX3... Done


3. To connects a given network adapter to a GuestLAN:


.. code-block:: perl

   chvm gpok3 --connectnic2guestlan 0600 GLAN1 LN1OWNR


Output is similar to:


.. code-block:: perl

   gpok3: Connecting NIC 0600 to GuestLan GLAN1 on LN1OWNR... Done


4. To connects a given network adapter to a vSwitch:


.. code-block:: perl

   chvm gpok3 --connectnic2vswitch 0600 VSW1


Output is similar to:


.. code-block:: perl

   gpok3: Connecting NIC 0600 to vSwitch VSW1 on LNX3... Done


5. To removes a minidisk from a virtual machine's directory entry:


.. code-block:: perl

   chvm gpok3 --removedisk 0101


Output is similar to:


.. code-block:: perl

   gpok3: Removing disk 0101 on LNX3... Done


6. To Removes a network adapter from a virtual machine's directory entry:


.. code-block:: perl

   chvm gpok3 --removenic 0700


Output is similar to:


.. code-block:: perl

   gpok3: Removing NIC 0700 on LNX3... Done


7. To replaces a virtual machine's directory entry:


.. code-block:: perl

   cat /tmp/dirEntry.txt | chvm gpok3 --replacevs


Output is similar to:


.. code-block:: perl

   gpok3: Replacing user entry of LNX3... Done


8. To resize virtual machine's disk sdb to 10G and sdc to 15G:


.. code-block:: perl

   chvm gpok3 --resize sdb=10G,sdc=15G




*****
FILES
*****


/opt/xcat/bin/chvm


********
SEE ALSO
********


mkvm(1)|mkvm.1, lsvm(1)|lsvm.1, rmvm(1)|rmvm.1

