
######
rmvm.1
######

.. highlight:: perl


****
NAME
****


\ **rmvm**\  - Removes HMC-, DFM-, IVM-, KVM-, VMware- and zVM-managed partitions or virtual machines.


********
SYNOPSIS
********


\ **rmvm [-h| -**\ **-help]**\ 

\ **rmvm [-v| -**\ **-version]**\ 

\ **rmvm [-V| -**\ **-verbose]**\  \ *noderange*\  \ **[-r] [-**\ **-service]**\ 

For KVM and VMware:
===================


\ **rmvm [-p] [-f]**\  \ *noderange*\ 


PPC (using Direct FSP Management) specific:
===========================================


\ **rmvm [-p]**\  \ *noderange*\ 



***********
DESCRIPTION
***********


The rmvm command removes the partitions specified in noderange. If noderange is an CEC, all the partitions associated with that CEC will be removed. Note that removed partitions are automatically removed from the xCAT database. For IVM-managed systems, care must be taken to not remove the VIOS partition, or all the associated partitions will be removed as well.

For DFM-managed (short For Direct FSP Management mode) normal power machines, only partitions can be removed. No options is needed.


*******
OPTIONS
*******


\ **-h|-**\ **-help**\           Display usage message.

\ **-v|-**\ **-version**\        Command Version.

\ **-V|-**\ **-verbose**\        Verbose output.

\ **-r**\           Retain the data object definitions of the nodes.

\ **-**\ **-service**\    Remove the service partitions of the specified CECs.

\ **-p**\           KVM: Purge the existence of the VM from persistant storage.  This will erase all storage related to the VM in addition to removing it from the active virtualization configuration. PPC: Remove the specified partiton on normal power machine.

\ **-f**\           Force remove the VM, even if the VM appears to be online.  This will bring down a live VM if requested.


************
RETURN VALUE
************


0 The command completed successfully.

1 An error has occurred.


********
EXAMPLES
********


1. To remove the HMC-managed partition lpar3, enter:


.. code-block:: perl

  rmvm lpar3


Output is similar to:


.. code-block:: perl

  lpar3: Success


2. To remove all the HMC-managed partitions associated with CEC cec01, enter:


.. code-block:: perl

  rmvm cec01


Output is similar to:


.. code-block:: perl

  lpar1: Success
  lpar2: Success
  lpar3: Success


3. To remove the HMC-managed service partitions of the specified CEC cec01 and cec02, enter:


.. code-block:: perl

  rmvm cec01,cec02 --service


Output is similar to:


.. code-block:: perl

  cec01: Success
  cec02: Success


4. To remove the HMC-managed partition lpar1, but retain its definition, enter:


.. code-block:: perl

  rmvm lpar1 -r


Output is similar to:


.. code-block:: perl

  lpar1: Success


5. To remove a zVM virtual machine:


.. code-block:: perl

  rmvm gpok4


Output is similar to:


.. code-block:: perl

  gpok4: Deleting virtual server LNX4... Done


6. To remove a DFM-managed partition on normal power machine:


.. code-block:: perl

  rmvm lpar1


Output is similar to:


.. code-block:: perl

  lpar1: Done



*****
FILES
*****


/opt/xcat/bin/rmvm


********
SEE ALSO
********


mkvm(1)|mkvm.1, lsvm(1)|lsvm.1, chvm(1)|chvm.1

