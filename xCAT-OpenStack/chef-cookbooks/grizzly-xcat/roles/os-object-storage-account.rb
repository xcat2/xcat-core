name "os-object-storage-account"
description "OpenStack object storage account service"
run_list(
  "role[os-base]",
  "recipe[openstack-object-storage::account]"
  )
