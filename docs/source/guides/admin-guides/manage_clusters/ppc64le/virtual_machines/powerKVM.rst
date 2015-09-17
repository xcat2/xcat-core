PowerKVM
========

Install PowerKVM 
----------------

The process to set up PowerKVM hypervisor with xCAT is the same with Diskfull installation. Prepare powerKVM iso, such as ibm-powerkvm-2.1.1.0-22.0-ppc64-gold-201410191558.iso, then refer to :ref:`diskful_installation` to install PowerKVM hypervisor.

Verifying hypervisor bridges
----------------------------

After PowerKVM hypervisor is installed successfully, you can get the bridge information by running ``brctl show``: ::

  # brctl show
  bridge name     bridge id               STP enabled     interfaces
  br0             8000.000000000000       no              eth0

If there are no bridges configured, the xCAT post install script will not work. You must manually create a bridge. The following is provided as an example for creating a bridge bro using interface eth0 with IP address: 10.1.101.1/16, for example: ::

  IPADDR=10.1.101.1/16
  brctl addbr br0
  brctl addif br0 eth0
  brctl setfd br0 0
  ip addr add dev br0 $IPADDR
  ip link set br0 up
  ip addr del dev eth0 $IPADDR

Note: During any of ubuntu installation, the virtual machines need to access Internet, so make sure the PowerKVM hypervisor is able to access Internet.
