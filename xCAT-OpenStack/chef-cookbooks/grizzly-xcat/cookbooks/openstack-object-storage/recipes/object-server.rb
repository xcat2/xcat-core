#
# Cookbook Name:: swift
# Recipe:: swift-object-server
#
# Copyright 2012, Rackspace US, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

include_recipe "openstack-object-storage::common"
include_recipe "openstack-object-storage::storage-common"
include_recipe "openstack-object-storage::disks"

platform_options = node["swift"]["platform"]

platform_options["object_packages"].each do |pkg|
  package pkg do
    action :install
    options platform_options["override_options"] # retain configs
  end
end

# epel/f-17 missing init scripts for the non-major services.
# https://bugzilla.redhat.com/show_bug.cgi?id=807170
%w{auditor updater replicator}.each do |svc|
  template "/etc/systemd/system/openstack-swift-object-#{svc}.service" do
    owner "root"
    group "root"
    mode "0644"
    source "simple-systemd-config.erb"
    variables({ :description => "OpenStack Object Storage (swift) - " +
                "Object #{svc.capitalize}",
                :user => "swift",
                :exec => "/usr/bin/swift-object-#{svc} " +
                "/etc/swift/object-server.conf"
              })
    only_if { platform?(%w{fedora})}
  end
end

# TODO(breu): track against upstream epel packages to determine if this
# is still necessary
# https://bugzilla.redhat.com/show_bug.cgi?id=807170
%w{auditor updater replicator}.each do |svc|
  template "/etc/init.d/openstack-swift-object-#{svc}" do
    owner "root"
    group "root"
    mode "0755"
    source "simple-redhat-init-config.erb"
    variables({ :description => "OpenStack Object Storage (swift) - " +
                "Object #{svc.capitalize}",
                :exec => "object-#{svc}"
              })
    only_if { platform?(%w{redhat centos}) }
  end
end

%w{swift-object swift-object-replicator swift-object-auditor swift-object-updater}.each do |svc|
  service_name=platform_options["service_prefix"] + svc + platform_options["service_suffix"]

  service svc do
    service_name service_name
    provider platform_options["service_provider"]
    # the default ubuntu provider uses invoke-rc.d, which apparently is
    # status-illy broken in ubuntu
    supports :status => false, :restart => true
    action [:enable, :start]
    only_if "[ -e /etc/swift/object-server.conf ] && [ -e /etc/swift/object.ring.gz ]"
  end

end

template "/etc/swift/object-server.conf" do
  source "object-server.conf.erb"
  owner "swift"
  group "swift"
  mode "0600"
  variables("bind_ip" => node["swift"]["network"]["object-bind-ip"],
            "bind_port" => node["swift"]["network"]["object-bind-port"])

  notifies :restart, "service[swift-object]", :immediately
  notifies :restart, "service[swift-object-replicator]", :immediately
  notifies :restart, "service[swift-object-updater]", :immediately
  notifies :restart, "service[swift-object-auditor]", :immediately
end

%w[ /var/swift /var/swift/recon ].each do |path|
  directory path do
  # Create the swift recon cache directory and set its permissions.
    owner "swift"
    group "swift"
    mode  00755
  
    action :create
  end
end

cron "swift-recon" do
  minute "*/5"
  command "swift-recon-cron /etc/swift/object-server.conf"
  user "swift"
end
