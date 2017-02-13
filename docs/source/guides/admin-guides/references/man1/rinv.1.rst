
######
rinv.1
######

.. highlight:: perl


****
Name
****


\ **rinv**\  - Remote hardware inventory


****************
\ **Synopsis**\ 
****************


\ **rinv**\  [\ **-h | -**\ **-help | -v | -**\ **-version**\ ]

BMC/MPA specific:
=================


\ **rinv**\  \ *noderange*\  {\ **pci | model | serial | asset | vpd | mprom | deviceid | guid | firm | diag | dimm | bios | mparom | mac | all**\ }


OpenPOWER server specific:
==========================


\ **rinv**\  \ *noderange*\  {\ **model | serial | deviceid | uuid | guid | vpd | mprom | firm | all**\ }


PPC (with HMC) specific:
========================


\ **rinv**\  \ *noderange*\  {\ **bus | config | serial | model | firm | all**\ }


PPC (using Direct FSP Management) specific:
===========================================


\ **rinv**\  \ *noderange*\  {\ **firm**\ }

\ **rinv**\  \ *noderange*\  {\ **deconfig**\  [\ **-x**\ ]}


Blade specific:
===============


\ **rinv**\  \ *noderange*\  {\ **mtm | serial | mac | bios | diag | mprom | mparom | firm | all**\ }


VMware specific:
================


\ **rinv**\  \ *noderange*\  [\ **-t**\ ]


pdu specific:
=============


\ **rinv**\  \ *noderange*\ 


zVM specific:
=============


\ **rinv**\  \ *noderange*\  [\ **config | all**\ ]

\ **rinv**\  \ *noderange*\  [\ **-**\ **-diskpoolspace**\ ]

\ **rinv**\  \ *noderange*\  [\ **-**\ **-diskpool**\  \ *pool*\  \ *space*\ ]

\ **rinv**\  \ *noderange*\  [\ **-**\ **-fcpdevices**\  \ *state*\  \ *details*\ ]

\ **rinv**\  \ *noderange*\  [\ **-**\ **-diskpoolnames**\ ]

\ **rinv**\  \ *noderange*\  [\ **-**\ **-networknames**\ ]

\ **rinv**\  \ *noderange*\  [\ **-**\ **-network**\  \ *name*\ ]

\ **rinv**\  \ *noderange*\  [\ **-**\ **-ssi**\ ]

\ **rinv**\  \ *noderange*\  [\ **-**\ **-smapilevel**\ ]

\ **rinv**\  \ *noderange*\  [\ **-**\ **-wwpns**\  \ *fcp_channel*\ ]

\ **rinv**\  \ *noderange*\  [\ **-**\ **-zfcppool**\  \ *pool*\  \ *space*\ ]

\ **rinv**\  \ *noderange*\  [\ **-**\ **-zfcppoolnames**\ ]



*******************
\ **Description**\ 
*******************


\ **rinv**\   retrieves  hardware  configuration  information from the on-board
Service Processor for a single or range of nodes and groups.

Calling \ **rinv**\  for VMware will display the UUID/GUID, nuumber of CPUs, amount of memory, the MAC address and a list of Hard disks.  The output for each Hard disk includes the label, size and backing file location.


***************
\ **Options**\ 
***************



\ **pci**\ 
 
 Retrieves PCI bus information.
 


\ **bus**\ 
 
 List all buses for each I/O slot.
 


\ **config**\ 
 
 Retrieves number of processors, speed, total  memory,  and  DIMM
 locations.
 


\ **model**\ 
 
 Retrieves model number.
 


\ **serial**\ 
 
 Retrieves serial number.
 


\ **firm**\ 
 
 Retrieves firmware versions.
 


\ **deconfig**\ 
 
 Retrieves deconfigured resources. Deconfigured resources are hw components (cpus, memory, etc.) that have failed so the firmware has automatically turned those components off. This option is only capable of listing some of the deconfigured resources and should not be the only method used to check the hardware status.
 


\ **-x**\ 
 
 To output the raw information of deconfigured resources for CEC.
 


