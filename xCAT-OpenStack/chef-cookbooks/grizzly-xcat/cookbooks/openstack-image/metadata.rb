name              "openstack-image"
maintainer        "Opscode, Inc."
license           "Apache 2.0"
description       "Installs and configures the Glance Image Registry and Delivery Service"
long_description  IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version           "7.0.0"
recipe            "openstack-image::api", "Installs packages required for a glance api server"
recipe            "openstack-image::registry", "Installs packages required for a glance registry server"
recipe            "openstack-image::identity_registration", "Registers Glance endpoints and service with Keystone"

%w{ ubuntu fedora redhat centos suse }.each do |os|
  supports os
end

depends           "openstack-common", "~> 0.4.0"
depends           "openstack-identity", "~> 7.0.0"
