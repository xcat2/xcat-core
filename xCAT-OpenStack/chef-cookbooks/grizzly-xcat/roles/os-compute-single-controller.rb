name "os-compute-single-controller"
description "Roll-up role for all of the OpenStack Compute services on a single, non-HA controller."
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
