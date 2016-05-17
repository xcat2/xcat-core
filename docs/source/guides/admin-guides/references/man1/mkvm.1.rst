
######
mkvm.1
######

.. highlight:: perl


****
NAME
****


\ **mkvm**\  - Creates HMC-, DFM-, IVM-, and zVM-managed partitions or other virtual machines.


********
SYNOPSIS
********


Common:
=======


\ **mkvm**\  [\ **-h**\ | \ **-**\ **-help**\ ]

\ **mkvm**\  [\ **-v**\ | \ **-**\ **-version**\ ]


For PPC (with HMC) specific:
============================


\ **mkvm**\  [\ **-V**\ | \ **-**\ **-verbose**\ ] \ *noderange*\  \ **-i**\  \ *id*\  \ **-l**\  \ *singlenode*\ 

\ **mkvm**\  [\ **-V**\ | \ **-**\ **-verbose**\ ] \ *noderange*\  \ **-c**\  \ *destcec*\  \ **-p**\  \ *profile*\ 

\ **mkvm**\  [\ **-V**\ | \ **-**\ **-verbose**\ ] \ *noderange*\  \ **-**\ **-full**\ 


For PPC (using Direct FSP Management) specific:
===============================================


\ **mkvm**\  \ *noderange*\  [\ **-**\ **-full**\ ]

\ **mkvm**\  \ *noderange*\  [\ **vmcpus=**\  \ *min/req/max*\ ] [\ **vmmemory=**\  \ *min/req/max*\ ] [\ **vmphyslots=**\  \ *drc_index1,drc_index2...*\ ] [\ **vmothersetting=**\  \ *hugepage:N,bsr:N*\ ] [\ **vmnics=**\  \ *vlan1[,vlan2..]*\ ] [\ **vmstorage=**\  \ *N|viosnode:slotid*\ ] [\ **-**\ **-vios**\ ]


For KVM:
========


\ **mkvm**\  \ *noderange*\  [\ **-s|-**\ **-size**\  \ *disksize*\ ] [\ **-**\ **-mem**\  \ *memsize*\ ] [\ **-**\ **-cpus**\  \ *cpucount*\ ] [\ **-f|-**\ **-force**\ ]


For Vmware:
===========


\ **mkvm**\  \ *noderange*\  [\ **-s | -**\ **-size**\  \ *disksize*\ ] [\ **-**\ **-mem**\  \ *memsize*\ ] [\ **-**\ **-cpus**\  \ *cpucount*\ ]


For zVM:
========


\ **mkvm**\  \ *noderange*\  [\ *directory_entry_file_path*\ ]

\ **mkvm**\  \ *noderange*\  [\ *source_virtual_machine*\ ] [\ **pool=**\  \ *disk_pool*\ ]



***********
DESCRIPTION
***********


For PPC (with HMC) specific:
============================


The first form of mkvm command creates new partition(s) with the same profile/resources as the partition specified by \ *singlenode*\ . The -i and \ *noderange*\  specify the starting numeric partition number and the \ *noderange*\  for the newly created partitions, respectively. The LHEA port numbers and the HCA index numbers will be automatically increased if they are defined in the source partition.

The second form of this command duplicates all the partitions from the source specified by \ *profile*\  to the destination specified by \ *destcec*\ . The source and destination CECs can be managed by different HMCs.

Please make sure the nodes in the \ *noderange*\  is defined in the \ *nodelist*\  table and the \ *mgt*\  is set to 'hmc' in the \ *nodehm*\  table before running this command.

Please note that the mkvm command currently only supports creating standard LPARs, not virtual LPARs working with VIOS server.


For PPC (using Direct FSP Management) specific:
===============================================


With option \ *full*\ , a partition using all the resources on a normal power machine will be created.

If no option is specified, a partition using the parameters specified with attributes such as 'vmcpus', 'vmmory', 'vmphyslots', 'vmothersetting', 'vmnics', 'vmstorage' will be created. Those attributes can either be specified with '\*def' commands running before or be specified with this command.


