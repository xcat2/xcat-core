
#############
getadapters.1
#############

.. highlight:: perl


****
NAME
****


\ **getadapters**\  - Obtain all network adapters's predictable name and some other information before provision or network configuration.


********
SYNOPSIS
********


\ **getadapters**\  \ *noderange*\  [\ **-f**\ ]

\ **getadapters**\  [\ **-h**\ |\ **--help**\ |\ **-v**\ |\ **--version**\ |\ **-V**\ ]


***********
DESCRIPTION
***********


Traditionally, network interfaces in Linux are enumerated as eth[0123…], but these names do not necessarily correspond to actual labels on the chassis. \ **getadapters**\  help customer to get predictable network device name and some other network adapter information before provision or network configuration.

\ **getadapters**\  use genesis to collect network adapters information, so that mean it need to restart the target node.

\ **getadapters**\  follows below scheme:

If the target node is scaned for the first time, \ **getadapters**\  will trigger genesis to collect information then save the information at local. 
If the target node has ever been scaned, i.e. this node has network device information in local, \ **getadapters**\  use the local information first.
If user doesn't want to use local information, can use \ **-f**\  option to force to trigger new round scan process.
if part nodes of \ *noderange*\  don't have network device information in local and the rest have, \ **getadapters**\  only trigger real scan process for these nodes which don't have local information, the nodes have network device information in local, \ **getadapters**\  still use the local information first.

\ **getadapters**\  tries to collect more information for the  target network device,  but doesn't guarantee collect same much information for every network device.

Below are the possible information can be collect up to now:
\ **hitname**\ : the consistent name which can be used by confignic directly in operating system which follow the same naming scheme with rhels7
\ **pci**\ : the pci location
\ **mac**\ : the MAC address
\ **candidatename**\ : All the names which satisfy predictable network device naming scheme. \ *(if xcat enhance confignic command later, user can use these names to configure their network adapter, even customize their name)*\ 
\ **vender**\ :  the vender of network device
\ **model**\ :  the model of network device


*******
OPTIONS
*******


\ **-h**\ 

Display usage message.

\ **-v**\ 

Command Version.

\ **-V**\ 

Display verbose message.

\ **-f**\ 

Force to trigger new round scan. ignore the data collected before.


********
EXAMPLES
********


1. To collect node[1-3]'s network device information, enter:


.. code-block:: perl

  getadapters  node[1-2]


Output is similar to:

-->Starting scan for: node1,node2
The whole scan result:
--------------------------------------
[node1] with no need for scan due to old data exist, using the old data:
node1:1:mac=98be9459ea24|pci=/0003:03:00.0|candidatename=enx98be9459ea24|vender=Broadcom Corporation 
node1:2:mac=98be9459ea25|pci=/0003:03:00.1|candidatename=enx98be9459ea25|vender=Broadcom Corporation
--------------------------------------
[node2] scan successfully, below are the latest data
node2:1:mac=98be9459ea34|pci=/0003:03:00.0|candidatename=enx98be9459ea34|vender=Broadcom Corporation 
node2:2:mac=98be9459ea35|pci=/0003:03:00.1|candidatename=enx98be9459ea35|vender=Broadcom Corporation

Every node gets a separate section to display its all network adapters information, every network adapter owns single line which start as node name and followed by index and other information.

2. Force to trigger new round scan


.. code-block:: perl

   getadatpers node -f



********
SEE ALSO
********


noderange(3)|noderange.3

