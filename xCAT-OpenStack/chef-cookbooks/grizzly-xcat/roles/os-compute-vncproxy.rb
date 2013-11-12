name "os-compute-vncproxy"
description "Nova VNC Proxy"
run_list(
  "role[os-base]",
  "recipe[openstack-compute::vncproxy]"
  )

