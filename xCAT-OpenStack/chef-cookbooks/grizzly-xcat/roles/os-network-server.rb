name "os-network-server"
description "os-network-server"
run_list(
  "role[os-base]",
  "recipe[openstack-network::server]"
)