For KVM and Vmware:
===================


The mkvm command creates new virtual machine(s) with the \ *disksize*\  size of hard disk, \ *memsize*\  size of memory and \ *cpucount*\  number of cpu.

For KVM: If \ **-f | -**\ **-force**\  is specified, the storage will be destroyed first if it existed.


For zVM:
========


The first form of mkvm creates a new virtual machine based on a directory entry.

The second form of this creates a new virtual machine with the same profile/resources as the specified node (cloning).



*******
OPTIONS
*******



\ **-h|-**\ **-help**\ 
 
 Display usage message.
 


\ **-c**\ 
 
 The cec (fsp) name for the destination.
 


\ **-**\ **-cpus**\ 
 
 The cpu count which will be created for the kvm/vmware virtual machine.
 


\ **-**\ **-full**\ 
 
 Request to create a new full system partition for each CEC.
 


\ **vmcpus=**\  \ *value*\  \ **vmmemory=**\  \ *value*\  \ **vmphyslots=**\  \ *value*\  \ **vmothersetting=**\  \ *value*\  \ **vmnics=**\  \ *value*\  \ **vmstorage=**\  \ *value*\  [\ **-**\ **-vios**\ ]
 
 To specify the parameters which are used to create a partition. The \ *vmcpus*\ , \ *vmmemory*\  are necessay, and the value specified with this command have a more high priority. If the value of any of the three options is not specified, the corresponding value specified for the node object will be used. If any of the three attributes is neither specified with this command nor specified with the node object, error information will be returned. To reference to lsvm(1)|lsvm.1 for more information about 'drc_index' for \ *vmphyslots*\ .
 
 The option \ *vios*\  is used to specify the partition that will be created is a VIOS partition. If specified, the value for \ *vmstorage*\  shall be number which indicate the number of vSCSI server adapter will be created, and if no value specified for \ *vmphyslots*\ , all the physical slot of the power machine will be asigned to VIOS partition. If not specified, it shall be in form of \ *vios_name:server_slotid*\  to specify the vios and the virtual slot id of the vSCSI server adapter that will be connected from the Logical partition.
 


\ **-f|-**\ **-force**\ 
 
 If \ **-f|-**\ **-force**\  is specified, the storage will be destroyed first if it existed.
 


\ **-i**\ 
 
 Starting numeric id of the newly created partitions.
 


\ **-l**\ 
 
 The partition name of the source.
 


\ **-**\ **-mem**\ 
 
 The memory size which will be used for the new created kvm/vmware virtual machine. Unit is Megabyte.
 


\ **-p**\ 
 
 The file that contains the profiles for the source partitions.
 


\ **-s|-**\ **-size**\ 
 
 The size of storage which will be created for the kvm/vmware virtual machine.
 


\ **-v|-**\ **-version**\ 
 
 Command Version.
 


\ **-V|-**\ **-verbose**\ 
 
 Verbose output.
 



************
RETURN VALUE
************


0 The command completed successfully.

1 An error has occurred.


********
EXAMPLES
********


1. To create a new HMC-managed partition lpar5 based on the profile/resources of lpar4, enter:


.. code-block:: perl

  mkdef -t node -o lpar5 mgt=hmc groups=all


then:


.. code-block:: perl

  mkvm lpar5 -i 5 -l lpar4


Output is similar to:


.. code-block:: perl

  lpar5: Success


2. To create new HMC-managed partitions lpar5-lpar8 based on the profile/resources of lpar4, enter:


.. code-block:: perl

  mkdef -t node -o lpar5-lpar8 mgt=hmc groups=all


then:


.. code-block:: perl

  mkvm lpar5-lpar8 -i 5 -l lpar4


Output is similar to:


.. code-block:: perl

  lpar5: Success
  lpar6: Success
  lpar7: Success
  lpar8: Success


3. To duplicate all the HMC-managed partitions associated with cec01 on cec02, first save the lpars from cec01 to a file:


