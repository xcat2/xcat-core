
##############
chhypervisor.1
##############

.. highlight:: perl


****
NAME
****


\ **chhypervisor**\  - Configure the virtualization hosts.


********
SYNOPSIS
********


\ **RHEV specific :**\ 


\ **chhypervisor**\  \ *noderange*\  [\ **-a**\ ]

\ **chhypervisor**\  \ *noderange*\  [\ **-n**\ ]

\ **chhypervisor**\  \ *noderange*\  [\ **-p**\ ]

\ **chhypervisor**\  \ *noderange*\  [\ **-e**\ ]

\ **chhypervisor**\  \ *noderange*\  [\ **-d**\ ]

\ **zVM specific :**\ 


\ **chhypervisor**\  \ *noderange*\  [\ **-**\ **-adddisk2pool**\  \ *function*\  \ *region*\  \ *volume*\  \ *group*\ ]

\ **chhypervisor**\  \ *noderange*\  [\ **-**\ **-addscsi**\  \ *device_number*\  \ *device_path*\  \ *option*\  \ *persist*\ ]

\ **chhypervisor**\  \ *noderange*\  [\ **-**\ **-addvlan**\  \ *name*\  \ *owner*\  \ *type*\  \ *transport*\ ]

\ **chhypervisor**\  \ *noderange*\  [\ **-**\ **-addvswitch**\  \ *name*\  \ *osa_dev_addr*\  \ *osa_exp_adapter*\  \ *controller*\  \ *connect (0, 1, or 2)*\  \ *memory_queue*\  \ *router*\  \ *transport*\  \ *vlan_id*\  \ *port_type*\  \ *update*\  \ *gvrp*\  \ *native_vlan*\ ]

\ **chhypervisor**\  \ *noderange*\  [\ **-**\ **-addzfcp2pool**\  \ *pool*\  \ *status*\  \ *wwpn*\  \ *lun*\  \ *size*\  \ *owner*\ ]

\ **chhypervisor**\  \ *noderange*\  [\ **-**\ **-removediskfrompool**\  \ *function*\  \ *region*\  \ *group*\ ]

\ **chhypervisor**\  \ *noderange*\  [\ **-**\ **-removescsi**\  \ *device_number*\  \ *persist (YES or NO)*\ ]

\ **chhypervisor**\  \ *noderange*\  [\ **-**\ **-removevlan**\  \ *name*\  \ *owner*\ ]

\ **chhypervisor**\  \ *noderange*\  [\ **-**\ **-removevswitch**\  \ *name*\ ]

\ **chhypervisor**\  \ *noderange*\  [\ **-**\ **-removezfcpfrompool**\  \ *pool*\  \ *lun*\  \ *wwpn*\ ]

\ **chhypervisor**\  \ *noderange*\  [\ **-**\ **-smcli**\  \ *function*\  \ *arguments*\ ]


***********
DESCRIPTION
***********


The \ **chhypervisor**\  command can be used to configure the RHEV-h.

The rhev-h host will register to the rhev-m automatically, but admin needs to 
approve the host can be added to the 'cluster' with \ **-a**\  flag .

After registering, the network interfaces of host need to be added to the 'network' of 
RHEV. And the power management for the host should be configured so that
rhev-m could make proper decision when certain host encountered error.

The \ **chhypervisor**\  command can also be used to configure the zVM host.

For each host, an entry should be added to the hypervisor table:

The columns of hypervisor table:


\ **hypervisor.node**\  - rhev-h host name or zVM host name (lower-case).

\ **hypervisor.type**\  - Must be set to 'rhevh' or 'zvm'.

\ **hypervisor.mgr**\  - The rhev manager (The FQDN of rhev-m server) for the host.

\ **hypervisor.interface**\  - The configuration for the nics. Refer to \ **-n**\ .

\ **hypervisor.cluster**\  - The cluster that the host will be added to. The 
default is 'Default' cluster if not specified.


*******
OPTIONS
*******


RHEV specific :
===============



\ **-a**\  Approve the host that to be added to cluster.
 
 Before approve, the status of the host must be 'pending_approval'.
 


\ **-n**\  Configure the network interfaces for the host.
 
 Note: This operation only can be run when host is in 'maintenance mode'. 
 Use \ **-d**\  to switch the host to 'maintenance' mode.
 
 The interfaces which configured in hypervisor.interface will be added
 to the network of RHEV.
 
 The format of hypervisor.interface is multiple [network:interfacename:
 protocol:IP:netmask:gateway] sections separated with '|'. For example: 
 [rhevm2:eth0:static:10.1.0.236:255.255.255.0:0.0.0.0].
 
 
 \ **network**\  - The logic network which has been created by 'cfgve -t nw' 
 or the default management network 'rhevm'.
 
 \ **interfacename**\  - Physical network name: 'eth0','eth1'...
 
 \ **protocol**\  - To identify which boot protocol to use for the interface: dhcp 
 or static.
 
 \ **IP**\  - The IP address for the interface.
 
 \ **netmask**\  - The network mask for the interface.
 
 \ **gateway**\  - The gateay for the interface. This field only can be set when 
 the interface is added to 'rhevm' network.
 


\ **-p**\  Configure the power management for the host.
 
 The power management must be configured for the rhev-h host to make the 
 rhev-m to monitor the power status of the host, so that when certain host 
 failed to function, rhev-m will fail over certain role like SPM to other active host.
 
 For rack mounted server, the bmc IP and user:password need to be set for the 
 power management (These parameters are gotten from ipmi table). rhev-m uses the 
 ipmi protocol to get the power status of the host.
 


