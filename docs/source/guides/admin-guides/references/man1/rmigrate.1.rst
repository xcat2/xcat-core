
##########
rmigrate.1
##########

.. highlight:: perl


****
Name
****


\ **rmigrate**\  - Execute migration of a guest VM between hosts/hypervisors


****************
\ **Synopsis**\ 
****************


\ **rmigrate**\  \ *noderange*\  \ *target_host*\ 

For zVM:
========


\ **rmigrate**\  \ *noderange*\  [\ **destination=**\ \ *target_host*\ ] [\ **action=**\ \ *action*\ ] [\ **force=**\ \ *force*\ ] [\ **immediate=**\ \ *yes_no*\ ] [\ **max_total=**\ \ *total*\ ] [\ **max_quiesce=**\ \ *quiesce*\ ]



*******************
\ **Description**\ 
*******************


\ **rmigrate**\  requests that a guest VM be moved from the current entity hosting it to another.  It requests a live migration be done, if possible.

For zVM:
========


\ **rmigrate**\  migrates a VM from one z/VM member to another in an SSI cluster (only in z/VM 6.2).



*******
OPTIONS
*******


zVM specific:
=============



\ **destination=**\  The name of the destination z/VM system to which the specified virtual machine will be relocated.



\ **action=**\  It can be: (MOVE) initiate a VMRELOCATE MOVE of the VM, (TEST) determine if VM is eligible to be relocated, or (CANCEL) stop the relocation of VM.



\ **force=**\  It can be: (ARCHITECTURE) attempt relocation even though hardware architecture facilities or CP features are not available on destination system, (DOMAIN) attempt relocation even though VM would be moved outside of its domain, or (STORAGE) relocation should proceed even if CP determines that there are insufficient storage resources on destination system.



\ **immediate=**\  It can be: (YES) VMRELOCATE command will do one early pass through virtual machine storage and then go directly to the quiesce stage, or (NO) specifies immediate processing.



\ **max_total=**\  The maximum wait time for relocation to complete.



\ **max_quiesce=**\  The maximum quiesce time a VM may be stopped during a relocation attempt.





*************
\ **Files**\ 
*************


\ **vm**\  table -
Table governing VM paramaters.  See vm(5)|vm.5 for further details.
This is used to determine the current host to migrate from.


****************
\ **Examples**\ 
****************


\ **rmigrate**\  \ *v1*\  \ *n2*\ 

zVM specific:
=============



\ **rmigrate**\  \ *ihost123*\  destination=\ *pokdev62*\ 


