name "os-object-storage-proxy"
description "OpenStack object storage server responsible for generating initial settings"
run_list(
  "role[os-base]",
  "recipe[openstack-object-storage::setup]"
  )