\ **asset**\ 
 
 Retrieves asset tag.  Usually it's the MAC address of eth0.
 


\ **vpd**\ 
 
 Same as specifying model, serial, deviceid, and mprom.
 


\ **diag**\ 
 
 Diagnostics information of firmware.
 


\ **mprom**\ 
 
 Retrieves mprom firmware level
 


\ **deviceid**\ 
 
 Retrieves device identification. Usually device, manufacturing and product ids.
 


\ **uuid**\ 
 
 Retrieves the universally unique identifier
 


\ **guid**\ 
 
 Retrieves the global unique identifier
 


\ **all**\ 
 
 All of the above.
 


\ **-h | -**\ **-help**\ 
 
 Print help.
 


\ **-v | -**\ **-version**\ 
 
 Print version.
 


\ **-t**\ 
 
 Set the values in the vm table to what vCenter has for the indicated nodes.
 


\ **zVM specific :**\ 


\ **-**\ **-diskpoolspace**\ 
 
 Calculates the total size of every known storage pool.
 


\ **-**\ **-diskpool**\  \ *pool*\  \ *space*\ 
 
 Lists the storage devices (ECKD and FBA) contained in a disk pool. Space can be: all, free, or used.
 


\ **-**\ **-fcpdevices**\  \ *state*\  \ *details*\ 
 
 Lists the FCP device channels that are active, free, or offline. State can be: active, free, or offline.
 


\ **-**\ **-diskpoolnames**\ 
 
 Lists the known disk pool names.
 


\ **-**\ **-networknames**\ 
 
 Lists the known network names.
 


\ **-**\ **-network**\  \ *name*\ 
 
 Shows the configuration of a given network device.
 


\ **-**\ **-ssi**\ 
 
 Obtain the SSI and system status.
 


\ **-**\ **-smapilevel**\ 
 
 Obtain the SMAPI level installed on the z/VM system.
 


\ **-**\ **-wwpns**\  \ *fcp_channel*\ 
 
 Query a given FCP device channel on a z/VM system and return a list of WWPNs.
 


\ **-**\ **-zfcppool**\  \ *pool*\  \ *space*\ 
 
 List the SCSI/FCP devices contained in a zFCP pool. Space can be: free or used.
 


\ **-**\ **-zfcppoolnames**\ 
 
 List the known zFCP pool names.
 



****************
\ **Examples**\ 
****************



1. To retrieve all information available from blade node4, enter:
 
 
 .. code-block:: perl
 
   rinv node5 all
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   node5: Machine Type/Model 865431Z
   node5: Serial Number 23C5030
   node5: Asset Tag 00:06:29:1F:01:1A
   node5: PCI Information
   node5:  Bus  VendID  DevID    RevID  Description              Slot Pass/Fail
   node5:  0    1166    0009     06     Host Bridge              0	PASS
   node5:  0    1166    0009     06     Host Bridge              0	PASS
   node5:  0    5333    8A22     04     VGA Compatible Controller0	PASS
   node5:  0    8086    1229     08     Ethernet Controller      0	PASS
   node5:  0    8086    1229     08     Ethernet Controller      0	PASS
   node5:  0    1166    0200     50     ISA Bridge               0	PASS
   node5:  0    1166    0211     00     IDE Controller           0	PASS
   node5:  0    1166    0220     04     Universal Serial Bus     0	PASS
   node5:  1    9005    008F     02     SCSI Bus Controller      0	PASS
   node5:  1    14C1    8043     03     Unknown Device Type      2	PASS
   node5: Machine Configuration Info
   node5: Number of Processors:
   node5: Processor Speed: 866 MHz
   node5: Total Memory:	  512 MB
   node5: Memory DIMM locations:  Slot(s)  3  4
 
 


2. To output the raw information of deconfigured resources for CEC cec01, enter:
 
 
 .. code-block:: perl
 
   rinv cec01 deconfig -x
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   cec01:
   <SYSTEM>
   <System_type>IH</System_type>
   <NODE>
   <Location_code>U78A9.001.0123456-P1</Location_code>
   <RID>800</RID>
   </NODE>
   </SYSTEM>
 
 


