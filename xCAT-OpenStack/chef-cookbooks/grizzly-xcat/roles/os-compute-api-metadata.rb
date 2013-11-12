name "os-compute-api-metadata"
description "OpenStack compute metadata API service"
run_list(
  "role[os-base]",
  "recipe[openstack-compute::api-metadata]"
  )
