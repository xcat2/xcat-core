name "os-block-storage-scheduler"
description "OpenStack Block Storage Scheduler service"
run_list(
  "role[os-base]",
  "recipe[openstack-block-storage::scheduler]"
  )