3.
 
 To retrieve 'config' information from the HMC-managed LPAR node3, enter:
 
 
 .. code-block:: perl
 
   rinv node3 config
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   node5: Machine Configuration Info
   node5: Number of Processors: 1
   node5: Total Memory (MB): 1024
 
 


4.
 
 To retrieve information about a VMware node vm1, enter:
 
 
 .. code-block:: perl
 
   rinv vm1
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   vm1: UUID/GUID: 42198f65-d579-fb26-8de7-3ae49e1790a7
   vm1: CPUs: 1
   vm1: Memory: 1536 MB
   vm1: Network adapter 1: 36:1b:c2:6e:04:02
   vm1: Hard disk 1 (d0): 9000 MB @ [nfs_192.168.68.21_vol_rc1storage_vmware] vm1_3/vm1.vmdk
   vm1: Hard disk 2 (d4): 64000 MB @ [nfs_192.168.68.21_vol_rc1storage_vmware] vm1_3/vm1_5.vmdk
 
 
 \ **zVM specific :**\ 
 


5.
 
 To list the defined network names available for a given node:
 
 
 .. code-block:: perl
 
   rinv pokdev61 --getnetworknames
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   pokdev61: LAN:QDIO SYSTEM GLAN1
   pokdev61: LAN:HIPERS SYSTEM GLAN2
   pokdev61: LAN:QDIO SYSTEM GLAN3
   pokdev61: VSWITCH SYSTEM VLANTST1
   pokdev61: VSWITCH SYSTEM VLANTST2
   pokdev61: VSWITCH SYSTEM VSW1
   pokdev61: VSWITCH SYSTEM VSW2
   pokdev61: VSWITCH SYSTEM VSW3
 
 


6.
 
 To list the configuration for a given network:
 
 
 .. code-block:: perl
 
   rinv pokdev61 --getnetwork GLAN1
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   pokdev61: LAN SYSTEM GLAN1        Type: QDIO    Connected: 1    Maxconn: INFINITE
   pokdev61:   PERSISTENT  UNRESTRICTED  IP                        Accounting: OFF
   pokdev61:   IPTimeout: 5                 MAC Protection: Unspecified
   pokdev61:   Isolation Status: OFF
 
 


7.
 
 To list the disk pool names available:
 
 
 .. code-block:: perl
 
   rinv pokdev61 --diskpoolnames
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   pokdev61: POOL1
   pokdev61: POOL2
   pokdev61: POOL3
 
 


8.
 
 List the configuration for a given disk pool:
 
 
 .. code-block:: perl
 
   rinv pokdev61 --diskpool POOL1 free
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   pokdev61: #VolID DevType StartAddr Size
   pokdev61: EMC2C4 3390-09 0001 10016
   pokdev61: EMC2C5 3390-09 0001 10016
 
 


9.
 
 List the known zFCP pool names.
 
 
 .. code-block:: perl
 
   rinv pokdev61 --zfcppoolnames
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   pokdev61: zfcp1
   pokdev61: zfcp2
   pokdev61: zfcp3
 
 


10.
 
 List the SCSI/FCP devices contained in a given zFCP pool:
 
 
 .. code-block:: perl
 
   rinv pokdev61 --zfcppool zfcp1
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   pokdev61: #status,wwpn,lun,size,range,owner,channel,tag
   pokdev61: used,500512345678c411,4014412100000000,2g,3B40-3B7F,ihost13,3b77,
   pokdev61: used,500512345678c411,4014412200000000,8192M,3B40-3B7F,ihost13,3b77,replace_root_device
   pokdev61: free,500512345678c411,4014412300000000,8g,3B40-3B7F,,,
   pokdev61: free,5005123456789411,4014412400000000,2g,3B40-3B7F,,,
   pokdev61: free,5005123456789411;5005123456789411,4014412600000000,2G,3B40-3B7F,,,
 
 



********
SEE ALSO
********


rpower(1)|rpower.1