.. code-block:: perl

  lsvm lpar01-lpar04 > /tmp/myprofile


then create lpars on cec02:


.. code-block:: perl

  mkvm lpar05-lpar08 -c cec02 -p /tmp/myprofile


Output is similar to:


.. code-block:: perl

  lpar5: Success
  lpar6: Success
  lpar7: Success
  lpar8: Success


4. To duplicate all the HMC-managed partitions associated with cec01 on cec02, one is for cec01, the other is for cec02:


.. code-block:: perl

  mkdef -t node -o lpar5,lpar6 mgt=hmc groups=all
  chtab node=lpar5 ppc.parent=cec01
  chtab node=lpar6 ppc.parent=cec02


then create lpars on cec01 and cec02:


.. code-block:: perl

  mkvm lpar5,lpar6 --full


Output is similar to:


.. code-block:: perl

  lpar5: Success
  lpar6: Success


5. To create a new zVM virtual machine (gpok3) based on a directory entry:


.. code-block:: perl

  mkvm gpok3 /tmp/dirEntry.txt


Output is similar to:


.. code-block:: perl

  gpok3: Creating user directory entry for LNX3... Done


6. To clone a new zVM virtual machine with the same profile/resources as the specified node:


.. code-block:: perl

  mkvm gpok4 gpok3 pool=POOL1


Output is similar to:


.. code-block:: perl

  gpok4: Cloning gpok3
  gpok4: Linking source disk (0100) as (1100)
  gpok4: Linking source disk (0101) as (1101)
  gpok4: Stopping LNX3... Done
  gpok4: Creating user directory entry
  gpok4: Granting VSwitch (VSW1) access for gpok3
  gpok4: Granting VSwitch (VSW2) access for gpok3
  gpok4: Adding minidisk (0100)
  gpok4: Adding minidisk (0101)
  gpok4: Disks added (2). Disks in user entry (2)
  gpok4: Linking target disk (0100) as (2100)
  gpok4: Copying source disk (1100) to target disk (2100) using FLASHCOPY
  gpok4: Mounting /dev/dasdg1 to /mnt/LNX3
  gpok4: Setting network configuration
  gpok4: Linking target disk (0101) as (2101)
  gpok4: Copying source disk (1101) to target disk (2101) using FLASHCOPY
  gpok4: Powering on
  gpok4: Detatching source disk (0101) at (1101)
  gpok4: Detatching source disk (0100) at (1100)
  gpok4: Starting LNX3... Done


7. To create a new kvm/vmware virtual machine with 10G storage, 2048M memory and 2 cpus.


.. code-block:: perl

  mkvm vm1 -s 10G --mem 2048 --cpus 2


8. To create a full partition on normal power machine.

First, define a node object:


.. code-block:: perl

  mkdef -t node -o lpar1 mgt=fsp cons=fsp nodetype=ppc,osi id=1 hcp=cec parent=cec hwtype=lpar groups=lpar,all


Then, create the partion on the specified cec.


.. code-block:: perl

  mkvm lpar1 --full


The output is similar to:


.. code-block:: perl

  lpar1: Done


To query the resources allocated to node 'lpar1'


.. code-block:: perl

  lsvm lpar1


The output is similar to:


.. code-block:: perl

   lpar1: Lpar Processor Info:
   Curr Processor Min: 1.
   Curr Processor Req: 16.
   Curr Processor Max: 16.
   lpar1: Lpar Memory Info:
   Curr Memory Min: 0.25 GB(1 regions).
   Curr Memory Req: 30.75 GB(123 regions).
   Curr Memory Max: 32.00 GB(128 regions).
   lpar1: 1,519,U78AA.001.WZSGVU7-P1-C7,0x21010207,0xffff(Empty Slot)
   lpar1: 1,518,U78AA.001.WZSGVU7-P1-C6,0x21010206,0xffff(Empty Slot)
   lpar1: 1,517,U78AA.001.WZSGVU7-P1-C5,0x21010205,0xffff(Empty Slot)
   lpar1: 1,516,U78AA.001.WZSGVU7-P1-C4,0x21010204,0xffff(Empty Slot)
   lpar1: 1,514,U78AA.001.WZSGVU7-P1-C19,0x21010202,0xffff(Empty Slot)
   lpar1: 1,513,U78AA.001.WZSGVU7-P1-T7,0x21010201,0xc03(USB Controller)
   lpar1: 1,512,U78AA.001.WZSGVU7-P1-T9,0x21010200,0x104(RAID Controller)
   lpar1: 1/2/2
   lpar1: 256.


