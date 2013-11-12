name "os-l2-networker"
description "for use case: Single Flat Network. In this use case, there are 3 different nodes including controller node(role[os-single-controller]), network node(role[os-L2-networker]) and compute node(role[os-computer]). This role is for the network  node. It includes the openvswitch, dhcp-agent. "
run_list(
  "role[os-base]",
  "role[os-network-openvswitch]",
  "role[os-network-dhcp-agent]"
  )
