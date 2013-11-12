name "os-computer"
description "for use case: Single Flat Network, Provider Router with Private Networks, and Per-tenant Routers with Private Networks. There are 3 different nodes including controller node, network node and compute node. This role is for the compute node. It includes L2 agent, nova compute."
run_list(
  "role[os-base]",
  "role[os-compute-worker]",
  "role[os-network-openvswitch]"
  )

