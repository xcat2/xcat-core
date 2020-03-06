Use Extra Parameters In NIC Configuration File
----------------------------------------------

Use ``nicextraparams`` to customize attributes in NIC configuration file. For example :

  #. Compute node ``cn1`` with one physical NIC: ``eth1``
  #. Configure network into ``networks`` table, configure ``nicips``, ``nictypes`` and ``nicnetworks`` in ``nics`` table, like :doc:`Configure Ethernet Network Interface<cfg_network_ethernet_nic>`
  #. In order to customize "MTU=1456 ONBOOT=no" for eth1. configure ``nicips``, ``nictypes`` and ``nicnetworks`` in ``nics`` table , also need to configure ``nicextraparams`` as following::

      chdef cn1 nicextraparams.eth1="MTU=1456 ONBOOT=no"

  #. After ``confignetwork`` is executed in ``cn1``, ``nicextraparams`` will overwrite the original value in ``/etc/sysconfig/network-scripts/ifcfg-eth1`` as ::

      DEVICE=eth1
      IPADDR=13.1.89.7
      NETMASK=255.255.255.0
      BOOTPROTO=static
      ONBOOT=no
      HWADDR=42:f5:0a:05:6a:09
      MTU=1456

  #. Example to add `nicextraparams` to `bond` interface ::

      chdef cn1 nicextraparams.bond0='BONDING_OPTS="mode=active-backup;abc=100" MTU=6400 XYZ="4800" IOP="mode=1 phase=2"'

