
##########
rnetboot.1
##########

.. highlight:: perl


****
NAME
****


\ **rnetboot**\  - Cause the range of nodes to boot to network.


********
SYNOPSIS
********


\ **rnetboot**\  [\ **-V | -**\ **-verbose**\ ] [\ **-s**\  \ *boot_device_order*\ ] [\ **-F**\ ] [\ **-f**\ ] \ *noderange*\  [\ **-m**\  \ *table.column*\ ==\ *expectedstatus*\  [\ **-m**\  \ *table.col-umn*\ =~\ *expectedstatus*\ ]] [\ **-t**\  \ *timeout*\ ] [\ **-r**\  \ *retrycount*\ ]

\ **rnetboot**\  [\ **-h | -**\ **-help**\ ] [\ **-v | -**\ **-version**\ ]

zVM specific:
=============


\ **rnetboot**\  \ *noderange*\  [\ **ipl=**\  \ *address*\ ]



***********
DESCRIPTION
***********


The rnetboot command will do what is necessary to make each type of node in the given noderange
boot from the network.  This is usually used to boot the nodes stateless or to network install
system p nodes.


*******
OPTIONS
*******


\ **-s**\ 

Set the boot device order.  Accepted boot devices are hd and net.

\ **-F**\ 

Force reboot the system no matter what state the node is.  By default, rnetboot will not reboot the node if node is in 'boot' state.

\ **-f**\ 

Force immediate shutdown of the partition.

\ **-m**\ 

Use one or multiple -m flags to specify the node attributes and the expected status for the node installation monitoring and automatic retry mechanism. The operators ==, !=, =~ and !~ are valid. This flag must be used with -t flag.

Note: if the "val" fields includes spaces or any other characters that will be parsed by shell, the "attr<oper-ator>val" needs to be quoted. If the operator is "!~", the "attr<operator>val" needs to be quoted using single quote.

\ **-r**\ 

specify the number of retries that the monitoring process will perform before declare the failure. The default value is 3. Setting the retrycount to 0 means only monitoring the os installation progress and will not re-initiate the installation if the node status has not been changed to the expected value after timeout. This flag must be used with -m flag.

\ **-t**\ 

Specify the the timeout, in minutes, to wait for the expectedstatus specified by -m flag. This is a required flag if the -m flag is specified.

\ **-V|-**\ **-verbose**\ 

Verbose output.

\ **-h|-**\ **-help**\ 

Display usage message.

\ **-v|-**\ **-version**\ 

Command Version.


************
RETURN VALUE
************


0 The command completed successfully.

1 An error has occurred.


********
EXAMPLES
********



.. code-block:: perl

  rnetboot 1,3
 
  rnetboot 14-56,70-203
 
  rnetboot 1,3,14-56,70-203
 
  rnetboot all,-129-256
 
  rnetboot all -s hd,net
 
  rnetboot all ipl=00c



********
SEE ALSO
********


nodeset(8)|nodeset.8

