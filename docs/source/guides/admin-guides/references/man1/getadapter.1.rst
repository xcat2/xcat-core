
############
getadapter.1
############

.. highlight:: perl


****
NAME
****


\ **getadapter**\  - Obtain all network adapters's predictable name and some other information before provision or network configuration.


********
SYNOPSIS
********


\ **getadapter**\  \ *noderange*\  [\ **-f**\ ]

\ **getadapter**\  [\ **-h | -**\ **-help | -v | -**\ **-version | -V**\ ]


***********
DESCRIPTION
***********


Traditionally, network interfaces in Linux are enumerated as eth[0123...], but these names do not necessarily correspond to actual labels on the chassis. \ **getadapter**\  help customer to get predictable network device name and some other network adapter information before provision or network configuration.

\ **getadapter**\  use genesis to collect network adapters information, so that mean it need to restart the target node.

\ **getadapter**\  follows below scheme:

If the target node is scaned for the first time, \ **getadapter**\  will trigger genesis to collect information then save the information at local.
If the target node has ever been scaned, i.e. this node has network device information in local, \ **getadapter**\  use the local information first.
If user doesn't want to use local information, can use \ **-f**\  option to force to trigger new round scan process.
if part nodes of \ *noderange*\  don't have network device information in local and the rest have, \ **getadapter**\  only trigger real scan process for these nodes which don't have local information, the nodes have network device information in local, \ **getadapter**\  still use the local information first.

\ **getadapter**\  tries to collect more information for the  target network device,  but doesn't guarantee collect same much information for every network device.

Below are the possible information can be collect up to now:
\ **name**\ : the consistent name which can be used by confignic directly in operating system which follow the same naming scheme with rhels7
\ **pci**\ : the pci location
\ **mac**\ : the MAC address
\ **candidatename**\ : All the names which satisfy predictable network device naming scheme. \ *(if xcat enhance confignic command later, user can use these names to configure their network adapter, even customize their name)*\ 
\ **vender**\ :  the vender of network device
\ **model**\ :  the model of network device
\ **linkstate**\ :  the link state of network device


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

  getadapter  node[1-2]


Output is similar to:


.. code-block:: perl

  -->Starting scan for: node1,node2
  The whole scan result:
  --------------------------------------
  [node1]: Adapter information exists, no need to scan.
  --------------------------------------
  [node2] scan successfully, below are the latest data
  node2:[1]->eno1!mac=34:40:b5:be:6a:80|pci=/pci0000:00/0000:00:01.0/0000:0c:00.0|candidatename=eno1/enp12s0f0/enx3440b5be6a80
  node2:[2]->enp0s29u1u1u5!mac=36:40:b5:bf:44:33|pci=/pci0000:00/0000:00:1d.0/usb2/2-1/2-1.1/2-1.1.5/2-1.1.5:1.0|candidatename=enp0s29u1u1u5/enx3640b5bf4433


Every node gets a separate section to display its all network adapters information, every network adapter owns single line which start as node name and followed by index and other information.

2. Force to trigger new round scan


.. code-block:: perl

   getadatper node -f



********
SEE ALSO
********


noderange(3)|noderange.3

