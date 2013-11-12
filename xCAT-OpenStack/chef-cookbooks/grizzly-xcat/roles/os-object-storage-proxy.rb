name "os-object-storage-proxy"
description "OpenStack object storage proxy service"
run_list(
  "role[os-base]",
  "recipe[openstack-object-storage::proxy]"
  )
