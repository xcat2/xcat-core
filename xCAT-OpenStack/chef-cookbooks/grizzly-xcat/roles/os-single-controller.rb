name "os-single-controller"
description "for use case: Single Flat Network, Provider Router with Private Networks, and Per-tenant Routers with Private Networks. There are 3 different nodes including controller node, network node and compute node. This role is for the non-HA controller. It includes quantum server, nova servers, keystone and so on."
run_list(
  "role[os-base]",
  "role[os-ops-database]",
  "role[os-ops-messaging]",
  "role[os-identity]",
  "role[os-network-server]",
  "role[os-compute-scheduler]",
  "role[os-compute-api]",
  "role[os-compute-cert]",
  "role[os-compute-vncproxy]",
  "role[os-compute-setup]",
  "recipe[openstack-compute::conductor]",
  "role[os-block-storage]",
  "role[os-dashboard]",
  "role[os-image]",
  "role[os-block-storage-endpoint-registration]",
  "role[os-compute-endpoint-registration]",
  "role[os-image-endpoint-registration]",
  "role[os-network-endpoint-registration]"
  )
