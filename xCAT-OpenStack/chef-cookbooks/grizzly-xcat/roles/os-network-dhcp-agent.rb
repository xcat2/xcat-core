name "os-network-dhcp-agent"
description "os-network-dhcp-agent"
run_list(
  "role[os-base]",
  "recipe[openstack-network::dhcp_agent]"
)

