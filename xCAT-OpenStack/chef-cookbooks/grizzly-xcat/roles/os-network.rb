name "os-network"
description "Configures OpenStack networking, managed by attribute for either nova-network or quantum"
run_list(
  "role[os-base]",
  "role[os-network-server]",
  "role[os-network-openvswitch]",
  "role[os-network-dhcp-agent]",
  "role[os-network-l3-agent]"
  )
