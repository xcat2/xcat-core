name "os-ops-messaging"
description "Currently RabbitMQ Server (non-ha)"
run_list(
  "role[os-base]",
  "recipe[openstack-ops-messaging::server]"
  )
