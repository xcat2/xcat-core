name "os-network-openvswitch"
description "os-network-openvswitch"
run_list(
  "role[os-base]",
  "recipe[openstack-network::openvswitch]"
)

