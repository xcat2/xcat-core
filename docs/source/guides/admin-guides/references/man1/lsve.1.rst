
######
lsve.1
######

.. highlight:: perl


****
NAME
****


\ **lsve**\  - Lists detail attributes for a virtual environment.


********
SYNOPSIS
********


\ **lsve**\  [\ **-t**\  \ *type*\ ] [\ **-m**\  \ *manager*\ ] [\ **-o**\  \ *object*\ ]


***********
DESCRIPTION
***********


The \ **lsve**\  command can be used to list a virtual environment for 
'Data Center', 'Cluster', 'Storage Domain', 'Network' and 'Template' objects.

The mandatory parameter \ **-m**\  \ *manager*\  is used to specify the address of the 
manager of virtual environment. xCAT needs it to access the RHEV manager.

The mandatory parameter \ **-t**\  \ *type*\  is used to specify the type of the target 
object.

Basically, \ **lsve**\  command supports three types of object: \ **dc**\ , \ **cl**\ , \ **sd**\ , \ **nw**\  
and \ **tpl**\ .

The parameter \ **-o object**\  is used to specify which object to list. If no \ **-o**\  is specified,
all the objects with the \ **-t**\  type will be displayed.


*******
OPTIONS
*******



\ **-h**\  Display usage message.



\ **-m**\  Specify the manager of the virtual environment.
 
 For RHEV, the FQDN (Fully Qualified Domain Name) of the rhev manager have to be specified.
 


\ **-o**\  The target object to display.



\ **-t**\  Specify the \ **type**\  of the target object.
 
 Supported types:
 
 
 .. code-block:: perl
 
   B<dc>  - Data Center (For type of 'dc', all the elements belongs to the data center will be listed.)
   B<cl>  - Cluster
   B<sd>  - Storage Domain (To get the status of Storage Doamin, show it from I<data center> it attached to.
   B<nw>  - Network
   B<tpl> - Template
 
 



************
RETURN VALUE
************


0  The command completed successfully.

1  An error has occurred.


********
EXAMPLES
********



1. To list the data center 'Default', enter:
 
 
 .. code-block:: perl
 
   lsve -t dc -m <FQDN of rhev manager> -o Default
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
    datacenters: [Default]
    description: The default Data Center
    state: up
    storageformat: v1
    storagetype: nfs
      clusters: [Default]
        cpu: Intel Westmere Family
        description: The default server cluster
        memory_hugepage: true
        memory_overcommit: 100
      storagedomains: [image]
        available: 55834574848
        committed: 13958643712
        ismaster: true
        status: active
        storage_add: <Address of storage domain>
        storage_format: v1
        storage_path: /vfsimg
        storage_type: nfs
        type: data
        used: 9663676416
      networks: [rhevm2]
        description:
        state: operational
        stp: false
      networks: [rhevm]
        description: Management Network
        state: operational
        stp: false
      templates: [Blank]
        bootorder: hd
        cpucore: 1
        cpusocket: 1
        creation_time: 2008-04-01T00:00:00.000-04:00
        display: spice
        memory: 536870912
        state: ok
        stateless: false
        type: desktop
 
 


2. To list the cluster 'Default', enter:
 
 
 .. code-block:: perl
 
   lsve -t cl -m <FQDN of rhev manager> -o Default
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
    cpu: Intel Westmere Family
    description: The default server cluster
    memory_hugepage: true
    memory_overcommit: 10
 
 


3. To list the Storage Domain 'image', enter:
 
 
 .. code-block:: perl
 
   lsve -t sd -m <FQDN of rhev manager> -o image
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
    storagedomains: [image]
      available: 55834574848
      committed: 13958643712
      ismaster: true
      status:
      storage_add: <Address of storage domain>
      storage_format: v1
      storage_path: /vfsimg
      storage_type: nfs
      type: data
      used: 9663676416
 
 


4. To list the network 'rhevm', enter:
 
 
 .. code-block:: perl
 
   lsve -t nw -m <FQDN of rhev manager> -o rhevm
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
    networks: [rhevm]
      description: Management Network
      state: operational
      stp: false
 
 


5. To list the template 'tpl01', enter:
 
 
 .. code-block:: perl
 
   lsve -t tpl -m <FQDN of rhev manager> -o tpl01
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
    templates: [tpl01]
      bootorder: network
      cpucore: 2
      cpusocket: 2
      creation_time: 2012-08-22T23:52:35.953-04:00
      display: vnc
      memory: 1999634432
      state: ok
      stateless: false
      type: server
 
 



*****
FILES
*****


/opt/xcat/bin/lsve


********
SEE ALSO
********


cfgve(1)|cfgve.1

