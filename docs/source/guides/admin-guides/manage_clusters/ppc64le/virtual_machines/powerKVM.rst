PowerKVM
========

Install PowerKVM 
----------------

The process to set up PowerKVM hypervisor with xCAT is the same with Diskfull installation. Prepare powerKVM iso, such as ibm-powerkvm-2.1.1.0-22.0-ppc64-gold-201410191558.iso, then refer to :ref:`diskful_installation` to install PowerKVM hypervisor.

Check bridge setting after installation finished
------------------------------------------------

After PowerKVM hypervisor is installed successfully, you can get the bridge information: ::

  # brctl show
  bridge name     bridge id               STP enabled     interfaces
  br0             8000.000000000000       no              eth0

If the bridge show is not like above, it means that you may not run xCAT post install script. You can manually run following commands to create the bridge, for example: ::

  IPADDR=10.1.101.1/16
  brctl addbr br0
  brctl addif br0 eth0
  brctl setfd br0 0
  ip addr add dev br0 $IPADDR
  ip link set br0 up
  ip addr del dev eth0 $IPADDR

Note: During ubuntu LE virtual machines installation, the virtual machines need to access Internet, so make sure the PowerKVM hypervisor is able to access Internet.
