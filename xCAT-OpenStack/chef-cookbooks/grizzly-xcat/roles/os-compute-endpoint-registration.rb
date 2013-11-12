name "os-compute-endpoint-registration"
description "Register Endpoint"
run_list(
  "role[os-base]",
  "recipe[openstack-compute::identity_registration]"
  )
