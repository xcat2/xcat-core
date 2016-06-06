
############
hypervisor.5
############

.. highlight:: perl


****
NAME
****


\ **hypervisor**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **hypervisor Attributes:**\   \ *node*\ , \ *type*\ , \ *mgr*\ , \ *interface*\ , \ *netmap*\ , \ *defaultnet*\ , \ *cluster*\ , \ *datacenter*\ , \ *preferdirect*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


Hypervisor parameters


**********************
hypervisor Attributes:
**********************



\ **node**\ 
 
 The node or static group name
 


\ **type**\ 
 
 The plugin associated with hypervisor specific commands such as revacuate
 


\ **mgr**\ 
 
 The virtualization specific manager of this hypervisor when applicable
 


\ **interface**\ 
 
 The definition of interfaces for the hypervisor. The format is [networkname:interfacename:bootprotocol:IP:netmask:gateway] that split with | for each interface
 


\ **netmap**\ 
 
 Optional mapping of useful names to relevant physical ports.  For example, 10ge=vmnic_16.0&vmnic_16.1,ge=vmnic1 would be requesting two virtual switches to be created, one called 10ge with vmnic_16.0 and vmnic_16.1 bonded, and another simply connected to vmnic1.  Use of this allows abstracting guests from network differences amongst hypervisors
 


\ **defaultnet**\ 
 
 Optionally specify a default network entity for guests to join to if they do not specify.
 


\ **cluster**\ 
 
 Specify to the underlying virtualization infrastructure a cluster membership for the hypervisor.
 


\ **datacenter**\ 
 
 Optionally specify a datacenter for the hypervisor to exist in (only applicable to VMWare)
 


\ **preferdirect**\ 
 
 If a mgr is declared for a hypervisor, xCAT will default to using the mgr for all operations.  If this is field is set to yes or 1, xCAT will prefer to directly communicate with the hypervisor if possible
 


\ **comments**\ 



\ **disable**\ 




********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

