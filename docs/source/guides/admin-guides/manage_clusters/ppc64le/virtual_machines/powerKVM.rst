PowerKVM
========

Install PowerKVM 
----------------

The process to set up PowerKVM hypervisors using xCAT is very similar to deploying diskful compute nodes.

#. Download the PowerKVM iso and add it to xCAT using copycds: :: 

    # if the iso file is: ibm-powerkvm-2.1.1.0-22.0-ppc64-gold-201410191558.iso
    copycds -n pkvm2.1.1 ibm-powerkvm-2.1.1.0-22.0-ppc64-gold-201410191558.iso

#. Then provision the target node using the PowerKVM osimage: ::

       nodeset <noderange> osimage=pkvm2.1.1-ppc64-install-compute
       rsetboot <noderange> net
       rpower <noderange> reset

   Refer to :doc:`/guides/admin-guides/manage_clusters/ppc64le/diskful/index` if you need more information.


Verifying hypervisor bridges
----------------------------

In order to launch VMs, bridges must be configured on the PowerKVM hypervisors for the Virtual Machines to utilize.

Check that at least one bridge is configured and mapped to a physical interface.   Show the bridge information using ``brctl show``: ::

   # brctl show
   bridge name     bridge id               STP enabled     interfaces
   br0             8000.000000000000       no              eth0

If there are no bridges configured, the xCAT post install script will not work. You must manually create a bridge. The following is provided as an example for creating a bridge br0 using interface eth0 with IP address: 10.1.101.1/16, for example: ::

  IPADDR=10.1.101.1/16
  brctl addbr br0
  brctl addif br0 eth0
  brctl setfd br0 0
  ip addr add dev br0 $IPADDR
  ip link set br0 up
  ip addr del dev eth0 $IPADDR

Note: During any of ubuntu installation, the virtual machines need to access Internet, so make sure the PowerKVM hypervisor is able to access Internet.