\ **-e**\  To activate the host.



\ **-d**\  To deactivate the host to maintenance mode.



\ **-h**\  Display usage message.




zVM specific :
==============



\ **-**\ **-adddisk2pool**\  \ *function*\  \ *region*\  \ *volume*\  \ *group*\ 
 
 Add a disk to a disk pool defined in the EXTENT CONTROL. Function type can be 
 either: (4) Define region as full volume and add to group OR (5) Add existing 
 region to group. If the volume already exists in the EXTENT CONTROL, use 
 function 5. If the volume does not exist in the EXTENT CONTROL, but is attached
 to SYSTEM, use function 4.
 


\ **-**\ **-addscsi**\  \ *device_number*\  \ *device_path*\  \ *option*\  \ *persist*\ 
 
 Dynamically add a SCSI disk to a running z/VM system.
 


\ **-**\ **-addvlan**\  \ *name*\  \ *owner*\  \ *type*\  \ *transport*\ 
 
 Create a virtual network LAN.
 


\ **-**\ **-addvswitch**\  \ *name*\  \ *osa_dev_addr*\  \ *osa_exp_adapter*\  \ *controller*\  \ *connect (0, 1, or 2)*\  \ *memory_queue*\  \ *router*\  \ *transport*\  \ *vlan_id*\  \ *port_type*\  \ *update*\  \ *gvrp*\  \ *native_vlan*\ 
 
 Create a virtual switch.
 


\ **-**\ **-addzfcp2pool**\  \ *pool*\  \ *status*\  \ *wwpn*\  \ *lun*\  \ *size*\  \ *owner*\ 
 
 Add a zFCP device to a device pool defined in xCAT. The device must have been 
 carved up in the storage controller and configured with a WWPN/LUN before it 
 can be added to the xCAT storage pool. z/VM does not have the ability to 
 communicate directly with the storage controller to carve up disks dynamically.
 


\ **-**\ **-removediskfrompool**\  \ *function*\  \ *region*\  \ *group*\ 
 
 Remove a disk from a disk pool defined in the EXTENT CONTROL. Function type can 
 be either: (1) Remove region, (2) Remove region from group, (3) Remove region 
 from all groups, OR (7) Remove entire group .
 


\ **-**\ **-removescsi**\  \ *device_number*\  \ *persist (YES or NO)*\ 
 
 Delete a real SCSI disk.
 


\ **-**\ **-removevlan**\  \ *name*\  \ *owner*\ 
 
 Delete a virtual network LAN.
 


\ **-**\ **-removevswitch**\  \ *name*\ 
 
 Delete a virtual switch.
 


\ **-**\ **-removezfcpfrompool**\  \ *pool*\  \ *lun*\ 
 
 Remove a zFCP device from a device pool defined in xCAT.
 


\ **-**\ **-smcli**\  \ *function*\  \ *arguments*\ 
 
 Execute a SMAPI function. A list of APIs supported can be found by using the 
 help flag, e.g. chhypervisor pokdev61 --smcli -h. Specific arguments associated 
 with a SMAPI function can be found by using the help flag for the function, 
 e.g. chhypervisor pokdev61 --smcli Image_Query_DM -h. Only z/VM 6.2 and older 
 SMAPI functions are supported at this time. Additional SMAPI functions will be 
 added in subsequent zHCP versions.
 




************
RETURN VALUE
************


0  The command completed successfully.

1  An error has occurred.


********
EXAMPLES
********


RHEV specific :
===============



1. To approve the host 'host1', enter:
 
 
 .. code-block:: perl
 
   chhypervisor host1 -a
 
 


2. To configure the network interface for the host 'host1', enter:
 
 
 .. code-block:: perl
 
   chhypervisor host1 -n
 
 


3. To configure the power management for the host 'host1', enter:
 
 
 .. code-block:: perl
 
   chhypervisor host1 -p
 
 


4. To activate the host 'host1', enter:
 
 
 .. code-block:: perl
 
   chhypervisor host1 -e
 
 


5. To deactivate the host 'host1', enter:
 
 
 .. code-block:: perl
 
   chhypervisor host1 -d
 
 



zVM specific :
==============



1. To add a disk to a disk pool defined in the EXTENT CONTROL, enter:
 
 
 .. code-block:: perl
 
   chhypervisor pokdev61 --adddisk2pool 4 DM1234 DM1234 POOL1
 
 


2. To add a zFCP device to a device pool defined in xCAT, enter:
 
 
 .. code-block:: perl
 
   chhypervisor pokdev61 --addzfcp2pool zfcp1 free 500501234567C890 4012345600000000 8G
 
 


3. To remove a region from a group in the EXTENT CONTROL, enter:
 
 
 .. code-block:: perl
 
   chhypervisor pokdev61 --removediskfrompool 2 DM1234 POOL1
 
 


4. To remove a zFCP device from a device pool defined in xCAT, enter:
 
 
 .. code-block:: perl
 
   chhypervisor pokdev61 --removezfcpfrompool zfcp1 4012345600000000 500501234567C890
 
 


5. To execute a SMAPI function (Image_Query_DM), enter:
 
 
 .. code-block:: perl
 
   chhypervisor pokdev61 --smcli Image_Query_DM -T LNX3
 
 




*****
FILES
*****


/opt/xcat/bin/chhypervisor

