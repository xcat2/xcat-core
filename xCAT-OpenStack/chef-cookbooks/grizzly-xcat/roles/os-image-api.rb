name "os-image-api"
description "Glance API service"
run_list(
  "role[os-base]",
  "recipe[openstack-image::api]"
  )

