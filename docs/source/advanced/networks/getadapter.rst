Predict network adapter name during discovery
==============================================

Traditionally, network interfaces in Linux are enumerated as eth[0123…], but
these names do not correspond to actual labels on the chassis. Now, most of
the linux distribution support naming the adapter with slot information which
makes adapter name predictable. xCAT add ``getadapter`` script which can be
run during discovery stage to detect the adapter names and pci slot
information to help customer configure the network.


How to use getadapter
-----------------------

Set the chain table to run ``getadapter`` script ::

  chdef <noderange> chain="runcmd=getadapter"

After the discovery completed, the column ``nicsadapter`` of ``nics`` table is
updated.

View result with ``lsdef`` command ::

  # lsdef <node>
  .......
  nicsadapter.enP3p3s0f0=mac=98:be:94:59:fa:cc linkstate=DOWN pci=/pci0003:00/0003:00:00.0/0003:01:00.0/0003:02:01.0/0003:03:00.0 candidatename=enP3p3s0f0/enx98be9459facc
  nicsadapter.enP3p3s0f1=mac=98:be:94:59:fa:cd linkstate=DOWN pci=/pci0003:00/0003:00:00.0/0003:01:00.0/0003:02:01.0/0003:03:00.1 candidatename=enP3p3s0f1/enx98be9459facd
  nicsadapter.enP3p3s0f2=mac=98:be:94:59:fa:ce linkstate=DOWN pci=/pci0003:00/0003:00:00.0/0003:01:00.0/0003:02:01.0/0003:03:00.2 candidatename=enP3p3s0f2/enx98be9459face
  nicsadapter.enP3p3s0f3=mac=98:be:94:59:fa:cf linkstate=UP pci=/pci0003:00/0003:00:00.0/0003:01:00.0/0003:02:01.0/0003:03:00.3 candidatename=enP3p3s0f3/enx98be9459facf
  .......

Below are the information ``getadapter`` trying to inspect:

* **name**: the real adapter name used by genesis operation system

* **pci**: the pci slot location

* **mac**: the MAC address

* **candidatename**: All the names which satisfy predictable network device naming scheme, if customer needs to customize their network adapter name, they can choose one of them. (``confignetwork`` needs to do more work to support this. if customer want to use their own name, xcat should offer a interface to get customer’s input and change this column)

* **linkstate**:  The link state of network device
