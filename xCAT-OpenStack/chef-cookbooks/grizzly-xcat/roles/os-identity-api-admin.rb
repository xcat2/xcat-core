name "os-identity-api-admin"
description "Keystone admin API service"
run_list(
  "role[os-base]",
  "recipe[openstack-identity::server]"
  )

