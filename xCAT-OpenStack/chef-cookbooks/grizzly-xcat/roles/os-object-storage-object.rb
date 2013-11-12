name "os-object-storage-object"
description "OpenStack object storage object service"
run_list(
  "role[os-base]",
  "recipe[openstack-object-storage::object]"
  )
