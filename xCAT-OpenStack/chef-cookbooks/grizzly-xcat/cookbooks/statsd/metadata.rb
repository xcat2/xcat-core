name             "statsd"
maintainer       "AT&T Services, Inc."
maintainer_email "cookbooks@lists.tfoundry.com"
license          "Apache 2.0"
description      "Installs/Configures statsd"
long_description IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version          "0.1.4"
recipe           "statsd", "Installs stats ruby gem"
recipe           "statsd::server", "Configures statsd server"

%w{ ubuntu }.each do |os|
  supports os
end

depends          "build-essential"
depends          "git"
