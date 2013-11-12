name "os-network-endpoint-registration"
description "Register Endpoint"
run_list(
  "role[os-base]",
  "recipe[openstack-network::identity_registration]"
  )
