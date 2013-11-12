name "allinone-compute"
description "This will deploy all of the services for Openstack Compute to function on a single box."
run_list(
  "role[os-compute-single-controller]",
  "role[os-compute-worker]"
)
