name "os-block-storage-volume"
description "OpenStack Block Storage volume service"
run_list(
  "role[os-base]",
  "recipe[openstack-block-storage::volume]"
  )
