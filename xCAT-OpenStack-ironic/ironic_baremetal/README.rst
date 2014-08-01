xCAT Driver for ironic x86/64 machine
==================================

xCAT is a Extreme Cluster/Cloud Administration Toolkit. We can use xcat
to do :
1 hardward discoveery
2 remote hardware control
3 remote sonsole
4 hardware inventory
5 firmware flashing

Ironic is a project in Openstack, it will replace the nova-baremetal in juno release. Ironic's design is very flexable, we can add driver to extend function
without change any code in Openstack. Ironic xCAT driver takes the advantage of xcat and openstack, we can use it to deploy the baremetal machine very easily.

Before using this driver, we must setup the openstack environment at least for two nodes( ironic conductor and neutron network node can't setup on the same node)
Ironic conductor and the baremetal node( waiting for deploy) must in the same vlan 

Add the follows in the ironic egg-info entry_points.txt file (ironic.drivers section) 

pxe_xcat = ironic.drivers.xcat:XCATBaremetalDriver
 
When the openstack with ironic is ready, just execute command in the ironic_xcat directory as follows:

$ python setup.py install

Restart the ironic-conductor process

Initialize the xcat environment according  to http://sourceforge.net/p/xcat/wiki/XCAT_iDataPlex_Cluster_Quick_Start/
Using xCAT baremetal driver need config site table and run copycds to generate image. The node definition is not requirement.

Ironic use neutron as the network service.
Check the openvswitch config on the network node ,make sure brbm bridge connect to the baremetal node. 

==================================================================================
Some Example to use the xCAT baremetal driver. 

$touch /tmp/rhelhpc6.5-x86_64-install-compute.qcow2;glance image-create --name rhelhpc6.5-x86_64-install-compute --public --disk-format qcow2 --container-format bare --property xcat_image_name='rhels6.4-x86_64-install-compute' < /tmp/rhelhpc6.5-x86_64-install-compute.qcow2
--name rhelhpc6.5-x86_64-install-compute is the image name in xcat. You can use lsdef -t osimage on the ironic-conductor node which xcat is installed.

$ ironic node-create --driver pxe_xcat -i ipmi_address=xxx.xxx.xxx.xxx   -i ipmi_username=userid -i ipmi_password=password  -i xcat_node=x3550m4n02  -i xcatmaster=10.1.0.241 -i netboot=xnba -i ipmi_terminal_port=0 -p memory_mb=2048 -p cpus=8

$ ironic port-create --address ff:ff:ff:ff:ff:ff --node_uuid <ironic node uuid>

$ nova boot --flavor baremetal --image <image-id>  testing --nic net-id=<internal network id>
