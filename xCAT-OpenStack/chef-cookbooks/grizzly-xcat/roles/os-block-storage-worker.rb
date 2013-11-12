name "os-block-storage-worker"
description "OpenStack Block Storage worker"
run_list(
  "role[os-base]",
  "recipe[openstack-block-storage::worker]"
  )
