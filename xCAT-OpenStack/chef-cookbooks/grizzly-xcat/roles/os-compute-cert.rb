name "os-compute-cert"
description "OpenStack Compute Cert service"
run_list(
  "role[os-base]",
  "recipe[openstack-compute::nova-cert]"
  )
