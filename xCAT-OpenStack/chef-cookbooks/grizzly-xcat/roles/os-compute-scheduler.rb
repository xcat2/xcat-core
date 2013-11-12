name "os-compute-scheduler"
description "Nova scheduler"
run_list(
  "role[os-base]",
  "recipe[openstack-compute::scheduler]"
  )
