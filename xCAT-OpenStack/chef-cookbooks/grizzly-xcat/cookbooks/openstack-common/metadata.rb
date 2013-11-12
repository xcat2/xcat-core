name             "openstack-common"
maintainer       "AT&T Services, Inc."
maintainer_email "cookbooks@lists.tfoundry.com"
license          "Apache 2.0"
description      "Common OpenStack attributes, libraries and recipes."
long_description IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version          "0.4.3"

recipe           "openstack-common", "Installs/Configures common recipes"
recipe           "openstack-common::logging", "Installs/Configures common logging"

%w{ ubuntu suse }.each do |os|
  supports os
end

depends          "apt"
depends          "database"
