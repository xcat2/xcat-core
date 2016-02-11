
#######
cfgve.1
#######

.. highlight:: perl


****
NAME
****


\ **cfgve**\  - Configure the elements for a virtual environment.


********
SYNOPSIS
********


\ **cfgve**\  \ **-t dc -m**\  \ *manager*\  \ **-o**\  \ *object*\  [\ **-c**\  \ **-k nfs**\  | \ **localfs**\  | \ **-r**\ ]

\ **cfgve**\  \ **-t cl -m**\  \ *manager*\  \ **-o**\  \ *object*\  [\ **-c -p**\  \ *cpu type*\  | \ **-r -f**\ ]

\ **cfgve**\  \ **-t sd -m**\  \ *manager*\  \ **-o**\  \ *object*\  [\ **-c**\  | \ **-g**\  | \ **-s**\  | \ **-a**\  | \ **-b**\  | \ **-r**\  \ **-f**\ ]

\ **cfgve**\  \ **-t nw -m**\  \ *manager*\  \ **-o**\  \ *object*\  [\ **-c**\  \ **-d**\  \ *data center*\  \ **-n**\  \ *vlan ID*\  | \ **-a**\  \ **-l**\  \ *cluster*\  | \ **-b**\  | \ **-r**\ ]

\ **cfgve**\  \ **-t tpl -m**\  \ *manager*\  \ **-o**\  \ *object*\  [\ **-r**\ ]


***********
DESCRIPTION
***********


The \ **cfgve**\  command can be used to configure a virtual environment for 
'Storage Domain', 'Network' and 'Template' objects.

The mandatory parameter \ **-m**\  \ *manager*\  is used to specify the address of the 
manager of virtual environment. xCAT needs it to access the RHEV manager.

The mandatory parameter \ **-t**\  \ *type*\  is used to specify the type of the target 
object.

Basically, \ **cfgve**\  command supports five types of object: \ **dc**\ , \ **cl**\ , 
\ **sd**\ , \ **nw**\  and \ **tpl**\ .


\ **dc**\  - The \ **create**\  and \ **remove**\  operations are supported.

\ **cl**\  - The \ **create**\  and \ **remove**\  operations are supported.

\ **sd**\   - The \ **create**\ , \ **attach**\ , \ **detach**\ , \ **activate**\ , 
\ **deactivate**\  and \ **remove**\  operations are supported.

\ **nw**\   - The \ **create**\ , \ **attach**\ , \ **detach**\  and \ **remove**\  operations are supported.

\ **tpl**\  - The \ **remove**\  operation is supported.

The mandatory parameter \ **-o**\  \ *object*\  is used to specify which object to configure.


*******
OPTIONS
*******



\ **-a**\  To attach the target object.



\ **-b**\  To detach the target object.



\ **-c**\  To create the target object.
 
 For creating of \ **Storage Domain**\ , the target storage domain will be created 
 first, then attached to data center and activated.
 
 The parameters that used to create the storage domain are gotten 
 from 'virtsd' table. The detail parameters in the virtsd table:
 
 
 \ **virtsd.node**\  - The name of the storage domain.
 
 \ **virtsd.sdtype**\  - The type of storage domain. Valid value: data, iso, export. 
 Default value is 'data'.
 
 \ **virtsd.stype**\  - The storage type. "nfs" or "localfs".
 
 \ **virtsd.location**\  - The location of the storage. 
 \ **nfs**\ : Format: [nfsserver:nfspath]. 
 The NFS export directory must be configured for read write access and must 
 be owned by vdsm:kvm.
 \ **localfs**\ : "/data/images/rhev" is set by default.
 
 \ **virtsd.host**\  - A host must be specified for a storage doamin as SPM 
 (Storage Pool Manager) when initialize the storage domain. The role of SPM 
 may be migrated to other host by rhev-m during the running of the datacenter 
 (For example, when the current SPM encountered issue or going to maintenance 
 status.
 
 \ **virtsd.datacenter**\  - The storage will be attached to. 'Default' data center 
 is the default value.
 


\ **-d**\  \ *data center*\ 
 
 The name of data center.
 
 Specify the 'Data Center' that will be used for the object to be attached to. 
 It is used by <nw> type.
 


\ **-f**\  It can be used with \ **-r**\  to remove the target object by force.
 
 For removing of \ **Storage Domain**\ , if \ **-f**\  is specified, the storage domain will be deactivated and detached from data center before the removing.
 


\ **-g**\  To activate the target object.



\ **-h**\  Display usage message.



\ **-k**\  \ *storage type*\ 
 
 To specify the type of the storage type when creating the data center.
 
 Supported type: nfs; localfs.
 


\ **-l**\  \ *cluster*\ 
 
 Specify the cluster for the network to attach to.
 


\ **-m**\  \ *manager*\ 
 
 Specify the manager of the virtual environment.
 
 For RHEV, the FQDN (Fully Qualified Domain Name) of the rhev manager have 
 to be specified.
 


\ **-n**\  \ *vlan ID*\ 
 
 To specify the vlan number when creating a network.
 


\ **-o**\  \ *object*\ 
 
 The name of the target object.
 


\ **-p**\  \ *cpu type*\ 
 
 To specify the cpu type when creating the cluster.
 \ **Intel Penryn Family**\  is default type.
 
 Supported type: \ **Intel Conroe Family**\ , \ **Intel Penryn Family**\ ,
 \ **Intel Nehalem Family**\ , \ **Intel Westmere Family**\ , \ **AMD Opteron G1**\ ,
 \ **AMD Opteron G2**\ , \ **AMD Opteron G3**\ 
 


\ **-r**\  To remove the target object.
 
 For removing of \ **Storage Domain**\ , the storage space will be formatted after removing.
 


\ **-s**\  To deactivate the target object.



\ **-t**\  \ *type*\ 
 
 Specify the \ **type**\  of the target object.
 
 Supported types:
  \ **dc**\   - Data Center
  \ **cl**\   - Cluster
  \ **sd**\   - Storage Domain
  \ **nw**\   - Network
  \ **tpl**\  - Template
 



************
RETURN VALUE
************


0  The command completed successfully.

1  An error has occurred.


********
EXAMPLES
********



1. To create the Storage Domain 'sd1', enter:
 
 
 .. code-block:: perl
 
   cfgve -t sd -m <FQDN of rhev manager> -o sd1 -c
 
 


2. To deactivate the Storage Domain 'sd1' from data center, enter:
 
 
 .. code-block:: perl
 
   cfgve -t sd -m <FQDN of rhev manager> -o sd1 -s
 
 


3. To remove the Storage Domain 'sd1', enter:
 
 
 .. code-block:: perl
 
   cfgve -t sd -m <FQDN of rhev manager> -o sd1 -r
 
 


4. To create the network 'nw1', enter:
 
 
 .. code-block:: perl
 
   cfgve -t nw -m <FQDN of rhev manager> -o nw1 -c
 
 


5. To remove the template 'tpl01', enter:
 
 
 .. code-block:: perl
 
   cfgve -t tpl -m <FQDN of rhev manager> -o tpl01 -r
 
 



*****
FILES
*****


/opt/xcat/bin/cfgve


********
SEE ALSO
********


lsve(1)|lsve.1

