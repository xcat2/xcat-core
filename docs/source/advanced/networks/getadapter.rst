Predict network adapter name before deployment
==============================================



Traditionally, network interfaces in Linux are enumerated as eth[0123…], but these names do not necessarily correspond to actual labels on the chassis. customer need a methods to get consistent and predictable network device name before provision or network configuration. xCAT provide a tool ``getadapter`` to help customer to resolve this problem.


**[Note]** : This feature needs to restart your target sever which you want to obtain network adapter from.

How to use get adapters
-----------------------


Using below command to obtain the network adapters information ::
 
    getadapter <noderange>

Then will get output like below ::


    The whole scan result:
    --------------------------------------
    [node2] scan successfully, below are the latest data
    node2:[1]->eno1!mac=34:40:b5:be:6a:80|pci=/pci0000:00/0000:00:01.0/0000:0c:00.0|candidatename=eno1/enp12s0f0/enx3440b5be6a80
    node2:[2]->enp0s29u1u1u5!mac=36:40:b5:bf:44:33|pci=/pci0000:00/0000:00:1d.0/usb2/2-1/2-1.1/2-1.1.5/2-1.1.5:1.0|candidatename=enp0s29u1u1u5/enx3640b5bf4433
    --------------------------------------
    [node1] scan successfully, below are the latest data
    node1:[1]->eno1!mac=34:40:b5:be:6a:80|pci=/pci0000:00/0000:00:01.0/0000:0c:00.0|candidatename=eno1/enp12s0f0/enx3440b5be6a80
    node1:[2]->enp0s29u1u1u5!mac=36:40:b5:bf:44:33|pci=/pci0000:00/0000:00:1d.0/usb2/2-1/2-1.1/2-1.1.5/2-1.1.5:1.0|candidatename=enp0s29u1u1u5/enx3640b5bf4433


Every node gets a separate section to display its all network adapters information, every network adapter owns single line which start as node name and followed by index and other information.

xCAT try its best to collect more information for each network adapter, but can’t guarantee collect same much information for every one. If a network adapter can be derived by xcat genesis, this adapter will have a predictable name, if it can’t be, it only has the information xcat can obtain.
    
below are the possible information:

* **name**: the consistent name which can be used by confignic directly in operating system which follow the same naming scheme with rhels7

* **pci**: the pci location

* **mac**: the MAC address

* **candidatename**: All the names which satisfy predictable network device naming scheme, if customer needs to customize their network adapter name, they can choose one of them. (``confignic`` needs to do more work to support this. if customer want to use their own name, xcat should offer a interface to get customer’s input and change this column) 

* **vendor**:  the vender of network device

* **modle**:  the modle of network device
    
* **linkstate**:  The link state of network device
