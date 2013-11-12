name "os-compute-setup"
description "Nova base setup"
run_list(
  "role[os-base]",
  "recipe[openstack-compute::nova-setup]"
  )

