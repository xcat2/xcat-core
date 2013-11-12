name "os-image-endpoint-registration"
description "Register Endpoint"
run_list(
  "role[os-base]",
  "recipe[openstack-image::identity_registration]"
  )
