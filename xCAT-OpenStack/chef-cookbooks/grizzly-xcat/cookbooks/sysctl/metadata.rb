name             "sysctl"
maintainer       "OneHealth Solutions, Inc."
maintainer_email "cookbooks@onehealth.com"
license          "Apache v2.0"
description      "Configures sysctl parameters"
long_description IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version          "0.3.2"
%w(ubuntu debian redhat centos).each do |os|
  supports os
end
