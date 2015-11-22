Predict network adapter name before deployment
==============================================



Traditionally, network interfaces in Linux are enumerated as eth[0123…], but these names do not necessarily correspond to actual labels on the chassis. customer need a methods to get consistent and predictable network device name before provision or network configuration. xCAT provide a tool ``getadapters`` to help customer to resolve this problem.


**[Note]** : This feature needs to restart your target sever which you want to obtain network adapter from.

How to use get adapters
-----------------------


Using below command to obtain the network adapters information ::
 
    getadapters <noderange>

Then will get output like below ::


    The whole scan result:
    --------------------------------------
    node1:1:hitn=enP3p3s0f0|pci=/pci0003:00/0003:00:00.0/0003:01:00.0/0003:02:01.0/0003:03:00.0|mac=98be9459ea24|prdn=enP3p3s0f0,enx98be9459ea24|vnd=Broadcom Corporationmod=NetXtreme II BCM57800 1/10 Gigabit Ethernet
    node1:2:hitn=enP3p3s0f1|pci=/pci0003:00/0003:00:00.0/0003:01:00.0/0003:02:01.0/0003:03:00.1|mac=98be9459ea25|prdn=enP3p3s0f1,enx98be9459ea25|vnd=Broadcom Corporationmod=NetXtreme II BCM57800 1/10 Gigabit Ethernet
    node1:3:hitn=enP3p3s0f2|pci=/pci0003:00/0003:00:00.0/0003:01:00.0/0003:02:01.0/0003:03:00.2|mac=98be9459ea26|prdn=enP3p3s0f2,enx98be9459ea26|vnd=Broadcom Corporationmod=NetXtreme II BCM57800 1/10 Gigabit Ethernet
    node1:4:hitn=enP3p3s0f3|pci=/pci0003:00/0003:00:00.0/0003:01:00.0/0003:02:01.0/0003:03:00.3|mac=98be9459ea27|prdn=enP3p3s0f3,enx98be9459ea27|vnd=Broadcom Corporationmod=NetXtreme II BCM57800 1/10 Gigabit Ethernet
    node1:5:pci=0001:01:00.0|mod=Mellanox Technologies MT27600 [Connect-IB]
    --------------------------------------
    node2:1:hitn=enP3p3s0f0|pci=/pci0003:00/0003:00:00.0/0003:01:00.0/0003:02:01.0/0003:03:00.0|mac=98be9459ea24|prdn=enP3p3s0f0,enx98be9459ea24|vnd=Broadcom Corporationmod=NetXtreme II BCM57800 1/10 Gigabit Ethernet
    node2:2:hitn=enP3p3s0f1|pci=/pci0003:00/0003:00:00.0/0003:01:00.0/0003:02:01.0/0003:03:00.1|mac=98be9459ea25|prdn=enP3p3s0f1,enx98be9459ea25|vnd=Broadcom Corporationmod=NetXtreme II BCM57800 1/10 Gigabit Ethernet


Every node gets a separate section to display its all network adapters information, every network adapter owns single line which start as node name and followed by index and other information.

xCAT try its best to collect more information for each network adapter, but can’t guarantee collect same much information for every one. If a network adapter can be derived by xcat genesis, this adapter will have a predictable name, if it can’t be, it only has the information xcat can obtain.
    
below are the possible information:

* **hitn**: the consistent name which can be used in ``confignic`` derectly in operating system which follow the same naming scheme with rhels7. (``confignic`` doesn’t need to do more work)

* **pci**: the pci location

* **mac**: the MAC address

* **prdn**: All the names which satisfy predictable network device naming scheme, if customer needs to customize their network adapter name, they can choose one of them. (``confignic`` needs to do more work to support this. if customer want to use their own name, xcat should offer a interface to get customer’s input and change this column) 

* **vnd**:  the vender of network device

* **mod**:  the modle of network device
    
    
    
