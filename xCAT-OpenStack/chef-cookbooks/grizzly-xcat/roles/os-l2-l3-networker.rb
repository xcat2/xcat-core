name "os-l2-l3-networker"
description "for use case: Provider Router with Private Networks, and Per-tenant Routers with Private Networks. In the 2 use cases, there are 3 different nodes including controller node(role[os-single-controller]), network node(role[os-L2-L3-networker]) and compute node(role[os-computer]). This role is for the network node. It includes the openvswitch, dhcp-agent and L3-agent"
run_list(
  "role[os-base]",
  "role[os-network-openvswitch]",
  "role[os-network-dhcp-agent]",
  "role[os-network-l3-agent]"
  )
