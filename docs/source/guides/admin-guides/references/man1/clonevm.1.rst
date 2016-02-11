
#########
clonevm.1
#########

.. highlight:: perl


****
NAME
****


\ **clonevm**\  - Create masters from virtual machines and virtual machines from masters.


********
SYNOPSIS
********


\ **clonevm**\  \ *noderange*\  [ \ **-t**\  \ *mastertobemade*\  | \ **-b**\  \ *master to base vms upon*\  ]  \ **-d|-**\ **-detached -f|-**\ **-force**\ 


***********
DESCRIPTION
***********


Command to promote a VM's current configuration and storage to a master as well as 
performing the converse operation of creating VMs based on a master.

By default, attempting to create a master from a running VM will produce an error. 
The force argument will request that a master be made of the VM anyway.

Also, by default a VM that is used to create a master will be rebased as a thin 
clone of that master. If the force argument is used to create a master of a powered
on vm, this will not be done.  Additionally, the detached option can be used to 
explicitly request that a clone not be tethered to a master image, allowing the 
clones to not be tied to the health of a master, at the cost of additional storage.

When promoting a VM's current state to master, all rleated virtual disks will be 
copied and merged with any prerequisite images.  A master will not be tethered to
other masters.


*******
OPTIONS
*******


\ **-h|-**\ **-help**\        Display usage message.

\ **-b**\               The master to base the clones upon

\ **-t**\               The target master to copy a single VM's state to

\ **-d**\               Explicitly request that the noderange be untethered from any masters.

\ **-f**\               Force cloning of a powered on VM.  Implies -d if the VM is on.

\ **-v|-**\ **-version**\     Command Version.

\ **-V|-**\ **-verbose**\     Verbose output.


************
RETURN VALUE
************


0: The command completed successfully.

Any other value: An error has occurred.


********
EXAMPLES
********



1. Creating a master named appserver from a node called vm1:
 
 
 .. code-block:: perl
 
   clonevm vm1 -t appserver
 
 


2. Cleating 30 VMs from a master named appserver:
 
 
 .. code-block:: perl
 
   clonevm vm1-vm30 -b appserver
 
 



*****
FILES
*****


/opt/xcat/bin/clonevm


********
SEE ALSO
********


chvm(1)|chvm.1, lsvm(1)|lsvm.1, rmvm(1)|rmvm.1, mkvm(1)|mkvm.1, vmmaster(5)|vmmaster.5

