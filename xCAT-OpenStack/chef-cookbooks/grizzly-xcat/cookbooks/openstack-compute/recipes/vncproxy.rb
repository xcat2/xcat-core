#
# Cookbook Name:: openstack-compute
# Recipe:: vncproxy
#
# Copyright 2012, Rackspace US, Inc.
# Copyright 2013, Craig Tracey <craigtracey@gmail.com>
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

include_recipe "openstack-compute::nova-common"

platform_options = node["openstack"]["compute"]["platform"]

platform_options["compute_vncproxy_packages"].each do |pkg|
  package pkg do
    options platform_options["package_overrides"]

    action :upgrade
  end
end

# required for vnc console authentication
platform_options["compute_vncproxy_consoleauth_packages"].each do |pkg|
  package pkg do
    action :upgrade
  end
end

proxy_service = platform_options["compute_vncproxy_service"]

service proxy_service do
  service_name proxy_service
  supports :status => true, :restart => true
  subscribes :restart, resources("template[/etc/nova/nova.conf]")

  action :enable
end

service "nova-consoleauth" do
  service_name platform_options["compute_vncproxy_consoleauth_service"]
  supports :status => true, :restart => true
  subscribes :restart, resources("template[/etc/nova/nova.conf]")

  action [:enable, :start]
end
