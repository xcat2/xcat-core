name             "openstack-dashboard"
maintainer       "AT&T Services, Inc."
maintainer_email "cookbooks@lists.tfoundry.com"
license          "Apache 2.0"
description      "Installs/Configures the OpenStack Dasboard (Horizon)"
long_description IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version          "7.0.0"

recipe           "openstack-dashboard::server", "Sets up the Horizon dashboard within an Apache `mod_wsgi` container."

%w{ ubuntu fedora redhat centos suse }.each do |os|
  supports os
end

depends          "apache2"
depends          "openstack-common", "~> 0.4.0"