Note: The 'parent' attribute for node 'lpar1' is the object name of physical power machine that the full partition will be created on.

9. To create a partition using some of the resources on normal power machine.

Option 1:

After a node object is defined, the resources that will be used for the partition shall be specified like this:


.. code-block:: perl

  chdef lpar1 vmcpus=1/4/16 vmmemory=1G/4G/32G vmphyslots=0x21010201,0x21010200 vmothersetting=bsr:128,hugepage:2


Then, create the partion on the specified cec.


.. code-block:: perl

  mkvm lpar1


Option 2:


.. code-block:: perl

  mkvm lpar1 vmcpus=1/4/16 vmmemory=1G/4G/32G vmphyslots=0x21010201,0x21010200 vmothersetting=bsr:128,hugepage:2


The outout is similar to:


.. code-block:: perl

  lpar1: Done


Note: The 'vmplyslots' specify the drc index of the physical slot device. Every drc index shall be delimited with ','. The 'vmothersetting' specify two kinds of resource, bsr(Barrier Synchronization Register) specified the num of BSR arrays, hugepage(Huge Page Memory) specified the num of huge pages.

To query the resources allocated to node 'lpar1'


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


10. To create a vios partition using some of the resources on normal power machine.


.. code-block:: perl

  mkvm viosnode vmcpus=1/4/16 vmmemory=1G/4G/32G vmphyslots=0x21010201,0x21010200 vmnics=vlan1 vmstorage=5 --vios


The resouces for the node is similar to:


.. code-block:: perl

  viosnode: Lpar Processor Info:
  Curr Processor Min: 1.
  Curr Processor Req: 4.
  Curr Processor Max: 16.
  viosnode: Lpar Memory Info:
  Curr Memory Min: 1.00 GB(4 regions).
  Curr Memory Req: 4.00 GB(16 regions).
  Curr Memory Max: 32.00 GB(128 regions).
  viosnode: 1,513,U78AA.001.WZSGVU7-P1-T7,0x21010201,0xc03(USB Controller)
  viosnode: 1,512,U78AA.001.WZSGVU7-P1-T9,0x21010200,0x104(RAID Controller)
  viosnode: 1,0,U8205.E6B.0612BAR-V1-C,0x30000000,vSerial Server
  viosnode: 1,1,U8205.E6B.0612BAR-V1-C1,0x30000001,vSerial Server
  viosnode: 1,3,U8205.E6B.0612BAR-V1-C3,0x30000003,vEth (port_vlanid=1,mac_addr=4211509276a7)
  viosnode: 1,5,U8205.E6B.0612BAR-V1-C5,0x30000005,vSCSI Server
  viosnode: 1,6,U8205.E6B.0612BAR-V1-C6,0x30000006,vSCSI Server
  viosnode: 1,7,U8205.E6B.0612BAR-V1-C7,0x30000007,vSCSI Server
  viosnode: 1,8,U8205.E6B.0612BAR-V1-C8,0x30000008,vSCSI Server
  viosnode: 1,9,U8205.E6B.0612BAR-V1-C9,0x30000009,vSCSI Server
  viosnode: 0/0/0
  viosnode: 0.



*****
FILES
*****


/opt/xcat/bin/mkvm


********
SEE ALSO
********


chvm(1)|chvm.1, lsvm(1)|lsvm.1, rmvm(1)|rmvm.1

