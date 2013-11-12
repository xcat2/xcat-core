name "os-block-storage-endpoint-registration"
description "Register Endpoint"
run_list(
  "role[os-base]",
  "recipe[openstack-block-storage::identity_registration]"
  )
