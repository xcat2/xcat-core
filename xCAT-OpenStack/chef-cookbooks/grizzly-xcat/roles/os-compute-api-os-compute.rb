name "os-compute-api-os-compute"
description "OpenStack API for Compute"
run_list(
  "role[os-base]",
  "recipe[openstack-compute::api-os-compute]"
  )
