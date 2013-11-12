name "os-infra-caching"
description "Memcached role for Openstack"
run_list(
  "role[os-base]",
  "recipe[memcached::default]"
  )
