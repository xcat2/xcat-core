name "os-object-storage"
description "OpenStack object storage roll-up role"
run_list(
  "role[os-base]",
  "recipe[openstack-object-storage]"
  )
