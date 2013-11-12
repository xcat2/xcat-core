name              "openstack-ops-messaging"
maintainer        "Opscode, Inc."
maintainer_email  "matt@opscode.com"
license           "Apache 2.0"
description       "Provides the shared messaging configuration for Chef for OpenStack."
version           "7.0.0"

recipe "server", "Installs and configures server packages for messaging queue used by the deployment."
recipe "rabbitmq-server", "Installs and configures RabbitMQ and is called via the server recipe"

%w{ fedora ubuntu redhat centos }.each do |os|
  supports os
end

depends "openstack-common", "~> 0.4.0"
depends "rabbitmq", ">= 2.1.0"
