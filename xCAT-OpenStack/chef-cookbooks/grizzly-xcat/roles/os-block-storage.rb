name "os-block-storage"
description "Configures OpenStack block storage, configured by attributes."
run_list(
  "role[os-base]",
  "recipe[openstack-block-storage]"
  )
