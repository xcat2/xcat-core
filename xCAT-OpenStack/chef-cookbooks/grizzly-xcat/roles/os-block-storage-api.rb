name "os-block-storage-api"
description "OpenStack Block Storage API service"
run_list(
  "role[os-base]",
  "recipe[openstack-block-storage::api]"
  )
