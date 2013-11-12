name             "openstack-identity"
maintainer       "Opscode, Inc."
maintainer_email "matt@opscode.com"
license          "Apache 2.0"
description      "The OpenStack Identity service Keystone."
long_description IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version          "7.0.0"

recipe           "openstack-identity::server", "Installs and Configures Keystone Service"
recipe           "openstack-identity::registration", "Adds user, tenant, role and endpoint records to Keystone"

%w{ ubuntu fedora redhat centos suse }.each do |os|
  supports os
end

depends          "openstack-common", "~> 0.4.0"
